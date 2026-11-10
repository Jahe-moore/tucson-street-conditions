param([string]$Name, [string]$List = '', [string]$ProcessName = 'PBIDesktop', [int]$Index = 0, [string]$ControlType = '')
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
$root = [System.Windows.Automation.AutomationElement]::RootElement
$pids = @(Get-Process $ProcessName -ErrorAction SilentlyContinue | ForEach-Object Id)
$cond = New-Object System.Windows.Automation.OrCondition (@($pids | ForEach-Object { New-Object System.Windows.Automation.PropertyCondition ([System.Windows.Automation.AutomationElement]::ProcessIdProperty), $_ }) + @([System.Windows.Automation.Condition]::FalseCondition))
$wins = $root.FindAll([System.Windows.Automation.TreeScope]::Children, $cond)
if ($List) {
  foreach ($w in $wins) {
    "WINDOW: $($w.Current.Name)"
    $all = $w.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
    foreach ($e in $all) { $n = $e.Current.Name; if ($n -and $n -match $List) { "  [$($e.Current.ControlType.ProgrammaticName)] '$n' enabled=$($e.Current.IsEnabled)" } }
  }
  return
}
$hits = @()
foreach ($w in $wins) {
  $c = New-Object System.Windows.Automation.PropertyCondition ([System.Windows.Automation.AutomationElement]::NameProperty), $Name
  $found = $w.FindAll([System.Windows.Automation.TreeScope]::Descendants, $c)
  foreach ($f in $found) { if (-not $ControlType -or $f.Current.ControlType.ProgrammaticName -match $ControlType) { $hits += $f } }
}
if ($hits.Count -le $Index) { "NOT FOUND: $Name"; exit 1 }
$e = $hits[$Index]
$ip = $null
if ($e.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$ip)) { $ip.Invoke(); "invoked '$Name' [$($e.Current.ControlType.ProgrammaticName)]"; exit 0 }
$sp = $null
if ($e.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$sp)) { $sp.Select(); "selected '$Name'"; exit 0 }
$tp = $null
if ($e.TryGetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern, [ref]$tp)) { $tp.Toggle(); "toggled '$Name'"; exit 0 }
"no pattern on '$Name'"; exit 2
