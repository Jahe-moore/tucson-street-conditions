# Test plan: Tucson Street Conditions

Version 1.0 · 2026-11-09 · Requirement IDs refer to [requirements.md](requirements.md)

## How to run

```powershell
Import-Module Pester -RequiredVersion 3.4.0
Invoke-Pester .\tests          # builds TucsonStreets_Test, runs, drops it. Never touches TucsonStreets.
```

**Last run: 2026-11-09, Pester 3.4.0. 16 passed, 0 failed, 1.24 s.**

## Automated cases (tests/StreetData.Tests.ps1)

| ID | Type | What it proves | Pester test name | Requirement | Result |
|---|---|---|---|---|---|
| TC-01 | Unit | A street line's middle point becomes its map point | takes the middle vertex of a line as its map point | FR-17 | Pass |
| TC-02 | Unit | A row with no geometry doesn't crash the load | returns nothing for a missing geometry | FR-01 | Pass |
| TC-03 | Unit | Cross streets map to the label fields; API nulls become database nulls | maps cross streets and turns API nulls into database nulls | FR-12 | Pass |
| TC-04 | Unit | Duplicate keys are caught before the merge | finds duplicate keys before they reach the merge | FR-04 | Pass |
| TC-05 | Unit | A web call that fails twice then works still returns | retries a failing call and returns once it works | FR-02 | Pass |
| TC-06 | Unit | After the last attempt the error comes through | gives up after the last attempt | FR-02 | Pass |
| TC-07 | Integration | First load inserts every row | inserts every row on the first load | FR-03 | Pass |
| TC-08 | Regression | Loading the same data again changes nothing | changes nothing when the same data loads again | FR-03 | Pass |
| TC-09 | Integration | "BOS 1" and blank wards become no ward | keeps only wards 1 to 6 and turns county districts and blanks into no ward | FR-07 | Pass |
| TC-10 | Integration | The 1900 placeholder date is stored as unknown | treats the 1900 placeholder date as unknown | FR-08 | Pass |
| TC-11 | Integration | A score change writes a history row and counts as one update | records a history row when a score changes | FR-09, BR-05 | Pass |
| TC-12 | Integration | Missing rows are flagged removed on a full load, left alone on an incremental one | flags a segment the city removed, but only on a full load | FR-06 | Pass |
| TC-13 | Security | Ward 5's office sees only Ward 5; the city engineer sees everything | shows a ward office only its own ward | FR-13, BR-01 | Pass |
| TC-14 | Security | A ward user can't read the base table at all, only the report views | blocks a ward office from reading the base table directly | FR-13 | Pass |
| TC-15 | Integration | A score of 150 trips the out-of-range error check | fails the quality check when a score is out of range | FR-10, BR-04 | Pass |
| TC-16 | Integration | A full load 75% smaller than the last one trips the row-count check | fails the quality check when a full load comes back much smaller than the last one | FR-10, BR-04 | Pass |

## Manual cases

| ID | Type | Steps | Expected | Requirement | Result |
|---|---|---|---|---|---|
| TC-17 | End to end | `.\etl\Load-StreetData.ps1` on an empty database | Exit 0; run_log shows 2,831 / 8,824 / 2,748 rows, status success; under 2 minutes | FR-01, FR-11, NFR-01, NFR-03 | Pass, 16 s (2026-11-09) |
| TC-18 | End to end | Run again with `-Mode incremental` | Only rows edited since the last load are downloaded (0 that day) | FR-05 | Pass (2026-11-09) |
| TC-19 | Regression | Run `.\etl\Install-Database.ps1` twice in a row on a loaded database | Both runs finish; row counts unchanged | NFR-02 | Pass (2026-11-09) |
| TC-20 | UAT, security | Power BI Desktop: Modeling > View as > role "Ward 3", then "Ward 5" | Every visual shows only that ward; Ward 3 has 1,539 segments, Ward 5 has 1,988 | FR-14, BR-01 | Not run yet |
| TC-21 | UAT, security | View as > Other user `district.lead@example.org` with the dynamic role | Wards 2 and 4 only; `ward3.office@example.org` sees Ward 3 only | FR-14, BR-01 | Not run yet |
| TC-22 | UAT | Compare the report's ward cards with `SELECT * FROM rpt.v_ward_summary` | Same numbers (e.g. Ward 3 area-weighted condition 67.5, 39.3% poor or worse) | FR-15, BR-02 | Not run yet |
| TC-23 | UAT | ArcGIS Online map: open, click three segments, toggle ward boundaries | Colors match the band table; pop-up shows street, OCI, inspection date; wards line up | FR-17, BR-02 | Not run yet |
| TC-24 | UAT | `SELECT * FROM rpt.v_dig_check WHERE dig_status LIKE 'Moratorium%'`, pick one, check the same segment on the City's map | Status and end date agree with the City layer | FR-16, BR-03 | Not run yet |
| TC-25 | UAT | Data health page vs `SELECT * FROM rpt.v_quality` | Every check and count matches | FR-15, BR-04 | Not run yet |
| TC-26 | Failure | Run the loader with the network off (or a bad URL in `StreetData.psm1`) | 4 attempts logged, run_log status failed with the error text, exit code 1 | FR-02, NFR-04 | Not run yet |

## Defects found during testing

| # | Found by | Problem | Fix |
|---|---|---|---|
| D1 | TC-19 | `05_security.sql` failed on rerun: the security policy locks its filter function | Drop the policy first, recreate it after |
| D2 | TC-19 | SQL helper left a reader open when a query returned two result sets | Read results with a data adapter that closes the reader |
| D3 | TC-17 | `-Layers major,minor` through `powershell -File` arrived as one string; the run failed (safely, and logged) | Split on commas and reject unknown layer names up front |
| D4 | Review | Segment labels showed position codes ("NPI to CL") | Use the cross-street fields instead |
