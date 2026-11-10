# Requirements: Tucson Street Conditions

Version 1.0 · 2026-11-09 · Author: Jake Moore · Status: draft for review

A personal project built on the City of Tucson's public pavement data. It is not a City project and was not requested
by City staff. Anything below about how the City works today is either sourced (link given) or marked
**assumed, to confirm with staff**.

## 1. Problem

| | |
|---|---|
| What the city is doing | Prop 411 is a voter-approved 10-year half-cent sales tax; $590 million goes to neighborhood streets. Phase 1 projects were picked by lowest Overall Condition Index (OCI) first, then ward proportionality and equity ([City of Tucson release](https://content.govdelivery.com/accounts/AZTUCSON/bulletins/362edfc), [KGUN 9](https://kgun9.com/operation-safe-roads/worst-first-is-tucsons-plan-for-street-repair)) |
| What the data is | The City publishes condition scores for 11,655 street segments (1,837 miles) as public ArcGIS layers, plus a layer of major streets under a pavement-cut moratorium |
| The gap | The layers hold only the latest score. Nothing keeps history, checks the data, splits it by ward with access control, or answers "can we dig here?" in one place |
| Today (assumed, to confirm with staff) | A ward office that wants its ward's street list emails TDOT. Staff export the layer, filter it in Excel and email it back. A utility crew learns about a moratorium during permit review |
| Rule that drives the dig check | Major streets newly built or overlaid within 5 years are under a pavement-cut moratorium ([ROW brochure](https://www.tucsonaz.gov/files/sharedassets/public/v/1/transportation-and-mobility/documents/rowbrochure2018-web.pdf)). Cuts in pavement with OCI 40 or lower are exempt from loss-of-value fees ([Rate and fee changes](https://www.tucsonaz.gov/Departments/Transportation-Mobility/Permits-and-Codes-Section/Rate-and-Fee-Changes)) |

## 2. Stakeholders

| Stakeholder | What they need | How often (assumed, to confirm with staff) |
|---|---|---|
| TDOT pavement program staff | City-wide condition, worst-first list, data gaps to fix | Weekly |
| Ward council offices (6) | Their own ward only: condition, worst streets, what's under moratorium | When a constituent asks |
| Prop 411 oversight commission (IOAC) | Proof the lowest-score-first rule is being followed, trend over time | Each meeting |
| Utility crews and the permit desk | Is this segment under moratorium, and until when | Before every street cut |
| City IT / GIS (maintainer) | A load that runs unattended, logs every run, fails loudly | On failure only |

## 3. Scope

| In | Out |
|---|---|
| Nightly load of the three public layers (major, minor, moratorium) into SQL Server | Editing City data; the City's Cartegraph system stays the source of truth |
| Cleaning, history of score changes, data quality checks | Choosing which streets to fix (the report ranks; people decide) |
| Ward-level access in SQL Server and in Power BI | Cost estimates (no published unit cost was found, so no dollar figures) |
| Power BI report: overview, worst-first, data health | Pima County roads outside the City's layer |
| ArcGIS Online map styled by condition | Live Power BI Service publishing with per-user sign-in (needs a Pro license) |
| Requirements, process maps, user stories, test plan, runbook | |

## 4. Business requirements

| ID | Requirement | Verified by |
|---|---|---|
| BR-01 | A ward office can see its own ward's street conditions without asking TDOT staff | TC-13, TC-20, TC-21 |
| BR-02 | Staff can pull a worst-first list per ward that follows the lowest-OCI-first rule | TC-22, TC-23 |
| BR-03 | A utility crew or permit clerk can check a segment's moratorium status and end date in one lookup | TC-24 |
| BR-04 | Anyone reading the report can see what the data is missing or doubtful about | TC-15, TC-16, TC-25 |
| BR-05 | Staff can see how a segment's score changed over time, even though the City layer keeps only the latest score | TC-11 |

## 5. Functional requirements

| ID | Requirement | Traces to | Verified by |
|---|---|---|---|
| FR-01 | Pull the major, minor and moratorium layers from the City's ArcGIS REST service, paged by OBJECTID, 1,000 rows a page | BR-01..03 | TC-17 |
| FR-02 | Retry a failed web call up to 4 times with 2, 4, 8 second waits, then mark the run failed | BR-04 | TC-05, TC-06, TC-26 |
| FR-03 | Stage each layer, then merge into core tables on the City's CartegraphID. Loading the same data twice changes nothing | BR-01 | TC-07, TC-08 |
| FR-04 | Stop before the merge if the source has duplicate CartegraphIDs | BR-04 | TC-04 |
| FR-05 | Incremental mode pulls only rows the City edited since the last load | BR-01 | TC-18 |
| FR-06 | On a full load only, flag segments that disappeared from the City layer as removed (never delete them) | BR-04 | TC-12 |
| FR-07 | Keep wards 1 to 6 only. County supervisor districts ("BOS n") and blanks become "outside city wards" | BR-01 | TC-09 |
| FR-08 | Treat the City's placeholder dates (1900, 1905) as unknown | BR-04 | TC-10 |
| FR-09 | Write a history row the first time a segment is seen and whenever its score or inspection date changes | BR-05 | TC-11 |
| FR-10 | Run 10 data quality checks after every load. Any "error" check with rows fails the run | BR-04 | TC-15, TC-16 |
| FR-11 | Log every run per layer: start, finish, rows read / new / changed / unchanged, status, error text | BR-04 | TC-17 |
| FR-12 | Label each segment with its cross streets ("S Cherry Av: E Irvington Rd to E Bantam Rd") | BR-01 | TC-03 |
| FR-13 | SQL Server row-level security: a ward user sees only rows for wards listed in `sec.user_ward`; city-wide users see all | BR-01 | TC-13, TC-14 |
| FR-14 | Power BI roles: one static role per ward and one dynamic role driven by the sign-in name | BR-01 | TC-20, TC-21 |
| FR-15 | Power BI pages: city overview, worst-first list, data health | BR-02, BR-04 | TC-22, TC-25 |
| FR-16 | Dig-check view: every major segment with moratorium status, end date and days left | BR-03 | TC-24 |
| FR-17 | ArcGIS Online map of the City's layer, colored by condition band, with ward boundaries and a pop-up | BR-01, BR-02 | TC-23 |

## 6. Non-functional requirements

| ID | Requirement | Verified by |
|---|---|---|
| NFR-01 | A full load of all three layers finishes in under 2 minutes (measured: 16 seconds) | TC-17 |
| NFR-02 | The database install script can run again at any time without errors or data loss | TC-19 |
| NFR-03 | Runs on Windows PowerShell 5.1 and SQL Server Express with no extra modules | TC-17 |
| NFR-04 | Runs unattended on a schedule and returns exit code 1 on any failure | TC-26 |
| NFR-05 | Public data only. Staff names and emails from the City's layer metadata are not republished | Review |
| NFR-06 | The automated test suite runs in under a minute against a throwaway database, never the real one | TC-01..16 |

## 7. Condition bands

Bands follow the ASTM D6433 0 to 100 rating scale. The City's OCI uses the same range; whether the City uses these
exact cut-offs is assumed, to confirm with staff.

| Band | OCI | Segments (2026-11-09) |
|---|---|---|
| Good | 85-100 | 4,167 |
| Satisfactory | 70-85 | 2,122 |
| Fair | 55-70 | 1,079 |
| Poor | 40-55 | 3,002 |
| Very poor | 25-40 | 940 |
| Serious | 10-25 | 174 |
| Failed | 0-10 | 30 |
| No score | blank | 141 |

## 8. Related documents

| File | What |
|---|---|
| [user-stories.csv](user-stories.csv) | 4 epics, 18 stories for a Jira CSV import. Map Issue ID and Parent to link stories to epics; map Acceptance Criteria to a custom field or append it to Description |
| [process-maps/](process-maps/) | As-is and to-be BPMN 2.0 (`.bpmn` opens in bpmn.io, Camunda Modeler or draw.io; `.svg` for viewing) |
| [test-plan.md](test-plan.md) | Test cases TC-01 to TC-26 |
| [runbook.md](runbook.md) | Running and fixing the loader |
| [data-findings.md](data-findings.md) | What the data says and what to do about it |

## 9. Assumptions and open questions

| # | Item | Owner |
|---|---|---|
| A1 | How ward offices get street lists today (the as-is map) | Confirm with TDOT |
| A2 | Whether the City uses ASTM band names or its own | Confirm with TDOT |
| A3 | Local streets: the fee page uses 36 months for local streets and 60 for arterials/collectors; the moratorium layer covers major streets only | Confirm with TDOT permits |
| A4 | Whether the 2020 scores on 2,782 neighborhood segments are still the scores used for ranking | Confirm with TDOT |
