# Pointer D Task 2 Report — First-Use Guide

Status: `DONE_WITH_CONCERNS`

Worktree: `/Users/bruno/Dev/pointer/.worktrees/stable-app`

No commit created. Task 1 changes already present in this shared worktree were
left untouched.

## TDD evidence

### RED

1. Command:

   ```text
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter FirstUseGuideTests
   ```

   Result: exit `1`. The test target failed to compile because the D seams
   were absent: `GuideAssetCatalogProviding`, `GuideAssetDescriptor`,
   `GuideAssetVariant`, `FirstUseGuidePanel`, and `FirstUseGuideController`.

2. After adding the injected metadata accessibility test, command:

   ```text
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter FirstUseGuideTests/testGuideExamplesExposeInjectedAccessibleMetadataAndFocusOrder
   ```

   Result: exit `1`. The test correctly failed because the view used the
   hard-coded `Arrow example` metadata instead of the injected `Attention
   arrow` name/description.

### GREEN

1. Focused guide suite:

   ```text
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter FirstUseGuideTests
   ```

   Result: exit `0`; `FirstUseGuideTests`: `10 passed, 0 failed`.

2. Full Swift test suite:

   ```text
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
   ```

   Result: exit `0`; `276 passed, 0 failed` across the package, including the
   existing C guide-integration suite and Task 1 render tests.

3. Build:

   ```text
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build
   ```

   Result: exit `0`; debug build completed successfully.

4. Diff validation:

   ```text
   git diff --check
   ```

   Result: exit `0`; no whitespace errors.

## Changed paths

- `Sources/PointerAppKit/Help/UserDefaultsFirstUseGuideStateStore.swift`
- `Sources/PointerAppKit/Help/FirstUseGuideController.swift`
- `Sources/PointerAppKit/Help/FirstUseGuideViewController.swift`
- `Sources/PointerAppKit/Help/GuideAssetCatalog.swift`
- `Tests/PointerAppKitTests/FirstUseGuideTests.swift`
- `Tests/PointerAppKitTests/FirstUseGuideTestFixtures.swift`

`Sources/PointerAppKit/Help/FirstUseGuideStateStoring.swift` and
`FirstUseGuidePresenting.swift` were consumed unchanged. No C controller,
composition root, launcher, rendering, asset, package, or build files were
edited.

## Contract and handoff

- `UserDefaultsFirstUseGuideStateStore` accepts an explicit `UserDefaults`
  instance and key; it never selects `UserDefaults.standard` itself.
- `GuideAssetVariant`, descriptor structs, envelope, injected catalog
  protocol, concrete catalog, and deterministic source mapping are public.
  The envelope contract uses schema version `1` and catalog identifier
  `pointer.first-use-guide.v1`; source files map as
  `FirstUseGuide/<assetIdentifier>-<variant>.png`.
- `FirstUseGuideController` exposes only concrete `assetCatalog` and the
  injected `placementProvider`; it does not alter C's presenting protocol.
  Every guide example is resolved through the injected catalog before panel
  presentation. `.shown` is returned only after the panel callback observes
  visibility; failed/hidden panels remain retryable and never mark the store.
- Display-loss hide records retry intent without changing seen state;
  reconnect restores once, while application-stop clears transient restore
  intent without committing seen state. Dismiss/Escape only closes the guide.
- `FirstUseGuideViewController` builds a non-modal guide with eight examples,
  injected catalog metadata, accessible labels/help, and focus order from title
  through explanation, examples, shortcuts, and Done. Decorative catalog
  entries are excluded from the accessibility element tree.
- `FirstUseGuideAssetPreparing` is an internal-only panel seam used by the
  retained-panel regression; it forwards complete resolved image maps into the
  existing guide view without changing the public presenting protocol.

## Remaining concerns

- Task 3 has not yet supplied the tracked AppIcon/FirstUseGuide raster assets,
  identity manifests, or compiled `Assets.car` proof. The concrete catalog now
  derives each compiled resource name from `GuideAssetSourceMapping` and uses
  the injected bundle's compiled-image lookup; runtime asset resolution still
  requires Task 3/F's compiled bundle proof.
- F's final composition root/build wiring is still outstanding; the temporary
  launcher guide bootstrap remains in place. Live VoiceOver, physical
  multi-display placement, and final manual composition evidence remain F
  responsibilities.

## Fix round 1 evidence

Reviewer findings were converted into RED tests before implementation:

1. Regression batch command:

   ```text
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter FirstUseGuideTests
   ```

   Result: exit `1` with the expected missing D APIs (`GuideAppearanceProviding`,
   `FirstUseGuidePlacementPlan`, strict catalog error cases, scroll/AX
   metadata), plus dependent test compile diagnostics.

2. After adding the invalid-frame assertion, command:

   ```text
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter FirstUseGuideTests/testPlacementPlanReturnsNilWhenNoLegalFrameFitsAndControllerKeepsPanelHidden
   ```

   Result: exit `1`; the pure plan incorrectly returned a frame for an invalid
   palette frame, proving the missing validation before the guard was added.

The fixes then passed:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter FirstUseGuideTests
exit 0
FirstUseGuideTests: 17 passed, 0 failed

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
exit 0
PointerPackageTests.xctest: 285 passed, 0 failed

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build
exit 0
Build complete

git diff --check
exit 0
No whitespace errors
```

The concrete catalog initializer now throws `GuideAssetCatalogError` for
schema/identifier mismatch, duplicate IDs or variants, missing variants,
invalid hashes/asset identifiers, and invalid required metadata. This is a
deliberate refinement of the earlier nonthrowing interface outline; the
coordinator must carry `try GuideAssetCatalog(envelope:bundle:)` into the
future F composition call site. The authoritative D plan was updated in this
scoped fix round; no package or composition file was edited.

The implementation also extracts `FirstUseGuidePlacementPlan.frame(size:in:)`
as a pure legal-frame planner, injects `GuideAppearanceProviding`, reloads
light/dark/high-contrast images safely while visible, rejects metadata
fallbacks, uses a scrollable compact guide, and passes the one-time preflight
image map into the real panel to avoid duplicate initial decoding.

## Coordinator follow-up evidence

The remaining pre-review findings were written as RED tests before their
production fixes:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter FirstUseGuideTests
exit 1
Missing start/stop appearance observation, semantic appearance refresh,
title/explanation narrow-layout accessors, and single-route catalog contract.

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter FirstUseGuideTests/testPlacementPlanReturnsNilWhenNoLegalFrameFitsAndControllerKeepsPanelHidden
exit 1
The pure planner returned a frame for an invalid palette frame.

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter FirstUseGuideTests
exit 1
After production APIs compiled, the semantic Aqua/Dark Aqua background test
and catalog fallback source-contract assertion failed as expected.
```

The corrected follow-up passed:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter FirstUseGuideTests
exit 0
FirstUseGuideTests: 20 passed, 0 failed

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
exit 0
PointerPackageTests.xctest: 288 passed, 0 failed

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build
exit 0
Build complete

git diff --check
exit 0
No whitespace errors
```

The concrete panel now observes
`NSWorkspace.shared.notificationCenter` only while visible, while effective
appearance is handled by the guide root view. Semantic background colors are
resolved under `performAsCurrentDrawingAppearance` without changing frame,
focus, or accessibility order. The stale view `variant` property was removed;
the injected appearance provider is the sole variant source. The guide uses a
120–390 point adaptive scroll constraint and remains inside tested 320/360
point view heights. Catalog loading uses one explicit injected-bundle compiled
image route derived from `GuideAssetSourceMapping`; alternate URL/image loading
and fallback lookup routes are prohibited. Task 3/F still owns the compiled bundle
and `Assets.car` proof.

The authoritative D plan was updated to document the throwing catalog
initializer, `GuideAppearanceProviding`, optional no-overlap placement, strict
catalog validation, and adaptive variant-aware scroll/appearance behavior.

## Coordinator follow-up round

Additional RED checks covered the workspace notification center, semantic
appearance resolution, stale variant state, narrow-height layout, and
single-route catalog loading:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter FirstUseGuideTests
exit 1
Missing appearance observation/semantic refresh/layout accessors and the
single-route catalog source contract.

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter FirstUseGuideTests/testEffectiveAppearanceUpdatesSemanticBackgroundWithoutMovingFrameOrFocus
exit 1
The first test snapshot used the host's already-Dark default appearance;
the test was corrected to establish Aqua before switching to Dark Aqua.
```

The corrected implementation and test suite passed:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter FirstUseGuideTests
exit 0
FirstUseGuideTests: 20 passed, 0 failed

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
exit 0
PointerPackageTests.xctest: 288 passed, 0 failed

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build
exit 0
Build complete

git diff --check
exit 0
No whitespace errors
```

The guide now observes `NSWorkspace.shared.notificationCenter` only while
visible, resolves semantic Aqua/Dark Aqua background colors under
`performAsCurrentDrawingAppearance`, uses `GuideAppearanceProviding` as its
sole variant source, and keeps all narrow-height content inside tested
320/360-point frames via an adaptive scroll viewport. The catalog has one
explicit injected-bundle compiled-image lookup route: it removes `.png` from
the `GuideAssetSourceMapping` path and passes the resulting resource name to
`bundle.image(forResource:)`. The source-contract test rejects URL/path loads,
`NSImage(contentsOf:)`, `Bundle.main`, global `NSImage(named:)`, and duplicate
compiled lookup routes.

## Final compiled-asset verification

The catalog resolves every guide image through the injected Bundle's compiled
resource lookup. It deterministically derives each resource name from
`GuideAssetSourceMapping.sourcePath(...).dropLast(".png".count)`, and the
source-contract test requires exactly one `bundle.image(forResource:)` call
while rejecting global/default named lookup and alternate resource routes.

Final verification after Task 1's test fixes and retained-panel reload fix:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build
exit 0
Build complete

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter FirstUseGuideTests
exit 0
FirstUseGuideTests: 21 passed, 0 failed

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
exit 0
PointerPackageTests.xctest: 292 passed, 0 failed

git diff --check
exit 0
No whitespace errors
```

The focused guide suite and full package suite both pass after Task 1's test
fixes and the retained-panel reload correction. This follow-up did not modify
`RenderPlanTests.swift` or any other Task 1 path.

## Retained-panel appearance regression

The RED test loaded the guide through the controller with light images, kept
the same panel/view instance after dismissal, switched the injected appearance
provider to dark, and re-presented it. Before the production fix, all eight
image identity assertions failed because `setResolvedImages` updated only its
caches; frame and focus remained unchanged.

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter FirstUseGuideTests/testReshowRetainedLoadedPanelAppliesDarkImagesWithoutMovingFrameOrFocus
exit 1
Executed 1 test, with 16 failures (0 unexpected)
All eight retained image views stayed on their light instances.
```

The GREEN fix validates a complete example-keyed map before updating caches or
loaded image views, applies all injected images to the retained view, and
clears resolution errors only after the complete update succeeds.

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter FirstUseGuideTests/testReshowRetainedLoadedPanelAppliesDarkImagesWithoutMovingFrameOrFocus
exit 0
Executed 1 test, with 0 failures (0 unexpected)

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter FirstUseGuideTests
exit 0
FirstUseGuideTests: 21 passed, 0 failed

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
exit 0
PointerPackageTests.xctest: 292 passed, 0 failed
```
