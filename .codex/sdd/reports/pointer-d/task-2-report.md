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

## Remaining concerns

- Task 3 has not yet supplied the tracked AppIcon/FirstUseGuide raster assets,
  identity manifests, or compiled `Assets.car` proof. The concrete catalog is
  ready for those injected bundle resources but asset resolution cannot be
  claimed until Task 3/F validation runs.
- F's final composition root/build wiring is still outstanding; the temporary
  launcher guide bootstrap remains in place. Live VoiceOver, physical
  multi-display placement, and final manual composition evidence remain F
  responsibilities.
