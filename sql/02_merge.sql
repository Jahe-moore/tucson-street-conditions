/* Merge staging into core. Called by the PowerShell loader after each bulk copy. */
USE TucsonStreets;
GO

/* Epoch milliseconds to a date. The city uses 1900 and 1905 as "unknown" placeholders, so anything before 1950 is NULL. */
CREATE OR ALTER FUNCTION etl.ms_to_date (@ms bigint)
RETURNS date WITH SCHEMABINDING AS
BEGIN
    IF @ms IS NULL RETURN NULL;
    DECLARE @d date = DATEADD(day, CAST(FLOOR(@ms / 86400000.0) AS int), CAST('1970-01-01' AS date));
    RETURN CASE WHEN @d < '1950-01-01' THEN NULL ELSE @d END;
END
GO

CREATE OR ALTER FUNCTION etl.ms_to_datetime (@ms bigint)
RETURNS datetime2(0) WITH SCHEMABINDING AS
BEGIN
    IF @ms IS NULL OR @ms < 0 RETURN NULL;
    RETURN DATEADD(second, CAST((@ms % 86400000) / 1000 AS int),
           DATEADD(day, CAST(@ms / 86400000 AS int), CAST('1970-01-01' AS datetime2(0))));
END
GO

CREATE OR ALTER PROCEDURE etl.usp_merge_segments
    @run_id int, @street_class varchar(5), @mode varchar(12)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;

    /* clean once, hash once */
    SELECT  s.cartegraph_id,
            @street_class                              AS street_class,
            NULLIF(LTRIM(RTRIM(s.street_name)),'')     AS street_name,
            NULLIF(LTRIM(RTRIM(s.from_desc)),'')       AS from_desc,
            NULLIF(LTRIM(RTRIM(s.to_desc)),'')         AS to_desc,
            NULLIF(s.complexity,'')                    AS complexity,
            NULLIF(s.jurisdiction,'')                  AS jurisdiction,
            NULLIF(s.custodian,'')                     AS custodian,
            NULLIF(s.ward_raw,'')                      AS ward_raw,
            CASE WHEN s.ward_raw IN ('1','2','3','4','5','6') THEN CAST(s.ward_raw AS tinyint) END AS ward_id,
            s.length_ft, s.width_ft,
            CASE WHEN s.area_sqft > 0 THEN s.area_sqft END AS area_sqft,
            etl.ms_to_date(s.inspection_ms)            AS inspection_date,
            CAST(s.oci AS decimal(5,2))                AS oci,
            CAST(ISNULL(s.is_protected,0) AS bit)      AS is_protected,
            etl.ms_to_date(s.replaced_ms)              AS last_treated_date,
            etl.ms_to_datetime(s.last_edited_ms)       AS source_edited_at,
            CAST(s.mid_lat AS decimal(9,6))            AS mid_lat,
            CAST(s.mid_lon AS decimal(9,6))            AS mid_lon
    INTO #src
    FROM stg.street_segment s;

    ALTER TABLE #src ADD row_hash varbinary(32);
    UPDATE #src SET row_hash = HASHBYTES('SHA2_256', CONCAT_WS('|', street_name, from_desc, to_desc, complexity,
        jurisdiction, custodian, ward_raw, length_ft, width_ft, area_sqft, inspection_date, oci, is_protected,
        last_treated_date, source_edited_at, mid_lat, mid_lon));

    /* A full load that comes back much smaller than the last good one is probably a partial download.
       Stop before the merge would flag thousands of real streets as removed. */
    IF @mode = 'full'
    BEGIN
        DECLARE @got int = (SELECT COUNT(*) FROM #src);
        DECLARE @last int = (SELECT TOP 1 rows_read FROM etl.run_log
                             WHERE layer = LOWER(@street_class) AND mode = 'full' AND status = 'success' AND run_id < @run_id
                             ORDER BY run_id DESC);
        IF @last IS NOT NULL AND @got < 0.9 * @last
        BEGIN
            DECLARE @msg nvarchar(200) = CONCAT('Partial download: ', @got, ' rows against ', @last,
                                                ' on the last full load. Nothing was changed.');
            THROW 50001, @msg, 1;
        END
    END

    DECLARE @changes TABLE (action nvarchar(10), cartegraph_id varchar(20), old_oci decimal(5,2), old_insp date,
                            new_oci decimal(5,2), new_insp date);

    BEGIN TRAN;

    MERGE core.street_segment AS t
    USING #src AS s ON t.cartegraph_id = s.cartegraph_id
    WHEN MATCHED AND (t.row_hash <> s.row_hash OR t.removed_from_source = 1) THEN UPDATE SET
        street_class = s.street_class, street_name = s.street_name, from_desc = s.from_desc, to_desc = s.to_desc,
        complexity = s.complexity, jurisdiction = s.jurisdiction, custodian = s.custodian, ward_raw = s.ward_raw,
        ward_id = s.ward_id, length_ft = s.length_ft, width_ft = s.width_ft, area_sqft = s.area_sqft,
        inspection_date = s.inspection_date, oci = s.oci, is_protected = s.is_protected,
        last_treated_date = s.last_treated_date, source_edited_at = s.source_edited_at,
        mid_lat = s.mid_lat, mid_lon = s.mid_lon, row_hash = s.row_hash,
        last_changed_run = @run_id, removed_from_source = 0
    WHEN NOT MATCHED BY TARGET THEN INSERT
        (cartegraph_id, street_class, street_name, from_desc, to_desc, complexity, jurisdiction, custodian, ward_raw,
         ward_id, length_ft, width_ft, area_sqft, inspection_date, oci, is_protected, last_treated_date,
         source_edited_at, mid_lat, mid_lon, row_hash, first_loaded_run, last_changed_run)
        VALUES (s.cartegraph_id, s.street_class, s.street_name, s.from_desc, s.to_desc, s.complexity, s.jurisdiction,
         s.custodian, s.ward_raw, s.ward_id, s.length_ft, s.width_ft, s.area_sqft, s.inspection_date, s.oci,
         s.is_protected, s.last_treated_date, s.source_edited_at, s.mid_lat, s.mid_lon, s.row_hash, @run_id, @run_id)
    OUTPUT $action, inserted.cartegraph_id, deleted.oci, deleted.inspection_date, inserted.oci, inserted.inspection_date
    INTO @changes;

    /* history: first sighting, or a new score / new inspection */
    INSERT core.condition_history (cartegraph_id, run_id, oci, inspection_date)
    SELECT cartegraph_id, @run_id, new_oci, new_insp
    FROM @changes
    WHERE action = 'INSERT'
       OR ISNULL(old_oci, -1) <> ISNULL(new_oci, -1)
       OR ISNULL(old_insp, '1900-01-01') <> ISNULL(new_insp, '1900-01-01');

    /* a full load is the whole layer, so anything missing was removed by the city */
    DECLARE @removed int = 0;
    IF @mode = 'full'
    BEGIN
        UPDATE t SET removed_from_source = 1, last_changed_run = @run_id
        FROM core.street_segment t
        WHERE t.street_class = @street_class AND t.removed_from_source = 0
          AND NOT EXISTS (SELECT 1 FROM #src s WHERE s.cartegraph_id = t.cartegraph_id);
        SET @removed = @@ROWCOUNT;
    END

    DECLARE @read int = (SELECT COUNT(*) FROM #src),
            @ins  int = (SELECT COUNT(*) FROM @changes WHERE action = 'INSERT'),
            @upd  int = (SELECT COUNT(*) FROM @changes WHERE action = 'UPDATE');

    UPDATE etl.run_log
       SET rows_read = @read, rows_inserted = @ins, rows_updated = @upd + @removed,
           rows_unchanged = @read - @ins - @upd
     WHERE run_id = @run_id;

    COMMIT;
END
GO

CREATE OR ALTER PROCEDURE etl.usp_merge_moratorium @run_id int
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @c TABLE (action nvarchar(10));
    BEGIN TRAN;
    MERGE core.moratorium AS t
    USING (SELECT cartegraph_id,
                  NULLIF(LTRIM(RTRIM(street_name)),'') AS street_name,
                  NULLIF(LTRIM(RTRIM(from_name)),'')   AS from_name,
                  NULLIF(LTRIM(RTRIM(to_name)),'')     AS to_name,
                  etl.ms_to_date(last_recon_ms)        AS last_recon_date,
                  etl.ms_to_date(moratorium_end_ms)    AS moratorium_end_date
           FROM stg.moratorium) AS s
    ON t.cartegraph_id = s.cartegraph_id
    WHEN MATCHED AND (ISNULL(t.moratorium_end_date,'1900-01-01') <> ISNULL(s.moratorium_end_date,'1900-01-01')
                   OR ISNULL(t.last_recon_date,'1900-01-01')     <> ISNULL(s.last_recon_date,'1900-01-01')
                   OR ISNULL(t.street_name,'') <> ISNULL(s.street_name,'')
                   OR ISNULL(t.from_name,'')   <> ISNULL(s.from_name,'')
                   OR ISNULL(t.to_name,'')     <> ISNULL(s.to_name,'')) THEN UPDATE SET
        street_name = s.street_name, from_name = s.from_name, to_name = s.to_name,
        last_recon_date = s.last_recon_date, moratorium_end_date = s.moratorium_end_date, last_changed_run = @run_id
    WHEN NOT MATCHED BY TARGET THEN INSERT
        (cartegraph_id, street_name, from_name, to_name, last_recon_date, moratorium_end_date, last_changed_run)
        VALUES (s.cartegraph_id, s.street_name, s.from_name, s.to_name, s.last_recon_date, s.moratorium_end_date, @run_id)
    OUTPUT $action INTO @c;

    DECLARE @read int = (SELECT COUNT(*) FROM stg.moratorium);
    UPDATE etl.run_log SET rows_read = @read,
        rows_inserted = (SELECT COUNT(*) FROM @c WHERE action = 'INSERT'),
        rows_updated  = (SELECT COUNT(*) FROM @c WHERE action = 'UPDATE'),
        rows_unchanged = @read - (SELECT COUNT(*) FROM @c)
    WHERE run_id = @run_id;
    COMMIT;
END
GO
