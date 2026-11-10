<#
.SYNOPSIS
  Pulls Tucson's public pavement condition and moratorium layers from the city's ArcGIS service
  and loads them into SQL Server: stage, merge, quality checks, one log row per layer.

.PARAMETER Mode
  full         every row; segments missing from the city layer are flagged as removed
  incremental  only rows the city edited since the last successful load of that layer

.EXAMPLE
  .\etl\Load-StreetData.ps1                    # full load of all three layers
  .\etl\Load-StreetData.ps1 -Mode incremental  # nightly
.NOTES
  Exit code 0 = success, 1 = a layer failed or a data quality check returned an error.
#>
param(
    [ValidateSet('full', 'incremental')][string]$Mode = 'full',
    [string[]]$Layers = @('major', 'minor', 'moratorium'),
    [string]$Server = 'localhost\SQLEXPRESS',
    [string]$Database = 'TucsonStreets',
    [string]$LogDir = (Join-Path (Split-Path $PSScriptRoot -Parent) 'logs')
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'StreetData.psm1') -Force

# "powershell -File" passes "major,minor" as one string, so split it here and reject unknown names up front
$Layers = @($Layers | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$unknown = @($Layers | Where-Object { -not (Get-LayerUrl $_) })
if ($unknown.Count) { throw "Unknown layer(s): $($unknown -join ', '). Use major, minor, moratorium." }

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$logFile = Join-Path $LogDir ('load_{0:yyyy-MM-dd}.log' -f (Get-Date))
$conn = New-SqlConnection "Server=$Server;Database=$Database;Integrated Security=True;TrustServerCertificate=True;Application Name=StreetDataLoader"
$failed = $false
$lastRun = $null

Write-Log "Start: mode=$Mode layers=$($Layers -join ',')" 'INFO' $logFile
try {
    foreach ($layer in $Layers) {
        $runId = Invoke-Sql $conn "INSERT etl.run_log (layer, mode) OUTPUT inserted.run_id VALUES (@l, @m)" @{ l = $layer; m = $Mode } -Scalar
        $lastRun = $runId
        try {
            # incremental: ask the city only for rows edited since our last good load of this layer
            $where = '1=1'
            if ($Mode -eq 'incremental' -and $layer -ne 'moratorium') {
                $since = Invoke-Sql $conn @"
SELECT MAX(s.source_edited_at) FROM core.street_segment s
WHERE s.street_class = @c
"@ @{ c = $(if ($layer -eq 'major') { 'Major' } else { 'Minor' }) } -Scalar
                if ($since -isnot [DBNull]) { $where = "last_edited_date > TIMESTAMP '{0:yyyy-MM-dd HH:mm:ss}'" -f $since }
            }

            $features = Get-LayerFeatures -Url (Get-LayerUrl $layer) -Where $where -WithGeometry:($layer -ne 'moratorium') -LogFile $logFile
            Write-Log "$layer : downloaded $($features.Count) rows (where $where)" 'INFO' $logFile

            if ($layer -eq 'moratorium') {
                $table = ConvertTo-MoratoriumTable $features
                $dupes = Test-DuplicateKeys $table
                if ($dupes.Count) { throw "Duplicate CartegraphID in source: $($dupes -join ', ')" }
                Write-Staging $conn $table 'stg.moratorium'
                [void](Invoke-Sql $conn 'EXEC etl.usp_merge_moratorium @run_id = @r' @{ r = $runId })
            } else {
                $table = ConvertTo-SegmentTable $features
                $dupes = Test-DuplicateKeys $table
                if ($dupes.Count) { throw "Duplicate CartegraphID in source: $($dupes -join ', ')" }
                Write-Staging $conn $table 'stg.street_segment'
                $class = if ($layer -eq 'major') { 'Major' } else { 'Minor' }
                # an incremental pull is partial, so the merge must not flag missing rows as removed
                [void](Invoke-Sql $conn 'EXEC etl.usp_merge_segments @run_id = @r, @street_class = @c, @mode = @m' @{ r = $runId; c = $class; m = $Mode })
            }

            [void](Invoke-Sql $conn "UPDATE etl.run_log SET status = 'success', finished_at = SYSDATETIME() WHERE run_id = @r" @{ r = $runId })
            $s = (Invoke-Sql $conn 'SELECT rows_read, rows_inserted, rows_updated, rows_unchanged FROM etl.run_log WHERE run_id = @r' @{ r = $runId }).Rows[0]
            Write-Log ("{0} : read {1}, new {2}, changed {3}, unchanged {4}" -f $layer, $s.rows_read, $s.rows_inserted, $s.rows_updated, $s.rows_unchanged) 'INFO' $logFile
        }
        catch {
            $failed = $true
            $msg = $_.Exception.Message
            if ($msg.Length -gt 2000) { $msg = $msg.Substring(0, 2000) }
            [void](Invoke-Sql $conn "UPDATE etl.run_log SET status = 'failed', finished_at = SYSDATETIME(), error_message = @e WHERE run_id = @r" @{ r = $runId; e = $msg })
            Write-Log "$layer : FAILED: $msg" 'ERROR' $logFile
        }
    }

    if ($lastRun) {
        $checks = Invoke-Sql $conn 'EXEC dq.usp_run_checks @run_id = @r' @{ r = $lastRun }
        foreach ($c in $checks.Rows) {
            $lvl = if ($c.row_count -eq 0) { 'OK' } else { @{ error = 'ERROR'; warn = 'WARN'; info = 'INFO' }[$c.severity] }
            Write-Log ("check {0}: {1} rows" -f $c.check_name, $c.row_count) $lvl $logFile
            if ($c.severity -eq 'error' -and $c.row_count -gt 0) { $failed = $true }
        }
    }
}
finally { $conn.Close() }

Write-Log ("Finished: {0}" -f $(if ($failed) { 'FAILED' } else { 'OK' })) $(if ($failed) { 'ERROR' } else { 'INFO' }) $logFile
exit $(if ($failed) { 1 } else { 0 })
