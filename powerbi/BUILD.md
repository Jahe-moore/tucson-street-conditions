# Build the Power BI report (about 45 minutes)

Build this yourself, click by click. An interviewer will ask you to walk through it, and you need to have made every choice.
The database already holds the data (`etl\Load-StreetData.ps1`); this page turns it into a three-page report with ward security.

## 1. Connect (5 min)
| Step | Do this |
|---|---|
| 1 | Power BI Desktop > **File > Options > Preview features**: turn on **Power BI Project (.pbip) save option**. Restart. |
| 2 | **Options > Security > Map and filled map visuals**: turn on (needed for the map page). |
| 3 | **Home > Get data > SQL Server**. Server `localhost\SQLEXPRESS`, Database `TucsonStreets`, mode **Import**. |
| 4 | Credentials: **Windows**, use my current credentials. If asked about encryption, OK to connect unencrypted (local only). |
| 5 | Tick these 6 views under `rpt`: `fact_segment`, `dim_ward`, `dim_condition_band`, `v_quality`, `v_load_status`, `user_ward`. **Load**. (`v_ward_summary` and `v_worst_first` are for SQL users; the report computes the same numbers with measures so slicers work.) |
| 6 | Rename each table in the Data pane to drop the `rpt ` prefix (e.g. `fact_segment`). The measures use the short names. |

## 2. Model (10 min)
| Step | Do this |
|---|---|
| 1 | **Model view**. Relationships: `dim_ward[ward_id]` 1 to many `fact_segment[ward_id]`; `dim_condition_band[band_id]` 1 to many `fact_segment[band_id]`. Cross-filter direction **Single**. Delete anything Power BI auto-detected that isn't on this list. |
| 2 | Leave `user_ward`, `v_quality`, `v_load_status` **unconnected**. `user_ward` is only read by the security role. |
| 3 | Sort `dim_condition_band[band]` by `band_id` (select column > Column tools > Sort by column), so bands run Failed to Good. |
| 4 | `fact_segment[mid_lat]` Data category **Latitude**, `[mid_lon]` **Longitude**. |
| 5 | Format `% Poor or Worse` as percent, 1 decimal; `Avg Condition` 1 decimal; `Miles` 0 decimals. |
| 6 | **Home > Enter data**, name it `_Measures`, Load. Paste each measure from `measures.dax` with **New measure**. Delete the dummy column. |

## 3. Pages (20 min)
Colors: one color per condition band, the same in the report, the map and the site: Failed/Serious `#B91C1C`, Very poor `#D4850A`, Poor `#E8B64C`, Fair `#9AA3AE`, Satisfactory `#6FB08C`, Good `#1A7A4A`.

**Page 1: Ward scorecard**
| Visual | Fields |
|---|---|
| Card row (5 cards) | `Avg Condition`, `% Poor or Worse`, `Miles`, `Inspected Over 3 Yrs Ago`, `Under Moratorium` |
| Card, top right | `Viewing As` (shows which ward the viewer is limited to) |
| Clustered bar | Y `dim_ward[ward_name]`, X `Avg Condition`, sorted descending |
| 100% stacked bar | Y `dim_ward[ward_name]`, X `fact_segment[area_sqft]` (Sum), Legend `dim_condition_band[band]` |
| Slicer | `fact_segment[street_class]` (Major / Minor) |
| Text box, bottom | `Data As Of` measure in a card |

**Page 2: Worst first**
| Visual | Fields |
|---|---|
| Table | `segment_label`, `ward_name`, `street_class`, `oci`, `area_sqft`, `inspection_date`, `under_moratorium`. Sort by `oci` ascending. Filter pane: `under_moratorium` is False, `jurisdiction` is City of Tucson, `oci` is not blank. Conditional formatting on `oci`: background by band color. |
| Map | Latitude/Longitude from `fact_segment`, Legend `dim_condition_band[band]`, Tooltips `segment_label`, `oci` |
| Slicers | `ward_name`, `street_class` |

**Page 3: Data health**
| Visual | Fields |
|---|---|
| Table | `v_quality`: `check_name`, `severity`, `row_count`, `detail`. Conditional icon on `severity`. |
| Table | `v_load_status`: `layer`, `mode`, `finished_at`, `status`, `rows_read`, `rows_updated` |
| Column chart | X `fact_segment[inspection_date]` (Year), Y `Segments`, Legend `street_class`. Shows the 2020 survey that hasn't been redone. |

## 4. Security (10 min)
| Step | Do this |
|---|---|
| 1 | **Modeling > Manage roles > New**. Make `Ward 3`, `Ward 5` (table `dim_ward`, filter `[ward_id] = 3` / `= 5`), `City-wide` (no filter), and `Ward office` with the dynamic filter in `measures.dax`. Save. |
| 2 | **Modeling > View as > Ward 3**. Every visual should show Ward 3 only and `Viewing As` should read "Ward 3". Screenshot. |
| 3 | Same with **Ward 5**. Screenshot. |
| 4 | **View as > Ward office + Other user** `district.lead@example.org`: Wards 2 and 4 only. Screenshot. |
| 5 | **File > Save as** `powerbi\Tucson Street Conditions.pbip`. Commit the folder. |

## Two things to say in an interview
- **Two layers of security.** SQL Server row-level security (`sql\05_security.sql`) limits what each database user can read, whatever tool they use. Power BI roles limit what each report viewer sees. Here the report connects with my own Windows account, which sees everything, so the Power BI roles do the filtering. In production the report would refresh through a gateway account and the city would assign people to roles in the Power BI Service.
- **Desktop only simulates roles.** "View as" proves the filters work; real per-person enforcement needs the report published to the Power BI Service (Pro license). "Publish to web" can't be used with row-level security, so the public proof is screenshots.
