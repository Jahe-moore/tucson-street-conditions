# Runbook: Tucson Street Conditions loader

For whoever keeps this running. Everything lives in the repo; the database is `TucsonStreets` on `localhost\SQLEXPRESS`.

## What runs when

| Job | When | Command | Notes |
|---|---|---|---|
| Nightly load | Daily 2:15 AM | `Load-StreetData.ps1 -Mode incremental` | Only rows the City edited since the last load. The moratorium layer is always pulled in full (2,748 rows, about 1 s) |
| Weekly full load | Sunday 3:15 AM | `Load-StreetData.ps1 -Mode full` | Catches segments the City deleted |

Both are created by `.\etl\Register-Task.ps1` and removed by `.\etl\Register-Task.ps1 -Unregister`.
**Not registered yet.** They run as the signed-in Windows user, only while signed in.

## Run by hand

```powershell
.\etl\Install-Database.ps1                          # first time, or after any sql/ change. Safe to rerun
.\etl\Load-StreetData.ps1                           # full load, all three layers
.\etl\Load-StreetData.ps1 -Mode incremental
.\etl\Load-StreetData.ps1 -Layers moratorium        # one layer
```

Exit code 0 = everything loaded and no error-level check fired. 1 = something needs a look.

## Where to look

| Place | Holds |
|---|---|
| `logs\load_YYYY-MM-DD.log` | Every line the loader printed, including retries and each check |
| `etl.run_log` | One row per layer per run: rows read / new / changed / unchanged, status, error text |
| `dq.check_result` | Every check's count for every run |
| `rpt.v_load_status` | Latest run per layer |
| `rpt.v_quality` | Latest check results (also the report's data health page) |

```sql
SELECT TOP 10 * FROM etl.run_log ORDER BY run_id DESC;
SELECT * FROM rpt.v_quality ORDER BY severity, check_name;
```

## Data quality checks

| Check | Level | Means | What to do | Count 2026-11-09 |
|---|---|---|---|---|
| row_count_drop | error | A full load got under 90% of the last full load's rows | Probably a partial download or a City outage. Rerun the full load. If it repeats, check the layer on the City's site before trusting the report | 0 |
| oci_out_of_range | error | A score below 0 or above 100 | Bad value at the source. Report to City GIS with the CartegraphID | 0 |
| moratorium_without_segment | error | A moratorium row with no matching street | City added a moratorium before the segment, or the IDs changed. Rerun full; report if it stays | 0 |
| missing_condition_score | warn | Segment has no OCI | Left out of averages. Ask TDOT if it's unrated or a data gap | 141 |
| city_road_without_ward | warn | City road with a blank ward | Shows under "Outside city wards" and is hidden from ward offices. Report to City GIS | 6 |
| inspection_over_3_years | warn | Last inspected more than 3 years ago | Score may be stale. Not a load problem | 4,540 |
| no_inspection_date | warn | No inspection date | Not a load problem | 119 |
| missing_pavement_area | warn | Area blank or zero | Left out of area-weighted averages | 3 |
| county_district_in_ward_field | info | Ward field says "BOS n" (county supervisor district) | Expected for county roads in the City layer | 19 |
| removed_by_city | info | Segment gone from the City layer since an earlier load | Kept, flagged, hidden from the report | 0 |

## Common failures

| Symptom | Likely cause | Fix |
|---|---|---|
| Log shows "Attempt n failed", run_log status `failed` | City ArcGIS service down or slow | Nothing to fix here. The next scheduled run picks it up. Run by hand once the City's map loads |
| `failed` with "Invalid column name" or a field missing | City renamed or dropped a field | Compare the layer's field list (`<layer url>?f=json`) with `ConvertTo-SegmentTable` in `etl\StreetData.psm1`; update the mapping and `sql\01_schema.sql` |
| `row_count_drop` fires | Partial download, or the City really removed many segments | Rerun the full load. If the count stays low, confirm with City GIS before trusting the report |
| "A network-related or instance-specific error" | SQL Server service stopped | `Get-Service 'MSSQL$SQLEXPRESS'`, then `Start-Service 'MSSQL$SQLEXPRESS'` from an admin shell |
| "Duplicate CartegraphID in source" | City layer has a duplicate key | Load stops before touching data. Report the IDs to City GIS |
| "Unknown layer(s)" | Typo in `-Layers` | Use major, minor, moratorium |

## Give someone access

Ward office (sees only listed wards):

```sql
CREATE USER ward2_office WITHOUT LOGIN;            -- or FOR LOGIN [DOMAIN\name] in a real deployment
ALTER ROLE ward_reader ADD MEMBER ward2_office;
INSERT sec.user_ward (user_name, ward_id) VALUES ('ward2_office', 2);
```

City-wide: `ALTER ROLE city_wide_reader ADD MEMBER <user>;`

Power BI dynamic role: add the person's sign-in email to `sec.user_ward` with their ward(s), then refresh the report.

Check what someone sees: `EXECUTE AS USER = 'ward2_office'; SELECT COUNT(*) FROM rpt.fact_segment; REVERT;`

## Rebuild from nothing

1. `.\etl\Install-Database.ps1` (creates the database, schemas, tables, procedures, views, security; rerunnable)
2. `.\etl\Load-StreetData.ps1` (full load, about 20 s)
3. Score history starts over from that day; the City layer has no history to rebuild from.

## Tests

`Invoke-Pester .\tests` builds and drops its own `TucsonStreets_Test` database. Safe to run anytime.
