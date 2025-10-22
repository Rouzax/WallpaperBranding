# 🖼️ WallpaperBranding

**WallpaperBranding** is a PowerShell tool that brands wallpapers by compositing an **SVG logo** onto PNG images.  
Logos are **sized as a percentage of the wallpaper**, positioned in any corner or centered, and exported as **PNG** (lossless, max compression) or **JPEG** (tuned quality).  
It uses **ImageMagick** for crisp, vector-accurate rasterization and works on **Windows PowerShell 5.x** and **PowerShell 7+**.

---

## ✨ Features

- 🎯 **Vector-accurate sizing (no bitmap resample):** the SVG is rendered directly at the target pixel size for sharp edges.
- 🧭 **Flexible placement:** `TopLeft`, `TopRight`, `BottomRight`, `BottomLeft`, or `Center` (margin ignored in center).
- 📐 **Consistent scaling:** size logo by % of **width**, **height**, or the **shorter** side of the wallpaper.
- ↔️ **Smart margins:** use a fixed pixel margin or automatically compute it from the **final logo height**.
- 🗂️ **Nested folders:** optional `-Recurse` mirrors your input folder structure in the output.
- 🧰 **ImageMagick under the hood:** accurate vector-to-raster and compositing.
- 💾 **Output formats:**
  - **PNG**: lossless with `png:compression-level=9` (max), alpha preserved.
  - **JPEG**: `-quality 95`, `jpeg:optimize-coding=true`, `jpeg:dct-method=float`, `sampling-factor 4:4:4`.

---

## 🧩 Requirements

- **PowerShell 5.1 or newer**
- **[ImageMagick](https://imagemagick.org/script/download.php)** installed and available in `PATH` (`magick` command)

Verify:
```powershell
magick -version
````

---

## 📦 Installation

```powershell
git clone https://github.com/Rouzax/WallpaperBranding.git
cd WallpaperBranding
```

---

## 🚀 Usage

Basic example (PNG output, top-right, auto margin):

```powershell
.\Add-Logo.ps1 `
  -BackgroundFolder "C:\Wallpapers\In" `
  -LogoSvg "C:\Brand\logo.svg" `
  -OutputFolder "C:\Wallpapers\Out" `
  -PercentOfSize 0.15 `
  -BaseDimension shorter `
  -Position TopRight
```

Recurse subfolders and mirror structure:

```powershell
.\Add-Logo.ps1 `
  -BackgroundFolder "C:\Wallpapers" `
  -LogoSvg "C:\Brand\logo.svg" `
  -OutputFolder "C:\Out" `
  -PercentOfSize 0.10 `
  -BaseDimension width `
  -Position TopRight `
  -Recurse
```

Bottom-left with **fixed** 72px margin:

```powershell
.\Add-Logo.ps1 `
  -BackgroundFolder "C:\Wallpapers\In" `
  -LogoSvg "C:\Logos\Company.svg" `
  -OutputFolder "C:\Wallpapers\Out" `
  -PercentOfSize 0.12 `
  -BaseDimension shorter `
  -Position BottomLeft `
  -MarginPx 72
```

Centered logo (margin ignored):

```powershell
.\Add-Logo.ps1 `
  -BackgroundFolder "C:\Wallpapers\In" `
  -LogoSvg "C:\Logos\Logo.svg" `
  -OutputFolder "C:\Wallpapers\Out" `
  -PercentOfSize 0.2 `
  -BaseDimension shorter `
  -Position Center
```

Export as **JPEG** with tuned settings:

```powershell
.\Add-Logo.ps1 `
  -BackgroundFolder "C:\Wallpapers\In" `
  -LogoSvg "C:\Brand\logo.svg" `
  -OutputFolder "C:\Wallpapers\OutJpg" `
  -PercentOfSize 0.12 `
  -BaseDimension width `
  -Position TopRight `
  -OutputFormat jpg
```

---

## ⚙️ Parameters

| Parameter                 | Type                                                         | Default      | Description                                                                   |
| ------------------------- | ------------------------------------------------------------ | ------------ | ----------------------------------------------------------------------------- |
| **BackgroundFolder**      | `string`                                                     | *(required)* | Root folder containing **PNG** wallpapers.                                    |
| **LogoSvg**               | `string`                                                     | *(required)* | Path to the **SVG** logo.                                                     |
| **OutputFolder**          | `string`                                                     | *(required)* | Destination root. Created if missing; mirrors subfolders when `-Recurse`.     |
| **PercentOfSize**         | `double (0.001–1.0)`                                         | `0.12`       | Fraction used to compute target logo **width** from `BaseDimension`.          |
| **BaseDimension**         | `width \| height \| shorter`                                 | `width`      | Which background dimension to base the logo width on.                         |
| **Position**              | `TopLeft \| TopRight \| BottomRight \| BottomLeft \| Center` | `TopRight`   | Logo placement. Center ignores margin.                                        |
| **MarginPx**              | `int`                                                        | `-1`         | Fixed pixel margin (both X/Y). If `< 0`, margin is computed from logo height. |
| **MarginLogoHeightRatio** | `double (0.0–2.0)`                                           | `0.25`       | When `MarginPx < 0`, margin = `logo_height × ratio`.                          |
| **SvgDensity**            | `int (72–1200)`                                              | `300`        | **Fallback** density if SVG probe fails (legacy resize path).                 |
| **OutputFormat**          | `png \| jpg \| jpeg`                                         | `png`        | Output format. PNG uses max compression; JPEG uses tuned quality/defines.     |
| **Recurse**               | `switch`                                                     | *(off)*      | Process nested folders and mirror structure under `OutputFolder`.             |

---

## 🧮 How sizing & margins work

* **Vector-accurate sizing:** the script probes the SVG at **72 DPI** to get a baseline width, then computes an **exact render density** so the SVG rasterizes **directly** to the target pixel width (no post-raster `-resize`).
* **Auto margin (corner positions):**

  ```
  margin = final_logo_height × MarginLogoHeightRatio
  ```

  Example: If final logo height is 200px and `MarginLogoHeightRatio = 0.25`, the margin is **50px**.
* **Fixed margin:** set `-MarginPx` to a non-negative integer to override the auto calculation.
* **Center:** margin is **ignored**; the logo is placed exactly in the image center.

---

## 🧱 Implementation Notes

* SVG is composited with `-background none` to preserve transparency during rasterization.
* **PNG** uses `-define png:compression-level=9` and `-define png:color-type=6` (RGBA).
* **JPEG** uses `-quality 95`, `-define jpeg:optimize-coding=true`, `-define jpeg:dct-method=float`, and `-sampling-factor 4:4:4`. Alpha is disabled for JPEG.
* The script avoids temporary files and is safe for batch runs.
* Tested on:

  * Windows 10 / 11
  * PowerShell 5.1 and 7.4
  * ImageMagick 7.1.1+