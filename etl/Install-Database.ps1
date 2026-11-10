<#
.SYNOPSIS  Creates or updates the street database. Safe to run again; every script is idempotent.
.EXAMPLE   .\etl\Install-Database.ps1
.EXAMPLE   .\etl\Install-Database.ps1 -Database TucsonStreets_Test   # throwaway copy for the tests
#>
param([string]$Server = 'localhost\SQLEXPRESS', [string]$Database = 'TucsonStreets')
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'StreetData.psm1') -Force

$sqlDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'sql'
$master = New-SqlConnection "Server=$Server;Database=master;Integrated Security=True;TrustServerCertificate=True"
try {
    Get-ChildItem $sqlDir -Filter '*.sql' | Sort-Object Name | ForEach-Object {
        Write-Host "Running $($_.Name)"
        Invoke-SqlScript -Connection $master -Path $_.FullName -Database $Database
    }
} finally { $master.Close() }
Write-Host "Database $Database ready."
