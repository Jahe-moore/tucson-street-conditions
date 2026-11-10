/* Data quality checks, run after every load. Each check writes one row to dq.check_result.
   An 'error' row makes the loader report the run as failed. */
USE TucsonStreets;
GO

CREATE OR ALTER PROCEDURE dq.usp_run_checks @run_id int
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @today date = CAST(SYSDATETIME() AS date);
    DECLARE @r TABLE (check_name varchar(60), severity varchar(8), row_count int, detail nvarchar(300));

    /* the load itself */
    INSERT @r SELECT 'row_count_drop', 'error', COUNT(*),
        'A layer returned under 90% of its previous successful row count (partial download?)'
    FROM etl.run_log cur
    CROSS APPLY (SELECT TOP 1 rows_read FROM etl.run_log p
                 WHERE p.layer = cur.layer AND p.status = 'success' AND p.mode = 'full' AND p.run_id < cur.run_id
                 ORDER BY p.run_id DESC) prev
    WHERE cur.run_id IN (SELECT MAX(run_id) FROM etl.run_log WHERE mode = 'full' GROUP BY layer)
      AND cur.rows_read < 0.9 * prev.rows_read;

    INSERT @r SELECT 'oci_out_of_range', 'error', COUNT(*), 'Condition score below 0 or above 100'
    FROM core.street_segment WHERE removed_from_source = 0 AND (oci < 0 OR oci > 100);

    INSERT @r SELECT 'moratorium_without_segment', 'error', COUNT(*), 'Moratorium row with no matching street segment'
    FROM core.moratorium m WHERE NOT EXISTS (SELECT 1 FROM core.street_segment s WHERE s.cartegraph_id = m.cartegraph_id);

    /* the city's data */
    INSERT @r SELECT 'missing_condition_score', 'warn', COUNT(*), 'Segment has no OCI'
    FROM core.street_segment WHERE removed_from_source = 0 AND oci IS NULL;

    INSERT @r SELECT 'city_road_without_ward', 'warn', COUNT(*), 'City of Tucson road with a blank ward'
    FROM core.street_segment WHERE removed_from_source = 0 AND jurisdiction = 'City of Tucson' AND ward_id IS NULL;

    INSERT @r SELECT 'county_district_in_ward_field', 'info', COUNT(*), 'Ward field holds a county supervisor district (BOS n)'
    FROM core.street_segment WHERE removed_from_source = 0 AND ward_raw LIKE 'BOS%';

    INSERT @r SELECT 'inspection_over_3_years', 'warn', COUNT(*), 'Last inspection more than 3 years ago'
    FROM core.street_segment WHERE removed_from_source = 0 AND inspection_date < DATEADD(year, -3, @today);

    INSERT @r SELECT 'no_inspection_date', 'warn', COUNT(*), 'Segment has no inspection date'
    FROM core.street_segment WHERE removed_from_source = 0 AND inspection_date IS NULL;

    INSERT @r SELECT 'missing_pavement_area', 'warn', COUNT(*), 'Area blank or zero; left out of area-weighted averages'
    FROM core.street_segment WHERE removed_from_source = 0 AND area_sqft IS NULL;

    INSERT @r SELECT 'removed_by_city', 'info', COUNT(*), 'Segment dropped from the city layer since an earlier load'
    FROM core.street_segment WHERE removed_from_source = 1;

    DELETE dq.check_result WHERE run_id = @run_id;
    INSERT dq.check_result (run_id, check_name, severity, row_count, detail)
    SELECT @run_id, check_name, severity, row_count, detail FROM @r;

    SELECT check_name, severity, row_count, detail FROM @r ORDER BY CASE severity WHEN 'error' THEN 1 WHEN 'warn' THEN 2 ELSE 3 END, check_name;
END
GO
