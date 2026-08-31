# Pointer D Task 3 Report — Raster Assets and Identity

Task 3 is implemented in the assigned scope only. No commit was created.

## Generation provenance

All four masters were generated with the built-in `image_gen` tool. CLI/API
fallback was not used. The tool recorded the outputs under the following
stable source paths:

- App icon: `/Users/bruno/.codex/generated_images/01a05655-f69f-7f43-8d1e-d6487b652e4b/exec-afa6eafe-6317-4f55-bfd4-ea92b29245ce.png` (1254×1254 RGBA PNG).
- Light guide sheet: `/Users/bruno/.codex/generated_images/01a05655-f69f-7f43-8d1e-d6487b652e4b/exec-eb69a9d4-c29e-4c75-bad8-6606e5c5cadf.png` (1774×887 RGB PNG).
- Dark guide sheet: `/Users/bruno/.codex/generated_images/01a05655-f69f-7f43-8d1e-d6487b652e4b/exec-076b53af-df9f-40e5-a81e-8cfb9d36d8c1.png` (1774×887 RGB PNG; light sheet used as the edit reference).
- High-contrast guide sheet: `/Users/bruno/.codex/generated_images/01a05655-f69f-7f43-8d1e-d6487b652e4b/exec-c315f5c0-a8ff-43cd-96bb-d6577af1b84f.png` (1774×887 RGB PNG; light sheet used as the edit reference).

The exact final prompts were:

### App icon

```text
Use case: logo-brand
Asset type: macOS application icon master for Pointer annotation app
Primary request: a distinctive minimal macOS app icon for Pointer: a deep graphite rounded-square tile with one bold coral-red annotation arrow/gesture and a restrained soft spotlight glow.
Scene/backdrop: single centered icon artwork, no surrounding scene.
Subject: one strong coral-red hand-drawn annotation arrow/gesture over a subtle graphite tile and small warm spotlight glow.
Style/medium: polished raster app icon, crisp simplified shapes, recognizable at 16 px, sophisticated macOS utility aesthetic.
Composition/framing: square 1:1 composition with generous safe margins; arrow is the unmistakable focal point, diagonally rising; rounded tile fills the canvas without touching the edges.
Lighting/mood: restrained spotlight glow, calm, focused, precise.
Color palette: deep graphite charcoal, near-black edges, coral-red arrow, tiny warm neutral highlight; high separation without neon.
Materials/textures: very subtle matte tile depth, clean edges, no grain that survives small sizes.
Text (verbatim): none.
Constraints: no text, letters, numbers, watermark, mock device, generic cursor screenshot, UI chrome, photo, hand, fingers, extra symbols, or copied brand mark; output must be a clean square raster master with a macOS-icon-safe background.
Avoid: thin fragile details, excessive gradients, clutter, multiple arrows, blue/purple neon, realistic computer screens.
```

### Light guide sheet

```text
Use case: scientific-educational
Asset type: 4×2 raster source sheet for Pointer first-use guide, eight equal visual examples
Primary request: create one coherent wide 4×2 contact sheet of eight compact tool demonstrations in exact left-to-right, top-to-bottom order: Arrow, Rectangle, Ellipse, Pen, Spotlight, Emoji, Select, Eraser. Every cell must show the tool's visual gesture and its representative annotation result, not only a symbol. This is the LIGHT variant.
Scene/backdrop: clean warm-white/light-gray guide board with eight clearly separated equal cells in a strict 4 columns by 2 rows grid, consistent spacing and margins.
Subject: row 1 shows an expressive coral annotation arrow pointing at a small detail, a coral rectangle framing a small detail, a coral ellipse circling a small detail, and a coral freehand pen stroke; row 2 shows a warm spotlight pool emphasizing a small detail, a cheerful simple emoji sticker annotation, a coral selection outline with visible handles around a mark, and a clean eraser action removing part of a mark.
Style/medium: polished flat-plus-soft-depth raster product illustration for a macOS utility onboarding guide; coherent across all cells, no photorealism.
Composition/framing: exactly eight equal square cells, icon and result centered inside each cell, generous padding, no labels or typography, same visual scale and stroke weight in every cell.
Lighting/mood: calm, focused, friendly, clear at small size.
Color palette: light background, deep graphite marks, coral-red annotations, restrained warm yellow spotlight, small amber emoji accent.
Materials/textures: clean crisp raster shapes with subtle soft shadows only where useful; no grain.
Text (verbatim): none.
Constraints: exact semantic order and 4×2 layout; no text, letters, numbers, labels, watermark, logo, mock device, cursor screenshot, or extra controls; preserve a clean wide sheet suitable for deterministic 512×512 crops.
Avoid: decorative clutter, overlapping cells, perspective distortion, random unrelated icons, blue/purple neon, tiny unreadable details.
```

### Dark guide sheet

```text
Use case: scientific-educational
Asset type: dark appearance variant of a Pointer first-use guide 4×2 raster source sheet
Input images: Image 1 is the composition reference; preserve its exact 4-column by 2-row grid, cell boundaries, tool order, object placement, gestures, and semantics.
Primary request: create the DARK variant of the referenced sheet. Keep every one of the same eight tool demonstrations in the exact same positions and scale: Arrow, Rectangle, Ellipse, Pen, Spotlight, Emoji, Select, Eraser. Change only the visual theme from light to dark.
Scene/backdrop: same clean guide board and eight equal cells, now deep graphite/charcoal with subtle separation between cells.
Subject: preserve the same coral-red arrow, rectangle, ellipse, pen stroke, warm spotlight, emoji sticker, selection handles, and eraser action; preserve all representative results.
Style/medium: polished flat-plus-soft-depth raster product illustration for a macOS utility onboarding guide, matching Image 1.
Composition/framing: exactly the same wide 4×2 layout and framing, no labels or typography, same stroke weights and centered padding.
Lighting/mood: calm, focused, friendly, with controlled highlights against dark surfaces.
Color palette: deep graphite and charcoal background, off-white and light-gray results, vivid coral-red annotations, restrained warm yellow spotlight and amber emoji.
Materials/textures: clean crisp raster shapes with subtle soft shadows; no grain.
Text (verbatim): none.
Constraints: preserve composition and semantics exactly; no text, letters, numbers, watermark, logo, mock device, cursor screenshot, extra controls, or rearrangement.
Avoid: changing cell order, adding objects, photorealism, blue/purple neon, busy gradients.
```

### High-contrast guide sheet

```text
Use case: scientific-educational
Asset type: high-contrast accessibility variant of a Pointer first-use guide 4×2 raster source sheet
Input images: Image 1 is the composition reference; preserve its exact 4-column by 2-row grid, cell boundaries, tool order, object placement, gestures, and semantics.
Primary request: create the HIGH-CONTRAST variant of the referenced sheet. Keep all eight tool demonstrations in the exact same positions and scale: Arrow, Rectangle, Ellipse, Pen, Spotlight, Emoji, Select, Eraser. Change only the visual treatment for maximum legibility.
Scene/backdrop: same clean guide board and eight equal cells, now near-black charcoal with strong clear cell separation.
Subject: preserve the same coral annotation arrow, rectangle, ellipse, pen stroke, spotlight, emoji sticker, selection handles, and eraser action; preserve all representative results.
Style/medium: polished flat raster product illustration for a macOS utility onboarding guide, matching Image 1.
Composition/framing: exactly the same wide 4×2 layout and framing, no labels or typography, same stroke weights and centered padding.
Lighting/mood: crisp, calm, focused, high legibility.
Color palette: near-black background, pure white/light-gray results, saturated coral-red annotation marks, vivid golden spotlight and emoji; very strong foreground/background contrast.
Materials/textures: simplified clean crisp raster shapes with minimal soft shadow and no low-contrast gradients.
Text (verbatim): none.
Constraints: preserve composition and semantics exactly; maximize contrast; no text, letters, numbers, watermark, logo, mock device, cursor screenshot, extra controls, or rearrangement.
Avoid: changing cell order, adding objects, subtle gray-on-gray details, blue/purple neon, busy gradients.
```

## Deterministic processing and mapping

- `sips` matched each generated master to `/System/Library/ColorSync/Profiles/sRGB Profile.icc` and normalized the guide sheets to 2048×1024. The icon was normalized directly to 512×512 sRGB RGBA.
- Each normalized guide sheet was cropped with `sips --cropToHeightWidth 512 512` and fixed top-left `--cropOffset` pairs `(row×512, column×512)`; explicit `0.0001` values select the origin cell without triggering sips' centered zero-offset default. The outputs match the sRGB profile without drawing or altering the generated content. The 24 final crops are all 512×512 RGB/sRGB PNGs with no alpha.
- The canonical icon is `Bundle/Assets.xcassets/AppIcon.appiconset/icon-512.png`, 512×512 RGBA/sRGB. Distinct deterministic icon renditions cover 16, 32, 64, 128, 256, 512, and 1024 physical pixels for the standard 16/32/128/256/512 logical 1×/2× slots; the Contents file does not reuse one filename for every slot.
- Guide source lookup follows the existing `GuideAssetSourceMapping`: `assetIdentifier-variant.png`. Each source is inside the matching `assetIdentifier-variant.imageset`, so the compiled resource name remains the mapped filename without `.png` (for example, `arrow-dark`).
- The catalog has exactly eight informative entries in this order: `arrow`, `rectangle`, `ellipse`, `pen`, `spotlight`, `emoji`, `select`, `eraser`. Each has exactly `light`, `dark`, and `highContrast` descriptors with `assetIdentifier` equal to its entry ID and the source hash below.

## Source inventory

### AppIcon sources

| Source | Dimensions | SHA-256 |
| --- | ---: | --- |
| `icon-16-1x.png` | 16×16 | `87aa3fc7bb5e394a90975c0a4399502444a305226857fcc5f91c6ece0ab00d4d` |
| `icon-16-2x.png` | 32×32 | `b85c459f5f7e742f098814ddac4a5493247be82a8682509197206234204eaa4f` |
| `icon-32-1x.png` | 32×32 | `b85c459f5f7e742f098814ddac4a5493247be82a8682509197206234204eaa4f` |
| `icon-32-2x.png` | 64×64 | `43dd62d465fd74ed2b1d1ff7cadc191fb8bee6f6d92571bfad3965536dbdbf95` |
| `icon-128-1x.png` | 128×128 | `e703d70211b8ab96c119222a4c94e94e3e5fe19613f158dab746d9c6cc69a86a` |
| `icon-128-2x.png` | 256×256 | `b3a0f15e4623007e27590a4dbced9a9e7076ad239cd06dac54d3e728d94a2d43` |
| `icon-256-1x.png` | 256×256 | `b3a0f15e4623007e27590a4dbced9a9e7076ad239cd06dac54d3e728d94a2d43` |
| `icon-256-2x.png` | 512×512 | `addf3ee7bdd2b047929ded43da54b7da70a61024a1399f6409b5997b3f61404e` |
| `icon-512.png` | 512×512 | `87eade9be043b792d052e7a1d6de0947290e58940a6568d25545c585da1e6690` |
| `icon-512-2x.png` | 1024×1024 | `6754319b244eb6f6a2972e8419d40ef1793ccabe07b658050bd8cf9c6fc8ef9a` |

`AppIconIdentity.json` records `name: AppIcon`, canonical dimensions 512×512,
`sRGB IEC 61966-2.1`, straight-alpha policy, marker coordinate `(256,256)`
with RGBA `[252,127,83,253]`, and canonical resolved-pixel digest
`dc9bb4ae78701a0d79004050eb062b836f1aa7623ad13c0b09b45d5a6dd59068`.

### Guide sources

| Entry | Light SHA-256 | Dark SHA-256 | High-contrast SHA-256 |
| --- | --- | --- | --- |
| `arrow` | `c7fb09d448c5a5d382dbaae1266090b0a9a480d888a152f49188d55e91179ecf` | `9907a214180c161eb204cf55c526e38991970f91caabd1420e50fba9b6ebbe0a` | `c95f1268bed95367818f69e1a7a0899c3a5151e759aaac8319ac9a80026cba8e` |
| `rectangle` | `7e65134ff7d54e955d9e30b34fdcced437e2ac46adc71a59302fee5867c2a76c` | `5447c95050285145669593ca6f704139593c4dd489f19fe92b4e0463ad089fc7` | `fd586ed7708e8a9d3f1cf1cdc435a1a336b56ac8102d700d598d3b0b1f8cbd72` |
| `ellipse` | `daf0f880ee6327b9e99e771e066bf4204300cfedbba4ba940f61df9de4d7ddc7` | `1a45ff088c731e6411fbd31690e90ac43a716dac75bf363d9bc483ab147f69ff` | `0d409fefc60c36f0821fb6dfebb50cff221c905de6d8ef05acf6fe0be92a9a8e` |
| `pen` | `cc60dd6cba402c7064fbf25c08385147191da53624d4fc7dcb1b6a69a844986c` | `3ac1b863149c7ce61f1d1652539eb17226c5abcc26bb652037391be3edcc2c9d` | `0c58f9bafb0a5029ae299da47a5064b28070c8067185d5c8b4beff2dd1208ddf` |
| `spotlight` | `79924c54b4d576df373907bb6ac29f2f45062b4c2b740ab4bb25857fa277b027` | `6e5084521c7e6eae19ccc24a5e08fcf0ccf05d5fed970dbbb98672532b6b7472` | `907b4bb84a298adce31b7287e1e0c15ed41e2f96a654c2d5adeb41277bc935ec` |
| `emoji` | `13d3fe5e897267bcffa4b64856e485bc36f4f93bda98e7607a4e92a544d5ff13` | `d5d401f84c0b49e83c15a06a6a05b615dfbaa9d2e6113745c1dbf7ea59bc1952` | `b6545b2cc1752437c29286e92aa991713df439a09e58d8fad8173e55af0ae8f7` |
| `select` | `636e6e0dbd9ccaccabc072928c49819e8180c2b71cdb9764a1c7941169995c2d` | `5f72aa907e96dec5c5831e238be46b904f7d0129ca3f1a18c56594d7a4ab64c7` | `c8afcfecd8a331b3107ef3474de3e6432696253eb8fb883636619b505509aa81` |
| `eraser` | `df2c1c8357d286a7d2de5f620d75545bcc2fe05ae0303b8405375eff2f8270af` | `2f538cd69e940b5b004424d635057f4d4c0e92db9da48a321119b4202350500e` | `23b0e43117d8dabb248c3cba58313c1ce89099e3c2a5a089268a8522bbb822f1` |

All guide sources are 512×512, RGB/sRGB, and are tracked only under
`Bundle/Assets.xcassets/FirstUseGuide/<entry>-<variant>.imageset/`.

## Visual inspection

- App icon master: distinctive deep graphite rounded tile, one bold coral-red
  diagonal annotation arrow/gesture, and a restrained warm glow; no text,
  letters, watermark, device, cursor screenshot, or extra symbols. The
  normalized 512×512 result remains recognizable when viewed at icon scale.
- Light guide master: exact 4×2 order and coherent cell framing; each cell
  includes a representative result (not only a symbol), with no text or
  watermark.
- Dark guide master: same 4×2 geometry, gestures, and semantics with charcoal
  surfaces and light results for readable dark appearance.
- High-contrast guide master: same 4×2 geometry and semantics with near-black
  surfaces, bright foreground results, coral strokes, and stronger yellow
  spotlight/emoji contrast.
- Representative crops inspected after deterministic processing: light arrow,
  dark spotlight, and high-contrast eraser. Each retained its complete cell,
  equal 512×512 frame, and intended gesture/result.

## Verification

Post-correction verification was run after the sips-only recrop:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AssetIdentityTests
GREEN: 3 tests, 0 failures.

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
GREEN: 298 tests, 0 failures.

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build
GREEN: Build complete (exit 0).

git diff --check
GREEN: no whitespace errors (exit 0).

All 24 guide PNGs: 512×512 PNG, sRGB IEC61966-2.1, alpha=no.
```

An additional temporary catalog sanity check compiled the tracked asset
catalog with the Xcode toolchain, and `assetutil --info` parsed its
`Assets.car` successfully:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun actool \
  --compile <mktemp-directory> \
  --platform macosx --minimum-deployment-target 14.0 \
  --app-icon AppIcon \
  --output-partial-info-plist <mktemp-directory>/partial.plist \
  Bundle/Assets.xcassets
exit 0
```

`assetutil --info` for that temporary `Assets.car` reported ten AppIcon
renditions (16, 32, 32, 64, 128, 256, 256, 512, 512, 1024 pixels) and all
24 guide resources at 512×512 sRGB. The partial plist contained
`CFBundleIconName = AppIcon`.

## Deferred F-owned proof

This task did not modify `Info.plist`, build scripts, `Package.swift`, or any
F-owned files. The temporary actool check above is not Release bundle proof.
F still owns the authoritative Release build and must prove, from the real
`build/Pointer.app`, that `Assets.car` is present, `CFBundleIconName` is exact,
Launch Services resolves the exact bundle, the injected catalog resolves every
compiled guide resource, the resolved icon marker/digest matches the manifest,
and the second Release build is idempotent. `AppIconIdentity.json`'s digest is
the canonical source-pixel digest; it has not been claimed as completed
Launch Services/Assets.car evidence.
