param([string]$Out, [string]$ProcessName = 'PBIDesktop', [int]$MaxWidth = 1600, [int]$Handle = 0)
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class PW {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
[void][PW]::SetProcessDPIAware()
$h = if ($Handle) { [IntPtr]$Handle } else { (Get-Process $ProcessName | Where-Object MainWindowHandle -ne 0 | Select-Object -First 1).MainWindowHandle }
if ([PW]::IsIconic($h)) { [void][PW]::ShowWindow($h, 4) ; Start-Sleep -Milliseconds 500 }
$r = New-Object PW+RECT; [void][PW]::GetWindowRect($h, [ref]$r)
$wd = $r.Right - $r.Left; $ht = $r.Bottom - $r.Top
$bmp = New-Object System.Drawing.Bitmap $wd, $ht
$g = [System.Drawing.Graphics]::FromImage($bmp); $hdc = $g.GetHdc()
[void][PW]::PrintWindow($h, $hdc, 2); $g.ReleaseHdc($hdc)
if ($bmp.Width -gt $MaxWidth) {
  $nh = [int]($bmp.Height * $MaxWidth / $bmp.Width); $small = New-Object System.Drawing.Bitmap $MaxWidth, $nh
  $g2 = [System.Drawing.Graphics]::FromImage($small); $g2.InterpolationMode = 'HighQualityBicubic'; $g2.DrawImage($bmp, 0, 0, $MaxWidth, $nh); $bmp = $small }
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
"$Out ${wd}x${ht}"
