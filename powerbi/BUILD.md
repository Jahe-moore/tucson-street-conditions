# How the Power BI report is built and rebuilt

The report is a Power BI project (`Tucson Street Conditions.pbip`): the model is TMDL text and the report is PBIR JSON,
so every measure, relationship, role and visual is in git and reviewable line by line. One script writes all of it.

## Open it
| Step | Do this |
|---|---|
| 1 | Load the database first: `.\etl\Install-Database.ps1`, then `.\etl\Load-StreetData.ps1`. |
| 2 | Open `powerbi\Tucson Street Conditions.pbip` in Power BI Desktop. It opens with no data; the project stores the model, not a copy of the rows. |
| 3 | **Home > Refresh**. Credentials: **Windows**, use my current credentials. If asked about encryption, OK to connect unencrypted (local SQL Server only). |
| 4 | Check page 1 against the database: 68.1 average, 36.9% poor or worse, 1,837 miles, 4,540 inspected over 3 years ago, 302 under moratorium (data as of 2026-11-09). |

## Rebuild it
```powershell
python powerbi\tools\build_pbip.py               # rewrites the whole model and all three pages
python powerbi\tools\build_pbip.py worst,health  # only these pages
```
Then open the `.pbip` and Refresh. The script is the source; edits made in Desktop and saved are overwritten on the next run.

## What's in it
| Part | Detail |
|---|---|
| Source | SQL Server `localhost\SQLEXPRESS`, database `TucsonStreets`, Import mode. Views: `rpt.fact_segment`, `dim_ward`, `dim_condition_band`, `user_ward`, `v_quality`, `v_load_status`, `v_worst_first` |
| Model | `dim_ward` and `dim_condition_band` one-to-many into `fact_segment`, single direction. `user_ward`, `v_quality`, `v_load_status` stay unconnected |
| Measures | Same as `measures.dax`: area-weighted average condition, share of pavement poor or worse (scored area only), miles, stale inspections, moratorium count, viewing-as, data-as-of |
| Page 1, Ward scorecard | Five headline cards, average condition by ward, condition mix by ward, street-type slicer |
| Page 2, Worst first | Lowest-scoring city streets with no moratorium, ranked within ward; failed or serious segments by ward |
| Page 3, Data health | The ten quality checks, last load per layer, segments by year of last inspection |
| Roles | `Ward 3`, `Ward 5` (static), `City-wide`, `Ward office` (dynamic, reads `user_ward` with `USERPRINCIPALNAME()`) |
| Colors | One per condition band: Failed `#7F1414`, Serious `#B91C1C`, Very poor `#D4850A`, Poor `#E8B64C`, Fair `#9AA3AE`, Satisfactory `#6FB08C`, Good `#1A7A4A`. The map and the site merge Failed and Serious into one band, `#B91C1C` |

## Checked on 2026-11-09
- **View as Ward 3:** 67.5 average, 39.3% poor or worse, 241 miles, 17 under moratorium, only Ward 3 in every visual. Matches `rpt.v_ward_summary`.
- **View as Ward office** with Jake's own account: no data, as it should be (he is not in `user_ward`).
- **Bug found and fixed:** `% Poor or Worse` counted unscored streets as poor, because DAX treats a blank as 0 and blank < 55 is true. 37.9% became 36.9%, matching SQL.
- Not yet run: View as Ward office + Other user `district.lead@example.org` (should show Wards 2 and 4). Desktop's View as dialog would not take typed input from a script.

## Two things to say in an interview
- **Two layers of security.** SQL Server row-level security (`sql\05_security.sql`) limits what each database user can read, whatever tool they use. Power BI roles limit what each report viewer sees. Here the report connects with my own Windows account, which sees everything, so the Power BI roles do the filtering. In production the report would refresh through a gateway account and the city would assign people to roles in the Power BI Service.
- **Desktop only simulates roles.** "View as" proves the filters work; real per-person enforcement needs the report published to the Power BI Service (Pro license). "Publish to web" can't be used with row-level security, so the public proof is screenshots.
