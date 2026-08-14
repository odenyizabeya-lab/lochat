# Regenerates the LoText icon set: a big SMS-style chat bubble with a long
# "mouth" (tail) pointing down, filled with the brand gradient, and the
# "LoText" wordmark centered in the middle of the bubble.
# Outputs:
#   - store_icon.png                    (512x512, Play Console)
#   - android res/mipmap-* ic_launcher / ic_launcher_round (white background)
#   - android res/mipmap-* ic_launcher_foreground.png (adaptive foreground,
#     bubble on transparent, central 66% safe zone)
#   - web favicon.png + icons/Icon-192/512 + maskable variants
#   - ios Runner/Assets.xcassets AppIcon.appiconset/*.png (white background)
# Run:  powershell -ExecutionPolicy Bypass -File tool\generate_icons.ps1
Add-Type -AssemblyName System.Drawing

# Draws a bubble logo filling a square of $size: rounded-rect bubble body with
# a long triangle tail at the bottom, brand gradient fill and centered text.
function New-LogoBitmap([int]$size) {
    $bmp = [System.Drawing.Bitmap]::new($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

    # Bubble body (rounded rectangle) centered horizontally, slightly above middle.
    $bubbleW = [int][math]::Round($size * 0.88)
    $bubbleH = [int][math]::Round($size * 0.56)
    $cx = [int][math]::Round($size / 2)
    $top = [int][math]::Round($size * 0.04)
    $left = $cx - [int][math]::Round($bubbleW / 2)
    $bottom = $top + $bubbleH
    $corner = [int][math]::Round($size * 0.16)
    $d = $corner * 2

    $path = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $path.AddArc($left, $top, $d, $d, 180, 90)
    $path.AddArc($left + $bubbleW - $d, $top, $d, $d, 270, 90)
    $path.AddArc($left + $bubbleW - $d, $bottom - $d, $d, $d, 0, 90)
    $path.AddArc($left, $bottom - $d, $d, $d, 90, 90)
    $path.CloseFigure()

    # Long mouth (tail): wide triangle pointing down from the bottom centre.
    $tailW = [int][math]::Round($size * 0.34)
    $tailH = [int][math]::Round($size * 0.30)
    $tailLeft = $cx - [int][math]::Round($tailW / 2)
    $points = [System.Drawing.Point[]]@(
        [System.Drawing.Point]::new($tailLeft, $bottom),
        [System.Drawing.Point]::new($tailLeft + $tailW, $bottom),
        [System.Drawing.Point]::new($cx, $bottom + $tailH)
    )
    $path.AddPolygon($points)
    $path.CloseFigure()

    # Brand gradient, top-left -> bottom-right (#8B5CF6 -> #4F46E5).
    $rect = [System.Drawing.Rectangle]::new(0, 0, $size - 1, $size - 1)
    $brush = [System.Drawing.Drawing2D.LinearGradientBrush]::new($rect, [System.Drawing.Color]::FromArgb(255, 139, 92, 246), [System.Drawing.Color]::FromArgb(255, 79, 70, 229), 0.0)
    $g.FillPath($brush, $path)

    # "LoText" wordmark, white and bold, centered in the middle of the bubble.
    $fs = [single]($size * 0.17)
    $font = [System.Drawing.Font]::new('Segoe UI', $fs, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $sf = [System.Drawing.StringFormat]::new()
    $sf.Alignment = [System.Drawing.StringAlignment]::Center
    $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
    $textHeight = [single]($fs * 1.4)
    $textTop = [single]($top + ($bubbleH - $textHeight) / 2)
    $textRect = [System.Drawing.RectangleF]::new($left, $textTop, $bubbleW, $textHeight)
    $white = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::White)
    $g.DrawString('LoText', $font, $white, $textRect, $sf)

    $white.Dispose(); $sf.Dispose(); $font.Dispose(); $brush.Dispose(); $path.Dispose()
    $g.Dispose()
    return $bmp
}

# Places the bubble logo (optionally scaled down via $fill) onto a canvas of
# $size. With $transparent = $false the background is solid white (required by
# iOS and store listings); otherwise it is left transparent for adaptive icons.
function New-IconBitmap([int]$size, [bool]$transparent, [single]$fill) {
    $bmp = [System.Drawing.Bitmap]::new($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    if (-not $transparent) {
        $g.Clear([System.Drawing.Color]::White)
    }
    $logoSize = [int][math]::Round($size * $fill)
    $offset = [int][math]::Round(($size - $logoSize) / 2)
    $logo = New-LogoBitmap $logoSize
    $g.DrawImage($logo, $offset, $offset, $logoSize, $logoSize)
    $logo.Dispose()
    $g.Dispose()
    return $bmp
}

function Save-Png($bmp, [string]$path) {
    $dir = Split-Path $path -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Host "wrote $path"
    $bmp.Dispose()
}

$root = Split-Path -Parent $PSScriptRoot
$res = Join-Path $root 'android\app\src\main\res'
$ios = Join-Path $root 'ios\Runner\Assets.xcassets\AppIcon.appiconset'
$webIcons = Join-Path $root 'web\icons'

# 1. Play Console icon (solid white background).
Save-Png (New-IconBitmap 512 $false 1.0) (Join-Path $root 'store_icon.png')

# 2. Legacy Android launcher icons (white background, full bubble).
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
    Save-Png (New-IconBitmap $s $false 1.0) (Join-Path $dir 'ic_launcher.png')
    Save-Png (New-IconBitmap $s $false 1.0) (Join-Path $dir 'ic_launcher_round.png')
}

# 3. Android adaptive-icon foreground: transparent canvas, bubble kept inside
#    the central 66% safe zone so launcher masks do not crop it.
$foreground = @{
    'mipmap-mdpi'    = 108
    'mipmap-hdpi'    = 162
    'mipmap-xhdpi'   = 216
    'mipmap-xxhdpi'  = 324
    'mipmap-xxxhdpi' = 432
}
foreach ($entry in $foreground.GetEnumerator()) {
    Save-Png (New-IconBitmap ([int]$entry.Value) $true 0.72) (Join-Path (Join-Path $res $entry.Key) 'ic_launcher_foreground.png')
}

# 4. Web icons: favicon, app icons (full bubble on white) and maskable
#    variants (bubble inside the 80% safe zone, white background full-bleed).
Save-Png (New-IconBitmap 64 $false 1.0) (Join-Path $root 'web\favicon.png')
Save-Png (New-IconBitmap 192 $false 1.0) (Join-Path $webIcons 'Icon-192.png')
Save-Png (New-IconBitmap 512 $false 1.0) (Join-Path $webIcons 'Icon-512.png')
Save-Png (New-IconBitmap 192 $false 0.72) (Join-Path $webIcons 'Icon-maskable-192.png')
Save-Png (New-IconBitmap 512 $false 0.72) (Join-Path $webIcons 'Icon-maskable-512.png')

# 5. iOS app icons (white background; bubble scaled down so Apple's ~23%
#    corner mask never clips it).
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
    Save-Png (New-IconBitmap ([int]$entry.Value) $false 0.82) (Join-Path $ios $entry.Key)
}

Write-Host 'All icons regenerated.'
