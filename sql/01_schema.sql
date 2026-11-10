/* Tucson Street Conditions: database, schemas and tables.
   Source: City of Tucson public pavement layers (ArcGIS REST). Run with sqlcmd -i, or from Install-Database.ps1. */

IF DB_ID('TucsonStreets') IS NULL CREATE DATABASE TucsonStreets;
GO
USE TucsonStreets;
GO
IF SCHEMA_ID('etl')  IS NULL EXEC('CREATE SCHEMA etl');
IF SCHEMA_ID('stg')  IS NULL EXEC('CREATE SCHEMA stg');
IF SCHEMA_ID('core') IS NULL EXEC('CREATE SCHEMA core');
IF SCHEMA_ID('sec')  IS NULL EXEC('CREATE SCHEMA sec');
IF SCHEMA_ID('rpt')  IS NULL EXEC('CREATE SCHEMA rpt');
IF SCHEMA_ID('dq')   IS NULL EXEC('CREATE SCHEMA dq');
GO

/* ---- load log: one row per layer per run ---- */
IF OBJECT_ID('etl.run_log') IS NULL
CREATE TABLE etl.run_log (
    run_id          int IDENTITY PRIMARY KEY,
    layer           varchar(20)   NOT NULL,          -- major | minor | moratorium
    mode            varchar(12)   NOT NULL,          -- full | incremental
    started_at      datetime2(0)  NOT NULL DEFAULT SYSDATETIME(),
    finished_at     datetime2(0)  NULL,
    rows_read       int           NULL,
    rows_inserted   int           NULL,
    rows_updated    int           NULL,
    rows_unchanged  int           NULL,
    status          varchar(10)   NOT NULL DEFAULT 'running',  -- running | success | failed
    error_message   nvarchar(2000) NULL
);

/* ---- staging: raw text as it came off the API, reloaded every run ---- */
IF OBJECT_ID('stg.street_segment') IS NULL
CREATE TABLE stg.street_segment (
    cartegraph_id      varchar(20)  NOT NULL,
    street_name        nvarchar(100) NULL,
    from_desc          nvarchar(100) NULL,
    to_desc            nvarchar(100) NULL,
    complexity         varchar(40)  NULL,
    jurisdiction       varchar(60)  NULL,
    custodian          varchar(60)  NULL,
    ward_raw           varchar(20)  NULL,
    length_ft          float        NULL,
    width_ft           float        NULL,
    area_sqft          float        NULL,
    inspection_ms      bigint       NULL,   -- epoch milliseconds, converted in the merge
    oci                float        NULL,
    is_protected       smallint     NULL,
    replaced_ms        bigint       NULL,
    last_edited_ms     bigint       NULL,
    mid_lat            float        NULL,
    mid_lon            float        NULL
);

IF OBJECT_ID('stg.moratorium') IS NULL
CREATE TABLE stg.moratorium (
    cartegraph_id      varchar(20)  NOT NULL,
    street_name        nvarchar(100) NULL,
    from_name          nvarchar(150) NULL,
    to_name            nvarchar(150) NULL,
    last_recon_ms      bigint       NULL,
    moratorium_end_ms  bigint       NULL
);

/* ---- reference ---- */
IF OBJECT_ID('core.ward') IS NULL
BEGIN
    CREATE TABLE core.ward (ward_id tinyint PRIMARY KEY, ward_name varchar(20) NOT NULL);
    INSERT core.ward VALUES (1,'Ward 1'),(2,'Ward 2'),(3,'Ward 3'),(4,'Ward 4'),(5,'Ward 5'),(6,'Ward 6');
END

/* Condition bands follow the ASTM D6433 pavement rating scale (0 to 100). The city's OCI uses the same 0 to 100 range. */
IF OBJECT_ID('core.condition_band') IS NULL
BEGIN
    CREATE TABLE core.condition_band (
        band_id   tinyint PRIMARY KEY,
        band      varchar(20) NOT NULL,
        min_oci   decimal(5,2) NOT NULL,
        max_oci   decimal(5,2) NOT NULL
    );
    INSERT core.condition_band VALUES
        (1,'Failed',0,10),(2,'Serious',10,25),(3,'Very poor',25,40),(4,'Poor',40,55),
        (5,'Fair',55,70),(6,'Satisfactory',70,85),(7,'Good',85,100.01);
END

/* ---- core: one row per street segment, keyed on the city's Cartegraph asset ID ---- */
IF OBJECT_ID('core.street_segment') IS NULL
CREATE TABLE core.street_segment (
    cartegraph_id      varchar(20)  NOT NULL PRIMARY KEY,
    street_class       varchar(5)   NOT NULL,          -- Major | Minor
    street_name        nvarchar(100) NULL,
    from_desc          nvarchar(100) NULL,
    to_desc            nvarchar(100) NULL,
    complexity         varchar(40)  NULL,
    jurisdiction       varchar(60)  NULL,
    custodian          varchar(60)  NULL,
    ward_raw           varchar(20)  NULL,
    ward_id            tinyint      NULL REFERENCES core.ward(ward_id),  -- NULL when outside the six wards
    length_ft          float        NULL,
    width_ft           float        NULL,
    area_sqft          float        NULL,
    inspection_date    date         NULL,
    oci                decimal(5,2) NULL,
    is_protected       bit          NOT NULL DEFAULT 0,
    last_treated_date  date         NULL,
    source_edited_at   datetime2(0) NULL,
    mid_lat            decimal(9,6) NULL,
    mid_lon            decimal(9,6) NULL,
    row_hash           varbinary(32) NOT NULL,
    first_loaded_run   int          NOT NULL,
    last_changed_run   int          NOT NULL,
    removed_from_source bit         NOT NULL DEFAULT 0
);

/* Every time a load sees a segment's score or inspection date change, the old and new values land here.
   This is what lets the report show trend over time; the city's layer only holds the latest score. */
IF OBJECT_ID('core.condition_history') IS NULL
CREATE TABLE core.condition_history (
    history_id         int IDENTITY PRIMARY KEY,
    cartegraph_id      varchar(20)  NOT NULL,
    run_id             int          NOT NULL REFERENCES etl.run_log(run_id),
    oci                decimal(5,2) NULL,
    inspection_date    date         NULL,
    recorded_at        datetime2(0) NOT NULL DEFAULT SYSDATETIME()
);

IF OBJECT_ID('core.moratorium') IS NULL
CREATE TABLE core.moratorium (
    cartegraph_id        varchar(20)  NOT NULL PRIMARY KEY,
    street_name          nvarchar(100) NULL,
    from_name            nvarchar(150) NULL,
    to_name              nvarchar(150) NULL,
    last_recon_date      date NULL,
    moratorium_end_date  date NULL,
    last_changed_run     int  NOT NULL
);

/* ---- who may see which ward (used by SQL row-level security and the Power BI dynamic role) ---- */
IF OBJECT_ID('sec.user_ward') IS NULL
CREATE TABLE sec.user_ward (
    user_name   sysname     NOT NULL,   -- database user, or Power BI sign-in (UPN)
    ward_id     tinyint     NOT NULL REFERENCES core.ward(ward_id),
    PRIMARY KEY (user_name, ward_id)
);

/* ---- data quality results: one row per check per run ---- */
IF OBJECT_ID('dq.check_result') IS NULL
CREATE TABLE dq.check_result (
    run_id      int          NOT NULL,
    check_name  varchar(60)  NOT NULL,
    severity    varchar(8)   NOT NULL,   -- error | warn | info
    row_count   int          NOT NULL,
    detail      nvarchar(300) NULL,
    checked_at  datetime2(0) NOT NULL DEFAULT SYSDATETIME(),
    PRIMARY KEY (run_id, check_name)
);
GO
