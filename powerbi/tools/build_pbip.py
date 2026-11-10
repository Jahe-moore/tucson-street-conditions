"""Writes the Tucson Street Conditions Power BI project (PBIP: TMDL model + PBIR report)."""
import json, os, shutil, sys

OUT = r"C:\Users\jahem\OneDrive\Portfolio_Projects\Tucson_Street_Conditions\powerbi"
NAME = "Tucson Street Conditions"
SM = os.path.join(OUT, f"{NAME}.SemanticModel")
RP = os.path.join(OUT, f"{NAME}.Report")
THEME_SRC = r"C:\Program Files\Microsoft Power BI Desktop\bin\WebView2Resources\minerva\sharedresources\BaseThemes\CY24SU10.json"
ONLY_PAGES = sys.argv[1].split(",") if len(sys.argv) > 1 else None

BANDS = [("Failed", "#7F1414"), ("Serious", "#B91C1C"), ("Very poor", "#D4850A"), ("Poor", "#E8B64C"),
         ("Fair", "#9AA3AE"), ("Satisfactory", "#6FB08C"), ("Good", "#1A7A4A")]
NAVY, STEEL = "#1B2A4A", "#5B7FA6"


def w(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def wj(path, obj):
    w(path, json.dumps(obj, indent=2))


for d in (SM, RP):
    # delete files only; OneDrive can hold empty folders open
    for root, _, files in os.walk(d):
        for fn in files:
            os.remove(os.path.join(root, fn))

# ---------------------------------------------------------------- semantic model (TMDL)
SRC = 'Sql.Database("localhost\\SQLEXPRESS", "TucsonStreets")'

TABLES = {
    "fact_segment": [
        ("cartegraph_id", "string"), ("street_class", "string"), ("street_name", "string"),
        ("segment_label", "string"), ("segment_key_label", "string"), ("complexity", "string"),
        ("jurisdiction", "string"), ("ward_id", "int64"), ("band_id", "int64"), ("oci", "double"),
        ("length_ft", "double"), ("length_mi", "double"), ("area_sqft", "double"),
        ("inspection_date", "dateTime"), ("inspection_year", "int64"), ("inspection_age_yrs", "double"),
        ("last_treated_date", "dateTime"), ("is_protected", "boolean"), ("moratorium_end_date", "dateTime"),
        ("under_moratorium", "boolean"), ("mid_lat", "double"), ("mid_lon", "double")],
    "dim_ward": [("ward_id", "int64"), ("ward_name", "string")],
    "dim_condition_band": [("band_id", "int64"), ("band", "string"), ("min_oci", "double"), ("max_oci", "double")],
    "v_worst_first": [("rank_in_ward", "int64"), ("ward_id", "int64"), ("cartegraph_id", "string"),
                      ("street_class", "string"), ("segment_label", "string"), ("oci", "double"),
                      ("area_sqft", "double"), ("inspection_date", "dateTime")],
    "v_quality": [("check_name", "string"), ("severity", "string"), ("row_count", "int64"),
                  ("detail", "string"), ("checked_at", "dateTime")],
    "v_load_status": [("layer", "string"), ("mode", "string"), ("started_at", "dateTime"),
                      ("finished_at", "dateTime"), ("status", "string"), ("rows_read", "int64"),
                      ("rows_inserted", "int64"), ("rows_updated", "int64"), ("rows_unchanged", "int64"),
                      ("error_message", "string")],
    "user_ward": [("user_name", "string"), ("ward_id", "int64")],
}
HIDDEN_TABLES = {"user_ward"}
COLFMT = {"oci": "0.0", "area_sqft": "#,0", "length_mi": "#,0.0", "length_ft": "#,0",
          "inspection_date": "mmm yyyy", "inspection_year": "0", "moratorium_end_date": "mmm d, yyyy",
          "last_treated_date": "mmm yyyy", "finished_at": "mmm d, yyyy h:mm AM/PM",
          "started_at": "mmm d, yyyy h:mm AM/PM", "checked_at": "mmm d, yyyy h:mm AM/PM",
          "row_count": "#,0", "rows_read": "#,0", "rows_inserted": "#,0", "rows_updated": "#,0",
          "rows_unchanged": "#,0", "rank_in_ward": "0"}
DISPLAY = {"segment_label": None}

MEASURES = {
    "Segments": ("COUNTROWS ( fact_segment )", "#,0"),
    "Miles": ("SUM ( fact_segment[length_mi] )", "#,0"),
    "Avg Condition": ("VAR scored = FILTER ( fact_segment, NOT ISBLANK ( fact_segment[oci] ) && NOT ISBLANK ( fact_segment[area_sqft] ) )\n"
                      "RETURN DIVIDE ( SUMX ( scored, fact_segment[oci] * fact_segment[area_sqft] ), SUMX ( scored, fact_segment[area_sqft] ) )", "0.0"),
    "% Poor or Worse": ("VAR scoredArea = CALCULATE ( SUM ( fact_segment[area_sqft] ), NOT ISBLANK ( fact_segment[oci] ) )\n"
                        "VAR poorArea = CALCULATE ( SUM ( fact_segment[area_sqft] ), NOT ISBLANK ( fact_segment[oci] ) && fact_segment[oci] < 55 )\n"
                        "RETURN DIVIDE ( poorArea, scoredArea )", "0.0%"),
    "Inspected Over 3 Yrs Ago": ("CALCULATE ( [Segments], fact_segment[inspection_age_yrs] > 3 ) + 0", "#,0"),
    "No Score": ("CALCULATE ( [Segments], ISBLANK ( fact_segment[oci] ) ) + 0", "#,0"),
    "Under Moratorium": ("CALCULATE ( [Segments], fact_segment[under_moratorium] = TRUE () ) + 0", "#,0"),
    "Data As Of": ('"Data loaded " & FORMAT ( MAX ( v_load_status[finished_at] ), "mmm d, yyyy h:mm AM/PM" )', None),
    "Viewing As": ('VAR n = COUNTROWS ( ALL ( dim_ward ) )\n'
                   'VAR wards = CONCATENATEX ( FILTER ( ALL ( dim_ward ), dim_ward[ward_id] > 0 ), dim_ward[ward_name], ", ", dim_ward[ward_id] )\n'
                   'RETURN IF ( n >= 7, "Viewing: all wards", "Viewing: " & wards )', None),
    "Scored Area": ("CALCULATE ( SUM ( fact_segment[area_sqft] ), NOT ISBLANK ( fact_segment[oci] ) )", "#,0"),
    "Failed Or Serious": ("CALCULATE ( COUNTROWS ( v_worst_first ), v_worst_first[oci] < 25 ) + 0", "#,0"),
    "Quality Issues": ('CALCULATE ( SUM ( v_quality[row_count] ), v_quality[severity] IN { "error", "warn" } ) + 0', "#,0"),
}

w(os.path.join(SM, "definition.pbism"), json.dumps({
    "$schema": "https://developer.microsoft.com/json-schemas/fabric/item/semanticModel/definitionProperties/1.0.0/schema.json",
    "version": "4.2", "settings": {}}, indent=2))
w(os.path.join(SM, "definition", "database.tmdl"), "database\n\tcompatibilityLevel: 1600\n")

model = ["model Model", "\tculture: en-US", "\tdefaultPowerBIDataSourceVersion: powerBI_V3",
         "\tdiscourageImplicitMeasures", "\tsourceQueryCulture: en-US", ""]
model += [f"ref table {t}" for t in TABLES] + [""]
model += ["ref role 'Ward 3'", "ref role 'Ward 5'", "ref role 'City-wide'", "ref role 'Ward office'", ""]
w(os.path.join(SM, "definition", "model.tmdl"), "\n".join(model))


def table_tmdl(t, cols):
    L = [f"table {t}"]
    if t in HIDDEN_TABLES:
        L.append("\tisHidden")
    L.append("")
    if t == "fact_segment":
        for m, (expr, fmt) in MEASURES.items():
            lines = expr.split("\n")
            if len(lines) == 1:
                L.append(f"\tmeasure '{m}' = {lines[0]}")
            else:
                L.append(f"\tmeasure '{m}' =")
                L += [f"\t\t\t{x}" for x in lines]
            if fmt:
                L.append(f"\t\tformatString: {fmt}")
            L.append("")
    for c, dt in cols:
        L.append(f"\tcolumn {c}")
        L.append(f"\t\tdataType: {dt}")
        if c in COLFMT:
            L.append(f"\t\tformatString: {COLFMT[c]}")
        summarize = "sum" if (t == "fact_segment" and dt in ("double", "int64") and not c.endswith("_id") and c not in
                              ("oci", "mid_lat", "mid_lon", "inspection_year", "inspection_age_yrs", "rank_in_ward",
                               "min_oci", "max_oci")) else "none"
        L.append(f"\t\tsummarizeBy: {summarize}")
        L.append(f"\t\tsourceColumn: {c}")
        if t == "dim_condition_band" and c == "band":
            L.append("\t\tsortByColumn: band_id")
        if t == "user_ward" or (c.endswith("_id") and c != "cartegraph_id") or c in ("mid_lat", "mid_lon"):
            L.append("\t\tisHidden")
        if c == "mid_lat":
            L.append("\t\tdataCategory: Latitude")
        if c == "mid_lon":
            L.append("\t\tdataCategory: Longitude")
        L.append("")
    L += [f"\tpartition {t} = m", "\t\tmode: import", "\t\tsource =", "\t\t\t\tlet",
          f"\t\t\t\t    Source = {SRC},",
          f'\t\t\t\t    Data = Source{{[Schema="rpt",Item="{t}"]}}[Data]',
          "\t\t\t\tin", "\t\t\t\t    Data", ""]
    return "\n".join(L)


for t, cols in TABLES.items():
    w(os.path.join(SM, "definition", "tables", f"{t}.tmdl"), table_tmdl(t, cols))

rels = []
for name, frm in [("fact_ward", "fact_segment.ward_id"), ("fact_band", "fact_segment.band_id"),
                  ("worst_ward", "v_worst_first.ward_id")]:
    to = "dim_condition_band.band_id" if "band" in frm else "dim_ward.ward_id"
    rels += [f"relationship {name}", f"\tfromColumn: {frm}", f"\ttoColumn: {to}", ""]
w(os.path.join(SM, "definition", "relationships.tmdl"), "\n".join(rels))

ROLES = {
    "Ward 3": "[ward_id] = 3",
    "Ward 5": "[ward_id] = 5",
    "City-wide": None,
    "Ward office": "[ward_id] IN CALCULATETABLE ( VALUES ( user_ward[ward_id] ), user_ward[user_name] = USERPRINCIPALNAME () )",
}
for r, f in ROLES.items():
    L = [f"role '{r}'", "\tmodelPermission: read", ""]
    if f:
        L += [f"\ttablePermission dim_ward = {f}", ""]
    w(os.path.join(SM, "definition", "roles", f"{r}.tmdl"), "\n".join(L))

# ---------------------------------------------------------------- report (PBIR)
S = "https://developer.microsoft.com/json-schemas/fabric/item/report/definition"
wj(os.path.join(RP, "definition.pbir"), {
    "$schema": "https://developer.microsoft.com/json-schemas/fabric/item/report/definitionProperties/2.0.0/schema.json",
    "version": "4.0", "datasetReference": {"byPath": {"path": f"../{NAME}.SemanticModel"}}})
wj(os.path.join(RP, "definition", "version.json"), {"$schema": f"{S}/versionMetadata/1.0.0/schema.json", "version": "2.0.0"})
RV = {"visual": "1.8.95", "report": "2.0.95", "page": "1.3.95"}
wj(os.path.join(RP, "definition", "report.json"), {
    "$schema": f"{S}/report/1.0.0/schema.json",
    "themeCollection": {
        "baseTheme": {"name": "CY24SU10", "reportVersionAtImport": RV, "type": "SharedResources"},
        "customTheme": {"name": "StreetBands.json", "reportVersionAtImport": RV, "type": "RegisteredResources"}},
    "resourcePackages": [
        {"name": "SharedResources", "type": "SharedResources",
         "items": [{"name": "CY24SU10", "path": "BaseThemes/CY24SU10.json", "type": "BaseTheme"}]},
        {"name": "RegisteredResources", "type": "RegisteredResources",
         "items": [{"name": "StreetBands.json", "path": "StreetBands.json", "type": "CustomTheme"}]}],
    "settings": {"useStylableVisualContainerHeader": True, "exportDataMode": "AllowSummarized",
                 "defaultDrillFilterOtherVisuals": True, "allowChangeFilterTypes": True,
                 "useEnhancedTooltips": True, "useDefaultAggregateDisplayName": True}})
os.makedirs(os.path.join(RP, "StaticResources", "SharedResources", "BaseThemes"), exist_ok=True)
shutil.copy(THEME_SRC, os.path.join(RP, "StaticResources", "SharedResources", "BaseThemes", "CY24SU10.json"))
wj(os.path.join(RP, "StaticResources", "RegisteredResources", "StreetBands.json"), {
    "name": "StreetBands",
    "dataColors": [NAVY, STEEL] + [c for _, c in BANDS],
    "background": "#FFFFFF", "foreground": "#2D2D2D", "tableAccent": NAVY,
    "textClasses": {"title": {"fontFace": "Segoe UI Semibold", "color": NAVY, "fontSize": 12},
                    "callout": {"color": NAVY}, "label": {"color": "#2D2D2D"}}})


# ---- helpers for visuals
def lit(v):
    return {"expr": {"Literal": {"Value": v}}}


def col(entity, prop):
    return {"Column": {"Expression": {"SourceRef": {"Entity": entity}}, "Property": prop}}


def mea(entity, prop):
    return {"Measure": {"Expression": {"SourceRef": {"Entity": entity}}, "Property": prop}}


def agg(entity, prop, fn=0):
    return {"Aggregation": {"Expression": col(entity, prop), "Function": fn}}


def proj(field, ref, display=None):
    p = {"field": field, "queryRef": ref, "nativeQueryRef": ref.split(".", 1)[1]}
    if display:
        p["displayName"] = display
    return p


def title(text, show=True):
    return {"title": [{"properties": {"show": lit("true" if show else "false"), "text": lit(f"'{text}'")}}]}


PAGES = {}


def visual(page, name, vtype, x, y, wd, ht, roles=None, objects=None, ttl=None, sort=None, z=0, filters=None):
    v = {"visualType": vtype, "drillFilterOtherVisuals": True}
    if roles:
        v["query"] = {"queryState": {r: {"projections": ps} for r, ps in roles.items()}}
        if sort:
            v["query"]["sortDefinition"] = {"sort": [{"field": f, "direction": d} for f, d in sort], "isDefaultSort": True}
    if objects:
        v["objects"] = objects
    vc = {"$schema": f"{S}/visualContainer/1.0.0/schema.json", "name": name,
          "position": {"x": x, "y": y, "z": z, "width": wd, "height": ht}, "visual": v}
    if ttl is not None:
        v["visualContainerObjects"] = title(ttl) if ttl else title("", False)
    if filters:
        vc["filterConfig"] = {"filters": filters}
    PAGES.setdefault(page, []).append(vc)


def textbox(page, name, text, x, y, wd, ht, size="18pt", bold=True, color=NAVY):
    style = {"fontSize": size, "color": color}
    if bold:
        style["fontWeight"] = "bold"
    PAGES.setdefault(page, []).append({
        "$schema": f"{S}/visualContainer/1.0.0/schema.json", "name": name,
        "position": {"x": x, "y": y, "z": 0, "width": wd, "height": ht},
        "visual": {"visualType": "textbox", "objects": {"general": [{"properties": {
            "paragraphs": [{"textRuns": [{"value": text, "textStyle": style}]}]}}]},
            "drillFilterOtherVisuals": True}})


def card(page, name, measure, label, x, y, wd=196, ht=100):
    visual(page, name, "card", x, y, wd, ht,
           roles={"Values": [proj(mea("fact_segment", measure), f"fact_segment.{measure}", label)]},
           objects={"labels": [{"properties": {"color": {"solid": {"color": lit(f"'{NAVY}'")}}, "fontSize": lit("24D")}}],
                    "categoryLabels": [{"properties": {"show": lit("true"), "fontSize": lit("10D")}}]},
           ttl="")


def band_colors(series_col):
    out = []
    for b, c in BANDS:
        out.append({"properties": {"fill": {"solid": {"color": lit(f"'{c}'")}}},
                    "selector": {"data": [{"scopeId": {"Comparison": {"ComparisonKind": 0, "Left": series_col,
                                                                      "Right": {"Literal": {"Value": f"'{b}'"}}}}}]}})
    return out


WARD = col("dim_ward", "ward_name")


def YEAR_FROM(name, year):
    """Visual filter: inspection_year >= year."""
    return {"name": name, "type": "Advanced", "field": col("fact_segment", "inspection_year"),
            "filter": {"Version": 2, "From": [{"Name": "f", "Entity": "fact_segment", "Type": 0}],
                       "Where": [{"Condition": {"Comparison": {"ComparisonKind": 2,
                                  "Left": {"Column": {"Expression": {"SourceRef": {"Source": "f"}}, "Property": "inspection_year"}},
                                  "Right": {"Literal": {"Value": f"{year}L"}}}}}]}}


def CITY_WARDS(name):
    """Visual filter: wards 1-6 only (drops county, state and private roads in the city's layer)."""
    return {"name": name, "type": "Advanced", "field": col("dim_ward", "ward_id"),
            "filter": {"Version": 2, "From": [{"Name": "d", "Entity": "dim_ward", "Type": 0}],
                       "Where": [{"Condition": {"Comparison": {"ComparisonKind": 1,
                                  "Left": {"Column": {"Expression": {"SourceRef": {"Source": "d"}}, "Property": "ward_id"}},
                                  "Right": {"Literal": {"Value": "0L"}}}}}]}}
BAND = col("dim_condition_band", "band")

# Page 1: ward scorecard
p = "scorecard"
textbox(p, "t_title", "Tucson street conditions by ward", 24, 12, 700, 44)
visual(p, "c_view", "card", 980, 10, 276, 52,
       roles={"Values": [proj(mea("fact_segment", "Viewing As"), "fact_segment.Viewing As")]},
       objects={"labels": [{"properties": {"color": {"solid": {"color": lit(f"'{STEEL}'")}}, "fontSize": lit("12D")}}],
                "categoryLabels": [{"properties": {"show": lit("false")}}]}, ttl="")
for i, (m, label) in enumerate([("Avg Condition", "Average condition (0-100)"), ("% Poor or Worse", "Pavement poor or worse"),
                                ("Miles", "Miles of street"), ("Inspected Over 3 Yrs Ago", "Inspected 3+ years ago"),
                                ("Under Moratorium", "Under dig moratorium")]):
    card(p, f"c_{i}", m, label, 24 + i * 206, 70)
visual(p, "s_class", "slicer", 1062, 70, 194, 100,
       roles={"Values": [proj(col("fact_segment", "street_class"), "fact_segment.street_class", "Street type")]},
       objects={"data": [{"properties": {"mode": lit("'Dropdown'")}}]}, ttl="")
visual(p, "b_avg", "clusteredBarChart", 24, 190, 500, 470,
       roles={"Category": [proj(WARD, "dim_ward.ward_name", "Ward")],
              "Y": [proj(mea("fact_segment", "Avg Condition"), "fact_segment.Avg Condition", "Average condition")]},
       sort=[(mea("fact_segment", "Avg Condition"), "Descending")],
       objects={"dataPoint": [{"properties": {"fill": {"solid": {"color": lit(f"'{NAVY}'")}}}}],
                "labels": [{"properties": {"show": lit("true")}}],
                "valueAxis": [{"properties": {"start": lit("0D"), "end": lit("100D")}}]}, filters=[CITY_WARDS("fa")],
       ttl="Average condition by ward (weighted by pavement area)")
visual(p, "b_mix", "hundredPercentStackedBarChart", 544, 190, 712, 470,
       roles={"Category": [proj(WARD, "dim_ward.ward_name", "Ward")],
              "Y": [proj(mea("fact_segment", "Scored Area"), "fact_segment.Scored Area", "Pavement area")],
              "Series": [proj(BAND, "dim_condition_band.band", "Condition")]},
       sort=[(WARD, "Ascending")],
       objects={"dataPoint": band_colors(BAND), "legend": [{"properties": {"show": lit("true"), "position": lit("'Top'")}}]}, filters=[CITY_WARDS("fb")],
       ttl="Share of pavement in each condition band")
visual(p, "c_asof", "card", 24, 670, 500, 40,
       roles={"Values": [proj(mea("fact_segment", "Data As Of"), "fact_segment.Data As Of")]},
       objects={"labels": [{"properties": {"color": {"solid": {"color": lit("'#6B7280'")}}, "fontSize": lit("10D")}}],
                "categoryLabels": [{"properties": {"show": lit("false")}}]}, ttl="")

# Page 2: worst first
p = "worst"
textbox(p, "t_title", "Worst first: city streets not under a dig moratorium", 24, 12, 900, 44)
visual(p, "s_ward", "slicer", 24, 64, 1232, 56,
       roles={"Values": [proj(WARD, "dim_ward.ward_name", "Ward")]},
       objects={"data": [{"properties": {"mode": lit("'Basic'")}}],
                "general": [{"properties": {"orientation": lit("1D")}}]}, ttl="", filters=[CITY_WARDS("fs")])
WF = "v_worst_first"
visual(p, "tbl_worst", "tableEx", 24, 130, 860, 570,
       roles={"Values": [proj(col(WF, "rank_in_ward"), f"{WF}.rank_in_ward", "Rank in ward"),
                         proj(WARD, "dim_ward.ward_name", "Ward"),
                         proj(col(WF, "segment_label"), f"{WF}.segment_label", "Street segment"),
                         proj(col(WF, "street_class"), f"{WF}.street_class", "Type"),
                         proj(col(WF, "oci"), f"{WF}.oci", "Condition"),
                         proj(col(WF, "area_sqft"), f"{WF}.area_sqft", "Pavement sq ft"),
                         proj(col(WF, "inspection_date"), f"{WF}.inspection_date", "Last inspected")]},
       sort=[(col(WF, "oci"), "Ascending")], ttl="")
visual(p, "b_fail", "clusteredBarChart", 904, 130, 352, 570,
       roles={"Category": [proj(WARD, "dim_ward.ward_name", "Ward")],
              "Y": [proj(mea("fact_segment", "Failed Or Serious"), "fact_segment.Failed Or Serious", "Segments")]},
       sort=[(mea("fact_segment", "Failed Or Serious"), "Descending")],
       objects={"dataPoint": [{"properties": {"fill": {"solid": {"color": lit("'#B91C1C'")}}}}],
                "labels": [{"properties": {"show": lit("true")}}]},
       filters=[CITY_WARDS("fw")], ttl="Segments scored under 25 (failed or serious)")

# Page 3: data health
p = "health"
textbox(p, "t_title", "Data health: is the city's data complete and current?", 24, 12, 900, 44)
visual(p, "tbl_q", "tableEx", 24, 70, 820, 320,
       roles={"Values": [proj(col("v_quality", "check_name"), "v_quality.check_name", "Check"),
                         proj(col("v_quality", "severity"), "v_quality.severity", "Severity"),
                         proj(col("v_quality", "row_count"), "v_quality.row_count", "Rows"),
                         proj(col("v_quality", "detail"), "v_quality.detail", "What it means")]},
       ttl="Quality checks from the last load")
visual(p, "tbl_load", "tableEx", 864, 70, 392, 320,
       roles={"Values": [proj(col("v_load_status", "layer"), "v_load_status.layer", "Layer"),
                         proj(col("v_load_status", "status"), "v_load_status.status", "Status"),
                         proj(col("v_load_status", "rows_read"), "v_load_status.rows_read", "Rows read"),
                        proj(col("v_load_status", "finished_at"), "v_load_status.finished_at", "Finished")]},
       ttl="Last load of each layer")
visual(p, "col_insp", "clusteredColumnChart", 24, 420, 1232, 280,
       roles={"Category": [proj(col("fact_segment", "inspection_year"), "fact_segment.inspection_year", "Year last inspected")],
              "Y": [proj(mea("fact_segment", "Segments"), "fact_segment.Segments", "Segments")],
              "Series": [proj(col("fact_segment", "street_class"), "fact_segment.street_class", "Street type")]},
       sort=[(col("fact_segment", "inspection_year"), "Ascending")],
       objects={"labels": [{"properties": {"show": lit("true"), "labelDisplayUnits": lit("1D")}}]},
       filters=[YEAR_FROM("fy", 2016)], ttl="When each segment was last inspected (2016 on)")

PAGE_META = {"scorecard": "Ward scorecard", "worst": "Worst first", "health": "Data health"}
order = [k for k in PAGE_META if not ONLY_PAGES or k in ONLY_PAGES]
wj(os.path.join(RP, "definition", "pages", "pages.json"),
   {"$schema": f"{S}/pagesMetadata/1.0.0/schema.json", "pageOrder": order, "activePageName": order[0]})
for k in order:
    wj(os.path.join(RP, "definition", "pages", k, "page.json"),
       {"$schema": f"{S}/page/1.0.0/schema.json", "name": k, "displayName": PAGE_META[k],
        "displayOption": "FitToPage", "height": 720, "width": 1280})
    for vc in PAGES[k]:
        vc["name"] = f"{k}_{vc['name']}"  # visual names must be unique across the report
        wj(os.path.join(RP, "definition", "pages", k, "visuals", vc["name"], "visual.json"), vc)

wj(os.path.join(OUT, f"{NAME}.pbip"), {
    "$schema": "https://developer.microsoft.com/json-schemas/fabric/pbip/pbipProperties/1.0.0/schema.json",
    "version": "1.0", "artifacts": [{"report": {"path": f"{NAME}.Report"}}], "settings": {"enableAutoRecovery": True}})
print("written:", order)
