# Build the ArcGIS Online map (about 20 minutes)

No ArcGIS Pro install needed. Everything here runs in the browser at arcgis.com, signed in with the UA account.
The map points at the city's own published layers, so it stays current without any upload.

| Layer | ArcGIS Online item | Owner |
|---|---|---|
| Pavement Conditions - Major Streets | `00a290def9cf4c16a0d5b87f2b282c67` | City of Tucson |
| Pavement Conditions - Minor Streets | `02bfd7ae183c4c8ebb2d74c02984ce35` | City of Tucson |
| Wards - City of Tucson | `025e8235c2ab4b09ba4e202d28cc2fc1` | Pima County GIS open data |

## 1. Add the layers (5 min)
1. arcgis.com > **Map** (opens Map Viewer). Basemap: **Light Gray Canvas**.
2. **Layers > Add > Browse layers > ArcGIS Online**. Search each item ID above and **Add to map**. Order from top: Wards, Major, Minor.
3. Zoom to Tucson. Save now: **Save and open > Save as**, title `Tucson Street Conditions`, tags `pavement, Tucson, OCI`. Keep sharing on **Owner only** for now.

## 2. Color streets by condition with Arcade (10 min)
Do this on both street layers.

1. Select the layer > **Styles** > **Expression** (the `+ Expression` button under Choose attributes).
2. Paste, title it `Condition`:
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
3. Style: **Types (unique symbols)**. Colors, same as the Power BI report: Failed or serious `#B91C1C`, Very poor `#D4850A`, Poor `#E8B64C`, Fair `#9AA3AE`, Satisfactory `#6FB08C`, Good `#1A7A4A`, No score `#D4D8DF`.
4. Line width: Major 2.5 px, Minor 1 px. Set Minor's **visibility range** so it only draws when zoomed in to neighborhoods.
5. Wards layer: no fill, dark outline 1.5 px, **Labels** on with the ward number.

## 3. Pop-ups that read like English (5 min)
On each street layer: **Pop-ups > Attribute expressions > + Add expression**.

`Inspected` expression:
```
var d = $feature.InspectionDate;
if (IsEmpty(d)) { return "Never inspected (no date on file)"; }
var yrs = Round(DateDiff(Now(), d, "years"), 1);
return Text(d, "MMM YYYY") + " (" + yrs + " years ago)" + IIf(yrs > 3, ". Due for re-inspection.", "");
```
`Between` expression:
```
var a = $feature.RouteBack; var b = $feature.RouteAhead;
IIf(a == b, "Near " + a, a + " to " + b)
```
Pop-up title: `{StreetName}`. Body text:
`Condition score {OCI} out of 100 ({expression/Condition}). Between: {expression/Between}. Inspected: {expression/Inspected}. Ward {Ward}.`

## 4. Save, screenshot, share (Jake's call)
- Save. Take two screenshots for the site: the whole city, and one ward zoomed in with a pop-up open. Save them to `docs\img\arcgis-city.png` and `docs\img\arcgis-ward.png`.
- **Keep the screenshots.** A UA organizational account can close after graduation and the map goes with it.
- Sharing the map publicly is publishing; decide before switching it from Owner to Everyone.
