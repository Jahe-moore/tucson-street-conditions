/* Reporting layer: a small star schema for Power BI plus three ready-made views. */
USE TucsonStreets;
GO

CREATE OR ALTER VIEW rpt.dim_ward AS
SELECT ward_id, ward_name FROM core.ward
UNION ALL SELECT 0, 'Outside city wards';
GO

CREATE OR ALTER VIEW rpt.dim_condition_band AS
SELECT band_id, band, min_oci, CASE WHEN max_oci > 100 THEN 100 ELSE max_oci END AS max_oci FROM core.condition_band;
GO

/* One row per active street segment. ward_id 0 = county, state or private road inside the city's layer. */
CREATE OR ALTER VIEW rpt.fact_segment AS
SELECT  s.cartegraph_id,
        s.street_class,
        s.street_name,
        CASE WHEN s.from_desc IS NULL AND s.to_desc IS NULL THEN s.street_name
             WHEN s.to_desc IS NULL OR s.from_desc = s.to_desc
                  THEN CONCAT(s.street_name, ' near ', ISNULL(s.from_desc, s.to_desc))
             WHEN s.from_desc IS NULL THEN CONCAT(s.street_name, ' near ', s.to_desc)
             ELSE CONCAT(s.street_name, ': ', s.from_desc, ' to ', s.to_desc) END AS segment_label,
        s.cartegraph_id + ' ' + s.street_name AS segment_key_label,
        s.complexity,
        s.jurisdiction,
        ISNULL(s.ward_id, 0)                     AS ward_id,
        b.band_id,
        s.oci,
        s.length_ft,
        s.length_ft / 5280.0                     AS length_mi,
        s.area_sqft,
        s.inspection_date,
        DATEDIFF(day, s.inspection_date, CAST(SYSDATETIME() AS date)) / 365.25 AS inspection_age_yrs,
        s.last_treated_date,
        s.is_protected,
        m.moratorium_end_date,
        CAST(CASE WHEN m.moratorium_end_date >= CAST(SYSDATETIME() AS date) THEN 1 ELSE 0 END AS bit) AS under_moratorium,
        s.mid_lat,
        s.mid_lon
FROM core.street_segment s
LEFT JOIN core.condition_band b ON s.oci >= b.min_oci AND s.oci < b.max_oci
LEFT JOIN core.moratorium m ON m.cartegraph_id = s.cartegraph_id
WHERE s.removed_from_source = 0;
GO

/* Ward scorecard. Average condition is weighted by pavement area, so a long arterial counts more than a cul-de-sac. */
CREATE OR ALTER VIEW rpt.v_ward_summary AS
SELECT  w.ward_id,
        w.ward_name,
        COUNT(*)                                                         AS segments,
        CAST(SUM(f.length_mi) AS decimal(8,1))                           AS miles,
        CAST(SUM(f.oci * f.area_sqft) / NULLIF(SUM(CASE WHEN f.oci IS NOT NULL THEN f.area_sqft END),0) AS decimal(5,1)) AS avg_oci_area_weighted,
        CAST(100.0 * SUM(CASE WHEN f.oci < 55 THEN f.area_sqft ELSE 0 END)
             / NULLIF(SUM(CASE WHEN f.oci IS NOT NULL THEN f.area_sqft END),0) AS decimal(5,1)) AS pct_area_poor_or_worse,
        SUM(CASE WHEN f.oci IS NULL THEN 1 ELSE 0 END)                   AS segments_no_score,
        SUM(CASE WHEN f.inspection_age_yrs > 3 OR f.inspection_date IS NULL THEN 1 ELSE 0 END) AS segments_inspection_over_3yrs,
        SUM(CASE WHEN f.under_moratorium = 1 THEN 1 ELSE 0 END)          AS segments_under_moratorium
FROM rpt.fact_segment f
JOIN rpt.dim_ward w ON w.ward_id = f.ward_id
GROUP BY w.ward_id, w.ward_name;
GO

/* Worst-first list: the selection rule the city's oversight commission uses (lowest condition first).
   Excludes segments still under a moratorium (just repaved) and roads the city doesn't maintain. */
CREATE OR ALTER VIEW rpt.v_worst_first AS
SELECT  RANK() OVER (PARTITION BY f.ward_id ORDER BY f.oci, f.area_sqft DESC) AS rank_in_ward,
        f.ward_id, f.cartegraph_id, f.street_class, f.segment_label, f.oci, f.area_sqft, f.inspection_date
FROM rpt.fact_segment f
WHERE f.oci IS NOT NULL AND f.ward_id <> 0 AND f.under_moratorium = 0 AND f.jurisdiction = 'City of Tucson';
GO

/* "Can we dig here?" Utility crews check this before cutting a street. */
CREATE OR ALTER VIEW rpt.v_dig_check AS
SELECT  f.cartegraph_id, f.segment_label, f.ward_id, f.oci, f.moratorium_end_date,
        CASE WHEN f.under_moratorium = 1 THEN 'Moratorium: restoration rules apply'
             ELSE 'No moratorium' END AS dig_status,
        DATEDIFF(day, CAST(SYSDATETIME() AS date), f.moratorium_end_date) AS days_left
FROM rpt.fact_segment f
WHERE f.street_class = 'Major';
GO

/* Latest result of every quality check, for the report's data-health page. */
CREATE OR ALTER VIEW rpt.v_quality AS
SELECT q.check_name, q.severity, q.row_count, q.detail, q.checked_at
FROM dq.check_result q
WHERE q.run_id = (SELECT MAX(run_id) FROM dq.check_result);
GO

/* Who may see which ward. Power BI's dynamic role filters on this with USERPRINCIPALNAME(). */
CREATE OR ALTER VIEW rpt.user_ward AS
SELECT user_name, ward_id FROM sec.user_ward;
GO

CREATE OR ALTER VIEW rpt.v_load_status AS
SELECT r.layer, r.mode, r.started_at, r.finished_at, r.status, r.rows_read, r.rows_inserted, r.rows_updated,
       r.rows_unchanged, r.error_message
FROM etl.run_log r
WHERE r.run_id IN (SELECT MAX(run_id) FROM etl.run_log GROUP BY layer);
GO
