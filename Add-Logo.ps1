<#
.SYNOPSIS
  Overlay an SVG logo on wallpapers with vector-accurate sizing (no bitmap resize),
  controllable position, optional recursion, and PNG/JPEG output.

.DESCRIPTION
  This script brands PNG wallpapers by compositing an SVG logo at a chosen position.
  It sizes the logo by percentage of the background, then computes an *exact*
  rasterization density so the SVG renders directly at the target pixel width
  (resize vector → then rasterize). This avoids post-raster bitmap resampling and
  yields the sharpest edges.

  Workflow per image:
    1) Read background dimensions.
    2) Compute target logo width from PercentOfSize applied to BaseDimension.
    3) Probe SVG size at 72 DPI to establish a baseline.
    4) Compute an exact density so the rendered logo is exactly targetLogoW pixels wide.
       (If probing fails, fall back to legacy: fixed density + -resize.)
    5) Rasterize the SVG at that density (no -resize in the normal path).
    6) Compute margin (either fixed pixels or ratio of the final logo height).
    7) Composite at the requested Position. For Center, margin is ignored.
    8) Write as PNG (max compression) or JPEG (requested quality/defines).
       When -Recurse is used, the input subfolder structure is mirrored.

  Compatible with PowerShell 5.x and 7.x. Requires ImageMagick `magick` on PATH.

.PARAMETER BackgroundFolder
  Root folder containing source PNG backgrounds.

.PARAMETER LogoSvg
  Path to the SVG logo.

.PARAMETER OutputFolder
  Root folder for outputs (created if missing). With -Recurse, the input subfolders
  are mirrored beneath this folder.

.PARAMETER PercentOfSize
  Fraction (e.g., 0.12 = 12%) applied to the chosen background dimension to set
  the logo's target pixel width.

.PARAMETER BaseDimension
  Basis for scaling: 'width' | 'height' | 'shorter'. Default: 'width'.

.PARAMETER Position
  Logo placement: 'TopLeft' | 'TopRight' | 'BottomRight' | 'BottomLeft' | 'Center'.
  Corner positions align the logo's corresponding corner to the image corner.
  Center ignores margin and centers the logo.

.PARAMETER MarginPx
  If >= 0, fixed pixel margin for BOTH X and Y (used only for corner positions).
  If < 0, margin is computed as (logoHeight * MarginLogoHeightRatio).
  Ignored when Position = 'Center'. Default: -1 (use ratio).

.PARAMETER MarginLogoHeightRatio
  Ratio of the final logo height used for margin when MarginPx < 0. Default: 0.25.

.PARAMETER SvgDensity
  Fallback rasterization density if SVG baseline probing fails (legacy path).
  Default: 300.

.PARAMETER OutputFormat
  Output format: 'png' or 'jpg' (alias 'jpeg'). Default: 'png'.
    - PNG: -define png:compression-level=9, -define png:color-type=6 (RGBA)
    - JPG: -quality 95, -define jpeg:optimize-coding=true,
           -define jpeg:dct-method=float, -sampling-factor 4:4:4

.PARAMETER Recurse
  When present, process PNGs in all subfolders and mirror the structure in OutputFolder.

.EXAMPLE
  # Recurse, top-right (default), PNG with max compression
  .\Add-Logo.ps1 `
    -BackgroundFolder "D:\Wallpapers" `
    -LogoSvg "D:\Brand\logo.svg" `
    -OutputFolder "D:\Out" `
    -PercentOfSize 0.1 `
    -BaseDimension width `
    -MarginLogoHeightRatio 1.5 `
    -Position TopRight `
    -OutputFormat png `
    -Recurse

.EXAMPLE
  # Bottom-left, fixed 72px margin, JPEG output
  .\Add-Logo.ps1 `
    -BackgroundFolder "D:\Wallpapers" `
    -LogoSvg "D:\Brand\logo.svg" `
    -OutputFolder "D:\OutJpg" `
    -PercentOfSize 0.12 `
    -BaseDimension shorter `
    -Position BottomLeft `
    -MarginPx 72 `
    -OutputFormat jpg

.EXAMPLE
  # Centered logo (margin ignored), exact vector sizing
  .\Add-Logo.ps1 `
    -BackgroundFolder "D:\Wallpapers" `
    -LogoSvg "D:\Brand\logo.svg" `
    -OutputFolder "D:\Out" `
    -PercentOfSize 0.2 `
    -BaseDimension shorter `
    -Position Center

.NOTES
  - Requires ImageMagick (https://imagemagick.org) with `magick` on PATH.
  - Input files must be PNG. Output can be PNG or JPEG.
  - JPEG cannot store transparency; the script disables alpha on JPEG export.
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string]$BackgroundFolder,
  [Parameter(Mandatory)] [string]$LogoSvg,
  [Parameter(Mandatory)] [string]$OutputFolder,

  [ValidateRange(0.001,1.0)]
  [double]$PercentOfSize = 0.12,

  [ValidateSet('width','height','shorter')]
  [string]$BaseDimension = 'width',

  [ValidateSet('TopLeft','TopRight','BottomRight','BottomLeft','Center')]
  [string]$Position = 'TopRight',

  [int]$MarginPx = -1,

  [ValidateRange(0.0, 2.0)]
  [double]$MarginLogoHeightRatio = 0.25,

  [ValidateRange(72,1200)]
  [int]$SvgDensity = 300,

  [ValidateSet('png','jpg','jpeg')]
  [string]$OutputFormat = 'png',

  [switch]$Recurse
)

function Get-RelativePath {
  param(
    [Parameter(Mandatory)][string]$BasePath,
    [Parameter(Mandatory)][string]$TargetPath
  )

  # Normalize to absolute paths and ensure trailing separator on base
  $baseFull   = [IO.Path]::GetFullPath($BasePath)
  $targetFull = [IO.Path]::GetFullPath($TargetPath)
  $baseWithSep = ($baseFull.TrimEnd('\','/')) + [IO.Path]::DirectorySeparatorChar

  try {
    $uBase   = New-Object System.Uri($baseWithSep, [System.UriKind]::Absolute)
    $uTarget = New-Object System.Uri($targetFull, [System.UriKind]::Absolute)

    # Make relative URI -> unescape any %xx -> normalize separators
    $relEscaped = $uBase.MakeRelativeUri($uTarget).ToString()
    $rel = [System.Uri]::UnescapeDataString($relEscaped).Replace('/', '\').TrimEnd('\')

    return $rel
  }
  catch {
    # Fallback if paths are on different volumes or URI fails
    if ($targetFull.StartsWith($baseWithSep, [StringComparison]::OrdinalIgnoreCase)) {
      $raw = $targetFull.Substring($baseWithSep.Length)
      return $raw.Replace('/', '\').TrimEnd('\')
    }
    return ""
  }
}


function Get-Gravity {
  param([Parameter(Mandatory)][string]$Pos)
  switch ($Pos) {
    'TopLeft'      { return 'northwest' }
    'TopRight'     { return 'northeast' }
    'BottomRight'  { return 'southeast' }
    'BottomLeft'   { return 'southwest' }
    'Center'       { return 'center' }
    default        { return 'northeast' }
  }
}

# --- Preconditions ---
if (-not (Get-Command magick -ErrorAction SilentlyContinue)) {
  throw "ImageMagick 'magick' CLI not found on PATH. Install it first."
}
if (-not (Test-Path -LiteralPath $BackgroundFolder)) {
  throw "BackgroundFolder not found: $BackgroundFolder"
}
if (-not (Test-Path -LiteralPath $LogoSvg)) {
  throw "LogoSvg not found: $LogoSvg"
}
if (-not (Test-Path -LiteralPath $OutputFolder)) {
  New-Item -ItemType Directory -Path $OutputFolder | Out-Null
}

# --- Enumerate PNGs (optionally recursive) ---
$pngs = Get-ChildItem -LiteralPath $BackgroundFolder -Filter *.png -File -Recurse:$Recurse -ErrorAction Stop
if (-not $pngs -or $pngs.Count -eq 0) {
  Write-Warning ("No PNG files found in '{0}' (Recurse={1})." -f $BackgroundFolder, $Recurse.IsPresent)
  return
}

# Normalize output format
$fmt = $OutputFormat.ToLower()
if ($fmt -eq 'jpeg') { $fmt = 'jpg' }
$ext = if ($fmt -eq 'png') { '.png' } else { '.jpg' }

$gravity   = Get-Gravity -Pos $Position
$useMargin = -not ($Position -eq 'Center')

foreach ($file in $pngs) {
  $bg = $file.FullName

  # 1) Background dimensions
  $dim = & magick identify -format "%w %h" -- "$bg" 2>$null
  if (-not $dim) { Write-Warning ("Could not read dimensions for '{0}'" -f $bg); continue }
  $parts = $dim -split '\s+'
  if ($parts.Count -lt 2) { Write-Warning ("Unexpected dimension output for '{0}': '{1}'" -f $bg, $dim); continue }
  [int]$bgW = $parts[0]; [int]$bgH = $parts[1]

  # 2) Target logo width from chosen base dimension
  [int]$basis = 0
  switch ($BaseDimension) {
    'width'   { $basis = $bgW }
    'height'  { $basis = $bgH }
    'shorter' { $basis = [math]::Min($bgW, $bgH) }
  }
  [int]$targetLogoW = [math]::Max([math]::Round($basis * $PercentOfSize), 1)

  # 3) Probe SVG baseline at 72 DPI to compute exact render density
  $svgW72 = 0
  $svgH72 = 0
  $probe72 = & magick -density 72 -background none "$LogoSvg" -format "%w %h" info: 2>$null
  if ($probe72) {
    $p = $probe72 -split '\s+'
    if ($p.Count -ge 2) {
      [int]$svgW72 = $p[0]
      [int]$svgH72 = $p[1]
    }
  }

  [bool]$useResizeFallback = $false
  [int]$svgExactDensity = $SvgDensity

  if ($svgW72 -gt 0) {
    # width scales ~linearly with density from the 72-DPI baseline
    $svgExactDensity = [math]::Max([math]::Round(72.0 * $targetLogoW / [double]$svgW72), 1)
  } else {
    # Fallback if probing failed (e.g., odd SVG metadata): use legacy path with -resize
    $useResizeFallback = $true
  }

  # Select density for the grouped SVG block (PS5-safe: no ternary)
  [int]$densityForRender = 0
  if ($useResizeFallback) { $densityForRender = $SvgDensity } else { $densityForRender = $svgExactDensity }

  # 4) Determine final logo dimensions to drive margin math
  $logoDims = $null
  if (-not $useResizeFallback) {
    # Normal (Option A): render at exact density, no resize
    $logoDims = & magick -density $densityForRender -background none "$LogoSvg" -format "%w %h" info: 2>$null
  } else {
    # Fallback: render at default density, then resize to target width
    $logoDims = & magick -density $densityForRender -background none "$LogoSvg" -resize ("{0}x" -f $targetLogoW) -format "%w %h" info: 2>$null
  }

  if (-not $logoDims) { Write-Warning ("Could not compute logo dimensions for '{0}'" -f $LogoSvg); continue }
  $ld = $logoDims -split '\s+'
  if ($ld.Count -lt 2) { Write-Warning ("Unexpected logo dimension output: '{0}'" -f $logoDims); continue }
  [int]$logoW = $ld[0]; [int]$logoH = $ld[1]

  # 5) Margin (ignored for center)
  [int]$finalMarginPx = 0
  if ($useMargin) {
    if ($MarginPx -ge 0) {
      $finalMarginPx = $MarginPx
    } else {
      $finalMarginPx = [math]::Max([math]::Round($logoH * $MarginLogoHeightRatio), 1)
    }
  } else {
    $finalMarginPx = 0
  }

  # 6) Mirror subfolder structure in OutputFolder
  $outDir = $OutputFolder
  if ($Recurse) {
    $relSubDir = Get-RelativePath -BasePath $BackgroundFolder -TargetPath $file.DirectoryName
    if (-not [string]::IsNullOrEmpty($relSubDir)) {
      $outDir = Join-Path -Path $OutputFolder -ChildPath $relSubDir
    }
  }
  if (-not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }

  $outName = [IO.Path]::ChangeExtension($file.Name, $ext)
  $outPath = Join-Path -Path $outDir -ChildPath $outName

  # 7) Build ImageMagick args (use literal '(' and ')' in PowerShell)
  $cmd = @(
    "$bg",
    '(' , '-density', $densityForRender, '-background', 'none', "$LogoSvg"
  )
  if ($useResizeFallback) {
    $cmd += @('-resize', ("{0}x" -f $targetLogoW))
  }
  $cmd += @(')',
    '-gravity', $gravity
  )

  if ($useMargin) {
    $cmd += @('-geometry', ("+{0}+{0}" -f $finalMarginPx))
  } else {
    $cmd += @('-geometry', '+0+0')
  }

  $cmd += @('-compose', 'over', '-composite')

  if ($fmt -eq 'png') {
    # PNG: lossless, max compression, RGBA
    $cmd += @('-define', 'png:compression-level=9',
              '-define', 'png:color-type=6')
  } else {
    # JPEG: requested settings; ensure no alpha on export
    $cmd += @('-quality', '95',
              '-define', 'jpeg:optimize-coding=true',
              '-define', 'jpeg:dct-method=float',
              '-sampling-factor', '4:4:4',
              '-alpha', 'off')
  }

  $cmd += @("$outPath")

  # 8) Invoke ImageMagick
  & magick @cmd

  # Status text for the path used (PS5-safe)
  $pathKind = 'exact-density'
  if ($useResizeFallback) { $pathKind = 'fallback-resize' }

  if ($LASTEXITCODE -eq 0) {
    Write-Host ("Created {0}  (logo {1}x{2}, margin {3}px, pos {4}, fmt {5}, {6})" -f `
      $outPath, $logoW, $logoH, $finalMarginPx, $Position, $fmt.ToUpper(), $pathKind)
  } else {
    Write-Warning ("Failed to process '{0}'" -f $bg)
  }
}
