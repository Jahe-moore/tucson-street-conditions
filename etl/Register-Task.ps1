<#
.SYNOPSIS  Schedules the nightly incremental load (2:15 AM) and a Sunday full load (3:15 AM) in Windows Task Scheduler.
           Runs as the current user, only when signed in. Remove with -Unregister.
.EXAMPLE   .\etl\Register-Task.ps1
.EXAMPLE   .\etl\Register-Task.ps1 -Unregister
#>
param([switch]$Unregister)
$ErrorActionPreference = 'Stop'
$names = 'Tucson Streets - nightly load', 'Tucson Streets - weekly full load'

if ($Unregister) {
    foreach ($n in $names) { if (Get-ScheduledTask -TaskName $n -ErrorAction SilentlyContinue) { Unregister-ScheduledTask -TaskName $n -Confirm:$false; "Removed $n" } }
    return
}

$script = Join-Path $PSScriptRoot 'Load-StreetData.ps1'
$work = Split-Path $PSScriptRoot -Parent
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 30) -MultipleInstances IgnoreNew

$jobs = @(
    @{ Name = $names[0]; Mode = 'incremental'; Trigger = New-ScheduledTaskTrigger -Daily -At 2:15am },
    @{ Name = $names[1]; Mode = 'full';        Trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 3:15am }
)
foreach ($j in $jobs) {
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -WorkingDirectory $work `
        -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$script`" -Mode $($j.Mode)"
    Register-ScheduledTask -TaskName $j.Name -Action $action -Trigger $j.Trigger -Settings $settings `
        -Description 'Loads City of Tucson pavement data into SQL Server. See docs/runbook.md.' -Force | Out-Null
    "Registered $($j.Name)"
}
