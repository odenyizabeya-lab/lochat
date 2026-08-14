# Regenerates the LoText icon set from the official logo file
# (assets/logo.png). Every output is a high-quality resize of that one file -
# nothing is redrawn or recomposed.
# Outputs:
#   - store_icon.png                      (512x512, Play Console)
#   - android res/mipmap-* ic_launcher / ic_launcher_round / foreground
#   - web favicon.png + icons/Icon-192/512 + maskable variants
#   - ios Runner/Assets.xcassets AppIcon.appiconset/*.png
# Run:  powershell -ExecutionPolicy Bypass -File tool\generate_icons.ps1
Add-Type -AssemblyName System.Drawing

function Save-Resized($source, [int]$size, [string]$path) {
    $dir = Split-Path $path -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $src = [System.Drawing.Image]::FromFile($source)
    $bmp = [System.Drawing.Bitmap]::new($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.DrawImage($src, 0, 0, $size, $size)
    $g.Dispose()
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    $src.Dispose()
    Write-Host "wrote $path"
}

$root = Split-Path -Parent $PSScriptRoot
$logo = Join-Path $root 'assets\logo.png'
$res = Join-Path $root 'android\app\src\main\res'
$ios = Join-Path $root 'ios\Runner\Assets.xcassets\AppIcon.appiconset'
$webIcons = Join-Path $root 'web\icons'

if (-not (Test-Path $logo)) {
    throw "Logo file not found: $logo"
}

# 1. Play Console icon.
Save-Resized $logo 512 (Join-Path $root 'store_icon.png')

# 2. Legacy Android launcher icons per density.
$density = @{
    'mipmap-mdpi'    = 48
    'mipmap-hdpi'    = 72
    'mipmap-xhdpi'   = 96
    'mipmap-xxhdpi'  = 144
    'mipmap-xxxhdpi' = 192
}
foreach ($entry in $density.GetEnumerator()) {
    $dir = Join-Path $res $entry.Key
    $s = [int]$entry.Value
    Save-Resized $logo $s (Join-Path $dir 'ic_launcher.png')
    Save-Resized $logo $s (Join-Path $dir 'ic_launcher_round.png')
}

# 3. Android adaptive-icon foreground per density.
$foreground = @{
    'mipmap-mdpi'    = 108
    'mipmap-hdpi'    = 162
    'mipmap-xhdpi'   = 216
    'mipmap-xxhdpi'  = 324
    'mipmap-xxxhdpi' = 432
}
foreach ($entry in $foreground.GetEnumerator()) {
    Save-Resized $logo ([int]$entry.Value) (Join-Path (Join-Path $res $entry.Key) 'ic_launcher_foreground.png')
}

# 4. Web icons.
Save-Resized $logo 64 (Join-Path $root 'web\favicon.png')
Save-Resized $logo 192 (Join-Path $webIcons 'Icon-192.png')
Save-Resized $logo 512 (Join-Path $webIcons 'Icon-512.png')
Save-Resized $logo 192 (Join-Path $webIcons 'Icon-maskable-192.png')
Save-Resized $logo 512 (Join-Path $webIcons 'Icon-maskable-512.png')

# 5. iOS app icons.
$iosIcons = @{
    'Icon-App-20x20@1x.png'     = 20
    'Icon-App-20x20@2x.png'     = 40
    'Icon-App-20x20@3x.png'     = 60
    'Icon-App-29x29@1x.png'     = 29
    'Icon-App-29x29@2x.png'     = 58
    'Icon-App-29x29@3x.png'     = 87
    'Icon-App-40x40@1x.png'     = 40
    'Icon-App-40x40@2x.png'     = 80
    'Icon-App-40x40@3x.png'     = 120
    'Icon-App-60x60@2x.png'     = 120
    'Icon-App-60x60@3x.png'     = 180
    'Icon-App-76x76@1x.png'     = 76
    'Icon-App-76x76@2x.png'     = 152
    'Icon-App-83.5x83.5@2x.png' = 167
    'Icon-App-1024x1024@1x.png' = 1024
}
foreach ($entry in $iosIcons.GetEnumerator()) {
    Save-Resized $logo ([int]$entry.Value) (Join-Path $ios $entry.Key)
}

Write-Host 'All icons regenerated from assets/logo.png.'
