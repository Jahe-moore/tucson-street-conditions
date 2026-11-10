# Waits for Power BI, clicks Refresh now, answers the SQL credential (current Windows user) and encryption prompts.
$s = $PSScriptRoot
. "$s\iedom_lib.ps1"
Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices; using System.Collections.Generic;
public static class RW { public delegate bool P(IntPtr h, IntPtr l);
 [DllImport("user32.dll")] public static extern bool EnumWindows(P p, IntPtr l);
 [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, P cb, IntPtr l);
 [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
 [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
 [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
 public static List<IntPtr> Tops(uint t){ var r=new List<IntPtr>(); EnumWindows((h,l)=>{uint q; GetWindowThreadProcessId(h,out q); if(q==t && IsWindowVisible(h)) r.Add(h); return true;},IntPtr.Zero); return r; }
 public static string Title(IntPtr h){ var s=new StringBuilder(256); GetWindowText(h,s,256); return s.ToString(); }
 public static IntPtr IeChild(IntPtr p){ IntPtr f=IntPtr.Zero; EnumChildWindows(p,(h,l)=>{var s=new StringBuilder(256); GetClassName(h,s,256); if(s.ToString()=="Internet Explorer_Server"){f=h; return false;} return true;},IntPtr.Zero); return f; } }
"@
function ClickIe([IntPtr]$ie, [string]$text) {
  $doc = [IE]::Doc($ie)
  foreach ($e in @($doc.all)) { if ("$($e.innerText)".Trim() -eq $text -and $e.children.length -eq 0) { $e.click(); return $true } }
  $false
}
$deadline = (Get-Date).AddMinutes(4); $clickedRefresh = $false; $sawLoad = $false
while ((Get-Date) -lt $deadline) {
  Start-Sleep -Seconds 3
  $p = Get-Process PBIDesktop -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $p) { continue }
  $tops = [RW]::Tops([uint32]$p.Id)
  $main = $tops | Where-Object { [RW]::Title($_) -like 'Tucson Street*' }
  if (-not $main) { continue }
  if (-not $clickedRefresh) {
    $r = & "$s\uia.ps1" -Name 'Refresh now'
    if ($r -like 'invoked*') { $clickedRefresh = $true; "refresh clicked (ribbon)" }
    continue
  }
  $others = @($tops | Where-Object { $_ -ne $main[0] })
  foreach ($h in $others) {
    $t = [RW]::Title($h)
    $ie = [RW]::IeChild($h)
    if ($ie -eq [IntPtr]::Zero) { continue }
    try { $txt = [IE]::Doc($ie).body.innerText } catch { continue }
    if ($txt -match 'unencrypted') { if (ClickIe $ie 'OK') { "encryption: OK" } }
    elseif ($txt -match 'current credentials') { if (ClickIe $ie 'Connect') { "credentials: Connect (current Windows user)" } }
    elseif ($txt -match 'Evaluating|rows loaded|Load') { $sawLoad = $true }
  }
  if ($others.Count -ge 1) { $sawDialog = $true }
  if ($sawDialog -and $others.Count -eq 0) { $quiet++ } else { $quiet = 0 }
  if ($quiet -ge 2) { "done"; break }
}
