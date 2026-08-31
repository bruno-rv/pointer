# Pointer D Task 3 Brief — Raster Assets and Identity

Implement only Task 3 of `.codex/sdd/features/2026-08-23-pointer-d-visual-language-plan.md`.

## Creative contract

- Use the installed `imagegen` skill and built-in image-generation tool. These must be genuinely generated raster assets, not SVG or code-drawn substitutes.
- App icon: a distinctive macOS icon for Pointer—a deep graphite rounded tile with one bold coral-red annotation arrow/gesture and a restrained spotlight glow; crisp, minimal, recognizable at 16 px; no text, letters, watermark, mock device, or generic cursor screenshot.
- Guide examples: generate three coherent 4×2 raster source sheets (light, dark, high-contrast), then deterministically crop eight equal tool examples in this exact order: Arrow, Rectangle, Ellipse, Pen, Spotlight, Emoji, Select, Eraser. Each cell shows the tool and its representative result, not just a symbol. No text or watermark. Variants keep identical composition and semantics while adapting contrast/background.
- Use deterministic image processing only for crop, color-profile/alpha normalization, and icon downscaling. Preserve the generated visual content.

## Repository scope

- Create `Bundle/Assets.xcassets/AppIcon.appiconset/**`.
- Create `Bundle/Assets.xcassets/FirstUseGuide/*.imageset/**`.
- Create `Bundle/AppIconIdentity.json` and `Bundle/GuideAssetIdentity.json`.
- Create `Tests/PointerAppKitTests/AssetIdentityTests.swift`.
- Create `.codex/sdd/reports/pointer-d/task-3-report.md` including final prompts, built-in tool provenance, generated masters/crops, dimensions, SHA-256 values, and visual inspection notes.
- Do not edit Task 1/2 production, C/F composition, Package.swift, Info.plist, or build scripts.

## Contract and verification

- `GuideAssetIdentity.json` exactly encodes schemaVersion `1`, catalogIdentifier `pointer.first-use-guide.v1`, and the eight informative entries with light/dark/highContrast variants. Every source hash matches bytes; source mapping and compiled resource names match `GuideAssetSourceMapping`.
- `AppIconIdentity.json` contains the exact AppIcon name, every source PNG hash/dimension, sRGB/straight-alpha policy, marker pixel coordinate/RGBA, and canonical resolved digest required by the D plan.
- Asset tests reject missing/extra/unused PNGs, missing variants, SVG/network references, invalid hashes, wrong dimensions/color space/alpha, inaccessible metadata, and catalog bypass.
- Inspect generated masters and representative crops visually before accepting. Use strict RED/GREEN TDD, then focused asset/guide tests, full `swift test`, `swift build`, and `git diff --check`. F remains responsible for actool/Assets.car/CFBundleIconName proof.
- Do not commit.
