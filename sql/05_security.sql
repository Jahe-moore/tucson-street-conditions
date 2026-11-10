/* Role-based access.
   city_wide_reader : every ward (city engineers, the oversight commission)
   ward_reader      : only the wards listed for that user in sec.user_ward (a council office)
   The filter is SQL Server row-level security, so it holds no matter which tool runs the query. */
USE TucsonStreets;
GO

IF DATABASE_PRINCIPAL_ID('city_wide_reader') IS NULL CREATE ROLE city_wide_reader;
IF DATABASE_PRINCIPAL_ID('ward_reader')      IS NULL CREATE ROLE ward_reader;
GRANT SELECT ON SCHEMA::rpt TO city_wide_reader;
GRANT SELECT ON SCHEMA::rpt TO ward_reader;
GO

/* the policy locks the function, so drop it first and recreate it below (keeps this script rerunnable) */
IF EXISTS (SELECT 1 FROM sys.security_policies WHERE name = 'ward_policy') DROP SECURITY POLICY sec.ward_policy;
GO

CREATE OR ALTER FUNCTION sec.fn_ward_filter (@ward_id tinyint)
RETURNS TABLE WITH SCHEMABINDING AS
RETURN
    SELECT 1 AS allowed
    WHERE IS_MEMBER('city_wide_reader') = 1
       OR IS_MEMBER('db_owner') = 1
       OR EXISTS (SELECT 1 FROM sec.user_ward uw WHERE uw.user_name = USER_NAME() AND uw.ward_id = @ward_id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.security_policies WHERE name = 'ward_policy')
    CREATE SECURITY POLICY sec.ward_policy
        ADD FILTER PREDICATE sec.fn_ward_filter(ward_id) ON core.street_segment
        WITH (STATE = ON);
GO

/* Demo users with no login, used by the tests and for screenshots (EXECUTE AS USER = 'ward3_office'). */
IF DATABASE_PRINCIPAL_ID('ward3_office')   IS NULL CREATE USER ward3_office   WITHOUT LOGIN;
IF DATABASE_PRINCIPAL_ID('ward5_office')   IS NULL CREATE USER ward5_office   WITHOUT LOGIN;
IF DATABASE_PRINCIPAL_ID('city_engineer')  IS NULL CREATE USER city_engineer  WITHOUT LOGIN;
ALTER ROLE ward_reader      ADD MEMBER ward3_office;
ALTER ROLE ward_reader      ADD MEMBER ward5_office;
ALTER ROLE city_wide_reader ADD MEMBER city_engineer;

MERGE sec.user_ward AS t
USING (VALUES ('ward3_office', 3), ('ward5_office', 5),
              -- sample Power BI sign-ins for the dynamic role (test with "View as > Other user")
              ('ward3.office@example.org', 3), ('ward5.office@example.org', 5),
              ('district.lead@example.org', 2), ('district.lead@example.org', 4)) AS s (user_name, ward_id)
ON t.user_name = s.user_name AND t.ward_id = s.ward_id
WHEN NOT MATCHED THEN INSERT VALUES (s.user_name, s.ward_id);
GO
