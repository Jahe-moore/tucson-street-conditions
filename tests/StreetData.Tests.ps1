# Pester 3.4 (ships with Windows). Run:  Invoke-Pester .\tests
# Unit tests need nothing. Integration tests build a throwaway database, TucsonStreets_Test, and drop it at the end.
$root = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'etl\StreetData.psm1') -Force

function New-Feature([hashtable]$a, $paths = $null) {
    $base = @{ CartegraphID = '1'; StreetName = 'N Test Av'; RouteBack = 'E One St'; RouteAhead = 'E Two St';
               Complexity = 'Local'; Jurisdiction = 'City of Tucson'; Custodian = 'City of Tucson'; Ward = '3';
               Length = 500; PavementWidth = 30; PavementArea = 15000; InspectionDate = 1711929600000; OCI = 50;
               IsProtected = 0; Replaced = $null; last_edited_date = 1762000000000 }
    foreach ($k in $a.Keys) { $base[$k] = $a[$k] }
    $f = [pscustomobject]@{ attributes = [pscustomobject]$base }
    if ($paths) { $f | Add-Member geometry ([pscustomobject]@{ paths = $paths }) }
    $f
}

Describe 'Unit: shaping API rows' {
    It 'takes the middle vertex of a line as its map point' {
        $m = Get-PolylineMidpoint ([pscustomobject]@{ paths = @(, @(@(-110.1, 32.1), @(-110.2, 32.2), @(-110.3, 32.3))) })
        $m.Lon | Should Be -110.2
        $m.Lat | Should Be 32.2
    }
    It 'returns nothing for a missing geometry' {
        Get-PolylineMidpoint $null | Should BeNullOrEmpty
    }
    It 'maps cross streets and turns API nulls into database nulls' {
        $t = ConvertTo-SegmentTable @(New-Feature @{ OCI = $null; Ward = '' })
        $t.Rows.Count | Should Be 1
        $t.Rows[0].from_desc | Should Be 'E One St'
        $t.Rows[0].to_desc | Should Be 'E Two St'
        $t.Rows[0].oci | Should Be ([DBNull]::Value)
    }
    It 'finds duplicate keys before they reach the merge' {
        $t = ConvertTo-SegmentTable @((New-Feature @{ CartegraphID = '7' }), (New-Feature @{ CartegraphID = '7' }), (New-Feature @{ CartegraphID = '8' }))
        Test-DuplicateKeys $t | Should Be '7'
    }
}

Describe 'Unit: retry' {
    It 'retries a failing call and returns once it works' {
        $script:n = 0
        $r = Invoke-WithRetry -BaseDelaySeconds 0 -Action { $script:n++; if ($script:n -lt 3) { throw 'timeout' }; 'ok' }
        $r | Should Be 'ok'
        $script:n | Should Be 3
    }
    It 'gives up after the last attempt' {
        { Invoke-WithRetry -MaxAttempts 2 -BaseDelaySeconds 0 -Action { throw 'down' } } | Should Throw 'down'
    }
}

Describe 'Integration: merge, history, quality checks, ward security' {
    $server = 'localhost\SQLEXPRESS'; $db = 'TucsonStreets_Test'
    & (Join-Path $root 'etl\Install-Database.ps1') -Server $server -Database $db | Out-Null
    $c = New-SqlConnection "Server=$server;Database=$db;Integrated Security=True"

    function Load([object[]]$features, [string]$mode = 'full') {
        $run = Invoke-Sql $c "INSERT etl.run_log (layer, mode) OUTPUT inserted.run_id VALUES ('minor', @m)" @{ m = $mode } -Scalar
        Write-Staging $c (ConvertTo-SegmentTable $features) 'stg.street_segment'
        [void](Invoke-Sql $c 'EXEC etl.usp_merge_segments @run_id=@r, @street_class=''Minor'', @mode=@m' @{ r = $run; m = $mode })
        [void](Invoke-Sql $c "UPDATE etl.run_log SET status='success' WHERE run_id=@r" @{ r = $run })
        (Invoke-Sql $c 'SELECT * FROM etl.run_log WHERE run_id=@r' @{ r = $run }).Rows[0]
    }
    $base = @(
        (New-Feature @{ CartegraphID = '101'; Ward = '3'; OCI = 20 }),
        (New-Feature @{ CartegraphID = '102'; Ward = '5'; OCI = 90 }),
        (New-Feature @{ CartegraphID = '103'; Ward = 'BOS 1'; Jurisdiction = 'Pima County' }),
        (New-Feature @{ CartegraphID = '104'; Ward = ''; Replaced = -2208988800000 })   # 1900-01-01 placeholder
    )

    It 'inserts every row on the first load' {
        $r = Load $base
        $r.rows_inserted | Should Be 4
    }
    It 'changes nothing when the same data loads again' {
        $r = Load $base
        $r.rows_unchanged | Should Be 4
        $r.rows_updated | Should Be 0
    }
    It 'keeps only wards 1 to 6 and turns county districts and blanks into no ward' {
        (Invoke-Sql $c "SELECT COUNT(*) FROM core.street_segment WHERE cartegraph_id IN ('103','104') AND ward_id IS NULL" -Scalar) | Should Be 2
    }
    It 'treats the 1900 placeholder date as unknown' {
        (Invoke-Sql $c "SELECT last_treated_date FROM core.street_segment WHERE cartegraph_id='104'" -Scalar) | Should Be ([DBNull]::Value)
    }
    It 'records a history row when a score changes' {
        $changed = @($base[0], $base[1], $base[2], $base[3]); $changed[0] = New-Feature @{ CartegraphID = '101'; Ward = '3'; OCI = 95 }
        $r = Load $changed
        $r.rows_updated | Should Be 1
        (Invoke-Sql $c "SELECT COUNT(*) FROM core.condition_history WHERE cartegraph_id='101'" -Scalar) | Should Be 2
    }
    It 'flags a segment the city removed, but only on a full load' {
        $filler = 1..16 | ForEach-Object { New-Feature @{ CartegraphID = "40$_" } }
        Load (@($base) + $filler) 'full' | Out-Null                    # 20 rows
        $minus101 = @($base[1], $base[2], $base[3]) + $filler           # 19 rows: 101 is gone
        Load $minus101 'incremental' | Out-Null
        (Invoke-Sql $c "SELECT removed_from_source FROM core.street_segment WHERE cartegraph_id='101'" -Scalar) | Should Be $false
        Load $minus101 'full' | Out-Null
        (Invoke-Sql $c "SELECT removed_from_source FROM core.street_segment WHERE cartegraph_id='101'" -Scalar) | Should Be $true
    }
    It 'shows a ward office only its own ward' {
        (Invoke-Sql $c "EXECUTE AS USER='ward5_office'; SELECT COUNT(*) FROM rpt.fact_segment; REVERT;").Rows[0][0] | Should Be 1
        (Invoke-Sql $c "EXECUTE AS USER='ward5_office'; SELECT MAX(ward_id) FROM rpt.fact_segment; REVERT;").Rows[0][0] | Should Be 5
        $all = Invoke-Sql $c 'SELECT COUNT(*) FROM rpt.fact_segment' -Scalar
        (Invoke-Sql $c "EXECUTE AS USER='city_engineer'; SELECT COUNT(*) FROM rpt.fact_segment; REVERT;").Rows[0][0] | Should Be $all
    }
    It 'blocks a ward office from reading the base table directly' {
        { Invoke-Sql $c "EXECUTE AS USER='ward3_office'; SELECT COUNT(*) FROM core.street_segment; REVERT;" } | Should Throw 'permission'
        [void](Invoke-Sql $c 'IF USER_NAME() <> ''dbo'' REVERT;')
    }
    It 'fails the quality check when a score is out of range' {
        Load @((New-Feature @{ CartegraphID = '201'; OCI = 150 })) 'incremental' | Out-Null
        $run = Invoke-Sql $c 'SELECT MAX(run_id) FROM etl.run_log' -Scalar
        $checks = Invoke-Sql $c 'EXEC dq.usp_run_checks @run_id=@r' @{ r = $run }
        ($checks.Rows | Where-Object check_name -eq 'oci_out_of_range').row_count | Should Be 1
        ($checks.Rows | Where-Object check_name -eq 'county_district_in_ward_field').row_count | Should Be 1
    }
    It 'stops a partial full download before it marks real streets as removed' {
        $big = 1..20 | ForEach-Object { New-Feature @{ CartegraphID = "30$_" } }
        Load $big 'full' | Out-Null
        $before = Invoke-Sql $c 'SELECT COUNT(*) FROM core.street_segment WHERE removed_from_source = 1' -Scalar
        { Load $big[0..4] 'full' } | Should Throw 'Partial download'
        (Invoke-Sql $c 'SELECT COUNT(*) FROM core.street_segment WHERE removed_from_source = 1' -Scalar) | Should Be $before
    }

    $c.Close()
    $m = New-SqlConnection "Server=$server;Database=master;Integrated Security=True"
    [void](Invoke-Sql $m "ALTER DATABASE [$db] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$db];")
    $m.Close()
}
