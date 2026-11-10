# The street map

**Built:** `site\map.html`, a page on the ArcGIS Maps SDK for JavaScript 4.30. Open it in any browser; no sign-in.
It reads the city's own published layers live, so it stays current without any upload.

| Layer | ArcGIS Online item | Owner |
|---|---|---|
| Pavement Conditions - Major Streets | `00a290def9cf4c16a0d5b87f2b282c67` | City of Tucson |
| Pavement Conditions - Minor Streets | `02bfd7ae183c4c8ebb2d74c02984ce35` | City of Tucson |
| Wards - City of Tucson | `025e8235c2ab4b09ba4e202d28cc2fc1` | Pima County GIS open data |

| Feature | How |
|---|---|
| Color by condition | Arcade expression below, unique-value renderer, same bands as `core.condition_band` |
| Line width | Major streets 2.6 px; neighborhood streets 1.2 px and only drawn once zoomed in past 1:80,000 |
| Pop-up | Street name, score out of 100 with its band, cross streets, last inspection with years ago and a re-inspection flag |
| Ward filter | Drop-down zooms to one ward and filters both street layers and the ward outline to it |
| Screenshots | `site\img\map-city.jpg`, `site\img\map-ward3.jpg` (kept in case the layers move) |

Checked 2026-11-09: ward filter zooms and filters correctly; pop-up for N Columbus Bl shows score 8, near E Fort Lowell Rd, inspected July 2024.

## Optional: save the same map in ArcGIS Online
The site page needs no account. To have it as a saved web map in an ArcGIS Online organization too (about 20 minutes, needs a sign-in):

1. arcgis.com > **Map** (opens Map Viewer). Basemap: **Light Gray Canvas**.
2. **Layers > Add > Browse layers > ArcGIS Online**. Search each item ID above and **Add to map**. Order from top: Wards, Major, Minor.
3. On both street layers: **Styles** > **+ Expression**, paste, title it `Condition`:
```
// Same bands as the SQL table core.condition_band (ASTM D6433 scale, 0 to 100)
var s = $feature.OCI;
if (IsEmpty(s)) { return "No score"; }
When(s < 25, "Failed or serious",
     s < 40, "Very poor",
     s < 55, "Poor",
     s < 70, "Fair",
     s < 85, "Satisfactory",
     "Good");
```
4. Style **Types (unique symbols)**: Failed or serious `#B91C1C`, Very poor `#D4850A`, Poor `#E8B64C`, Fair `#9AA3AE`, Satisfactory `#6FB08C`, Good `#1A7A4A`, No score `#D4D8DF`. Line width and Minor's visibility range as in the table above.
5. Wards layer: no fill, dark outline 1.5 px, labels on with the ward number.
6. **Pop-ups > Attribute expressions > + Add expression** on each street layer:

`Inspected`
```
var d = $feature.InspectionDate;
if (IsEmpty(d)) { return "Never inspected (no date on file)"; }
var yrs = Round(DateDiff(Now(), d, "years"), 1);
return Text(d, "MMM YYYY") + " (" + yrs + " years ago)" + IIf(yrs > 3, ". Due for re-inspection.", "");
```
`Between`
```
var a = $feature.RouteBack; var b = $feature.RouteAhead;
IIf(a == b, "Near " + a, a + " to " + b)
```
Pop-up title `{StreetName}`. Body: `Condition score {OCI} out of 100 ({expression/Condition}). Between: {expression/Between}. Inspected: {expression/Inspected}. Ward {Ward}.`

7. **Save as** `Tucson Street Conditions`, tags `pavement, Tucson, OCI`, sharing **Owner only**. A UA organizational account can close after graduation, so the site page stays the main copy. Sharing it publicly is publishing: Jake's call.
