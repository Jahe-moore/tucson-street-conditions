# Shared functions for the Tucson street data loader. Windows PowerShell 5.1, no extra modules.
Set-StrictMode -Version 3.0

$script:Layers = @{
    major      = 'https://services3.arcgis.com/9coHY2fvuFjG9HQX/arcgis/rest/services/Pavement_Condition_Major_Streets_HFL/FeatureServer/20'
    minor      = 'https://services3.arcgis.com/9coHY2fvuFjG9HQX/arcgis/rest/services/Pavement_Condition_Minor_Streets_HFL/FeatureServer/21'
    moratorium = 'https://services3.arcgis.com/9coHY2fvuFjG9HQX/arcgis/rest/services/Pavement_Moratorium_Major_Roads_HFL/FeatureServer/22'
}

function Get-LayerUrl([string]$Layer) { $script:Layers[$Layer] }

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO', [string]$LogFile)
    $line = '{0:yyyy-MM-dd HH:mm:ss} {1,-5} {2}' -f (Get-Date), $Level, $Message
    Write-Host $line
    if ($LogFile) { Add-Content -Path $LogFile -Value $line -Encoding UTF8 }
}

function Invoke-WithRetry {
    # Retries a script block with backoff: 2s, 4s, 8s. Throws after the last attempt.
    param([scriptblock]$Action, [int]$MaxAttempts = 4, [int]$BaseDelaySeconds = 2, [string]$LogFile)
    for ($i = 1; $i -le $MaxAttempts; $i++) {
        try { return & $Action }
        catch {
            if ($i -eq $MaxAttempts) { throw }
            $wait = $BaseDelaySeconds * [math]::Pow(2, $i - 1)
            Write-Log "Attempt $i failed: $($_.Exception.Message). Retrying in $wait s." 'WARN' $LogFile
            Start-Sleep -Seconds $wait
        }
    }
}

function Get-PolylineMidpoint {
    # Middle vertex of the first path. Good enough to place a dot on a Power BI map.
    param($Geometry)
    if (-not $Geometry -or -not $Geometry.paths -or $Geometry.paths.Count -eq 0) { return $null }
    $path = $Geometry.paths[0]
    $pt = $path[[math]::Floor($path.Count / 2)]
    [pscustomobject]@{ Lon = [double]$pt[0]; Lat = [double]$pt[1] }
}

function Get-LayerFeatures {
    # Pages through an ArcGIS feature layer. Page size stays at 1000 because Windows PowerShell's
    # JSON reader struggles with very large responses.
    param(
        [Parameter(Mandatory)][string]$Url,
        [string]$Where = '1=1',
        [switch]$WithGeometry,
        [int]$PageSize = 1000,
        [string]$LogFile
    )
    $all = New-Object System.Collections.Generic.List[object]
    $offset = 0
    do {
        $q = @{
            where = $Where; outFields = '*'; orderByFields = 'OBJECTID'; f = 'json'
            resultOffset = $offset; resultRecordCount = $PageSize
            returnGeometry = $(if ($WithGeometry) { 'true' } else { 'false' })
        }
        if ($WithGeometry) { $q.outSR = 4326; $q.geometryPrecision = 6; $q.maxAllowableOffset = 0.0001 }
        $page = Invoke-WithRetry -LogFile $LogFile -Action { Invoke-RestMethod -Uri "$Url/query" -Body $q -Method Get -TimeoutSec 120 }
        if ($page.PSObject.Properties['error']) { throw "ArcGIS error $($page.error.code): $($page.error.message)" }
        foreach ($f in $page.features) { $all.Add($f) }
        $offset += $page.features.Count
        $more = ($page.PSObject.Properties['exceededTransferLimit'] -and $page.exceededTransferLimit) -or $page.features.Count -eq $PageSize
    } while ($more -and $page.features.Count -gt 0)
    , $all
}

function ConvertTo-SegmentTable {
    # API features -> DataTable shaped like stg.street_segment
    param([Parameter(Mandatory)]$Features)
    $t = New-Object System.Data.DataTable
    $cols = [ordered]@{
        cartegraph_id = [string]; street_name = [string]; from_desc = [string]; to_desc = [string]
        complexity = [string]; jurisdiction = [string]; custodian = [string]; ward_raw = [string]
        length_ft = [double]; width_ft = [double]; area_sqft = [double]; inspection_ms = [long]; oci = [double]
        is_protected = [int16]; replaced_ms = [long]; last_edited_ms = [long]; mid_lat = [double]; mid_lon = [double]
    }
    foreach ($c in $cols.Keys) { [void]$t.Columns.Add($c, $cols[$c]) }
    foreach ($f in $Features) {
        $a = $f.attributes
        $r = $t.NewRow()
        $r.cartegraph_id = [string]$a.CartegraphID
        $r.street_name   = $a.StreetName
        $r.from_desc     = $a.RouteBack     # cross street at the start of the segment
        $r.to_desc       = $a.RouteAhead    # cross street at the end
        $r.complexity    = $a.Complexity
        $r.jurisdiction  = $a.Jurisdiction
        $r.custodian     = $a.Custodian
        $r.ward_raw      = $a.Ward
        foreach ($pair in @(@('length_ft','Length'), @('width_ft','PavementWidth'), @('area_sqft','PavementArea'),
                            @('inspection_ms','InspectionDate'), @('oci','OCI'), @('is_protected','IsProtected'),
                            @('replaced_ms','Replaced'), @('last_edited_ms','last_edited_date'))) {
            $v = $a.($pair[1]); $r[$pair[0]] = if ($null -eq $v) { [DBNull]::Value } else { $v }
        }
        $mid = if ($f.PSObject.Properties['geometry']) { Get-PolylineMidpoint $f.geometry } else { $null }
        if ($mid) { $r.mid_lat = $mid.Lat; $r.mid_lon = $mid.Lon } else { $r.mid_lat = [DBNull]::Value; $r.mid_lon = [DBNull]::Value }
        $t.Rows.Add($r)
    }
    , $t
}

function ConvertTo-MoratoriumTable {
    param([Parameter(Mandatory)]$Features)
    $t = New-Object System.Data.DataTable
    foreach ($c in 'cartegraph_id','street_name','from_name','to_name') { [void]$t.Columns.Add($c, [string]) }
    foreach ($c in 'last_recon_ms','moratorium_end_ms') { [void]$t.Columns.Add($c, [long]) }
    foreach ($f in $Features) {
        $a = $f.attributes
        $r = $t.NewRow()
        $r.cartegraph_id = [string]$a.CartegraphID
        $r.street_name = $a.STREETNAME; $r.from_name = $a.FromName; $r.to_name = $a.ToName
        $r.last_recon_ms     = if ($null -eq $a.Last_Recon_Date) { [DBNull]::Value } else { $a.Last_Recon_Date }
        $r.moratorium_end_ms = if ($null -eq $a.MOR_END_DATE)    { [DBNull]::Value } else { $a.MOR_END_DATE }
        $t.Rows.Add($r)
    }
    , $t
}

function Test-DuplicateKeys {
    # Returns the keys that appear more than once. The merge would fail on these, so the loader stops first.
    param([System.Data.DataTable]$Table, [string]$Column = 'cartegraph_id')
    @($Table.Rows | Group-Object { $_[$Column] } | Where-Object Count -gt 1 | ForEach-Object Name)
}

# ---- SQL helpers (System.Data.SqlClient ships with .NET Framework) ----

function New-SqlConnection([string]$ConnectionString) {
    $c = New-Object System.Data.SqlClient.SqlConnection $ConnectionString
    $c.Open(); $c
}

function Invoke-Sql {
    param([System.Data.SqlClient.SqlConnection]$Connection, [string]$Query, [hashtable]$Parameters = @{}, [switch]$Scalar, [int]$Timeout = 300)
    $cmd = $Connection.CreateCommand(); $cmd.CommandText = $Query; $cmd.CommandTimeout = $Timeout
    foreach ($k in $Parameters.Keys) { [void]$cmd.Parameters.AddWithValue("@$k", $(if ($null -eq $Parameters[$k]) { [DBNull]::Value } else { $Parameters[$k] })) }
    if ($Scalar) { return $cmd.ExecuteScalar() }
    # the adapter reads every result set and closes the reader; the last one is returned
    $ds = New-Object System.Data.DataSet
    [void](New-Object System.Data.SqlClient.SqlDataAdapter $cmd).Fill($ds)
    if ($ds.Tables.Count -eq 0) { return , (New-Object System.Data.DataTable) }
    , $ds.Tables[$ds.Tables.Count - 1]
}

function Invoke-SqlScript {
    # Runs a .sql file the way sqlcmd does: split on lines that say GO.
    param([System.Data.SqlClient.SqlConnection]$Connection, [string]$Path, [string]$Database = 'TucsonStreets')
    $text = Get-Content -Raw -Path $Path
    if ($Database -ne 'TucsonStreets') { $text = $text -replace '\bTucsonStreets\b', $Database }
    foreach ($batch in [regex]::Split($text, '(?im)^\s*GO\s*$')) {
        if ($batch.Trim()) { [void](Invoke-Sql -Connection $Connection -Query $batch) }
    }
}

function Write-Staging {
    param([System.Data.SqlClient.SqlConnection]$Connection, [System.Data.DataTable]$Table, [string]$Destination)
    [void](Invoke-Sql $Connection "TRUNCATE TABLE $Destination")
    $bc = New-Object System.Data.SqlClient.SqlBulkCopy $Connection
    $bc.DestinationTableName = $Destination; $bc.BatchSize = 2000; $bc.BulkCopyTimeout = 300
    foreach ($col in $Table.Columns) { [void]$bc.ColumnMappings.Add($col.ColumnName, $col.ColumnName) }
    $bc.WriteToServer($Table); $bc.Close()
}

Export-ModuleMember -Function *
