param([string]$Page, [string]$Out, [int]$X = 49, [int]$Y = 228, [int]$W = 1252, [int]$H = 762)
$s = $PSScriptRoot
if ($Page) { & "$s\uia.ps1" -Name $Page -ControlType TabItem | Out-Null; Start-Sleep -Seconds 6 }
$full = "$s\_full.png"
& "$s\winshot.ps1" -Out $full -MaxWidth 5000 | Out-Null
Add-Type -AssemblyName System.Drawing
$img = [System.Drawing.Bitmap]::FromFile($full)
$crop = $img.Clone((New-Object System.Drawing.Rectangle $X, $Y, $W, $H), $img.PixelFormat)
$img.Dispose()
$enc = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object MimeType -eq 'image/jpeg'
$ep = New-Object System.Drawing.Imaging.EncoderParameters 1
$ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), 88L
$crop.Save($Out, $enc, $ep); $crop.Dispose()
"$Out"
