param([long]$Hwnd, [string]$Text)
. "$PSScriptRoot\iedom_lib.ps1" -Hwnd $Hwnd
$doc = [IE]::Doc([IntPtr]$Hwnd)
$frames = @($doc)
for ($i=0; $i -lt $doc.frames.length; $i++) { try { $frames += $doc.frames.item($i).document } catch {} }
foreach ($d in $frames) {
  foreach ($e in @($d.all)) {
    $t = "$($e.innerText)".Trim()
    if ($t -eq $Text -and $e.children.length -eq 0) { "found <$($e.tagName)> class=$($e.className)"; $e.click(); "clicked"; return }
  }
}
"not found in $($frames.Count) docs"
