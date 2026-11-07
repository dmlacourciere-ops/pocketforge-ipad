param(
    [string]$RepositoryRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
)

# Original geometric PocketForge mark. Run on Windows with System.Drawing;
# no font, downloaded artwork, application build, or API call is required.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$iconBackground = [System.Drawing.ColorTranslator]::FromHtml('#111314')
$iconAccent = [System.Drawing.ColorTranslator]::FromHtml('#8cdac3')

function Write-PocketForgeIcon([int]$Size, [string]$Destination) {
    $bitmap = [System.Drawing.Bitmap]::new($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $pen = [System.Drawing.Pen]::new($iconAccent, [single]($Size * 80.0 / 1024))
    try {
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.Clear($iconBackground)
        $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
        $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
        $factor = $Size / 1024.0
        $left = [System.Drawing.PointF[]]@(
            [System.Drawing.PointF]::new([single](420 * $factor), [single](345 * $factor)),
            [System.Drawing.PointF]::new([single](255 * $factor), [single](512 * $factor)),
            [System.Drawing.PointF]::new([single](420 * $factor), [single](679 * $factor))
        )
        $right = [System.Drawing.PointF[]]@(
            [System.Drawing.PointF]::new([single](604 * $factor), [single](345 * $factor)),
            [System.Drawing.PointF]::new([single](769 * $factor), [single](512 * $factor)),
            [System.Drawing.PointF]::new([single](604 * $factor), [single](679 * $factor))
        )
        $graphics.DrawLines($pen, $left)
        $graphics.DrawLines($pen, $right)
        $bitmap.Save($Destination, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $pen.Dispose()
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

$nativeDirectory = Join-Path $RepositoryRoot 'flutter_app/ios/Runner/Assets.xcassets/AppIcon.appiconset'
$catalog = Get-Content -LiteralPath (Join-Path $nativeDirectory 'Contents.json') -Raw | ConvertFrom-Json
$written = [System.Collections.Generic.HashSet[string]]::new()
foreach ($entry in $catalog.images) {
    if ($written.Add($entry.filename)) {
        $points = [double]($entry.size.Split('x')[0])
        $scale = [double]($entry.scale.TrimEnd('x'))
        Write-PocketForgeIcon -Size ([int]($points * $scale)) -Destination (Join-Path $nativeDirectory $entry.filename)
    }
}

$webDirectory = Join-Path $RepositoryRoot 'flutter_app/web'
foreach ($size in @(192, 512)) {
    foreach ($name in @("Icon-$size.png", "Icon-maskable-$size.png")) {
        Write-PocketForgeIcon -Size $size -Destination (Join-Path $webDirectory "icons/$name")
    }
}
Write-PocketForgeIcon -Size 64 -Destination (Join-Path $webDirectory 'favicon.png')

$vector = @'
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <rect width="1024" height="1024" rx="200" fill="#111314"/>
  <path d="M420 345 255 512 420 679 M604 345 769 512 604 679" fill="none" stroke="#8cdac3" stroke-width="80" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
'@
Set-Content -LiteralPath (Join-Path $webDirectory 'favicon.svg') -Value $vector -Encoding utf8NoBOM
Write-Output "Generated $($written.Count) native icons, four web icons, and PNG/SVG favicons."
