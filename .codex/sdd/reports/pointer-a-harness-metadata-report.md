# Pointer A-harness Metadata Matrix Report

Status: `READY_FOR_REVIEW`

## Scope

This bounded A-harness slice exercises the existing production metadata path
through the retained `DeterministicInteractionFixture` graph and
`DeterministicInteractionHarness.metadata()`. It does not modify production
metadata, palette, menu, router, shortcut, or display code.

Changed paths:

- `Tests/PointerAppKitTests/Harness/DeterministicInteractionFixture.swift`
- `Tests/PointerAppKitTests/Harness/ControlMetadataHarnessTests.swift`
- `.codex/sdd/reports/pointer-a-harness-metadata-report.md`

The fixture adds two named test states: `standard()` reuses the existing
1920-point display fixture, and `clamped()` supplies a stable 792-point
visible display so the real `PalettePanel.show(on:)` clamps to 760 points.

## Matrix covered

`ControlMetadataHarnessTests` uses the real `DisplayCoordinator`,
`OverlayPanel`, `CanvasView`, `CommandRouter`, `PalettePanel`,
`MenuBarController`, `HotKeyController`, and `ControlMetadataInventory` held
by the fixture. Its five tests cover:

1. A standard display: `palette.show(on:)` produces an 822-point palette with
   all eight direct tools, no overflow tool rows, complete unique metadata,
   slider/popup values, and expected enabled/focus reachability.
2. A clamped display: the palette is 760 points wide; Select, Arrow,
   Rectangle, Ellipse, and Pen remain direct controls while Eraser, Emoji, and
   Spotlight appear exactly once under the real More menu. The metadata order
   is explicitly contiguous: More, its disabled header, Eraser, Emoji, then
   Spotlight, with no intervening rows. Active Eraser selection is represented
   by the overflow metadata value.
3. A pending shortcut: the retained real hot-key controller routes the O
   candidate through `CommandRouter`, preserving P as Selected, exposing O as
   Pending, and publishing the shared five-second guidance on the shortcut
   parent.
4. A no-display sync: the real menu metadata reports the disabled annotation,
   Clear All, and Undo Clear All states plus the no-display warning while Show
   Palette, Learn Pointer, and Quit remain discoverable. Toggle mode, explicit
   annotation mode, and tool-selection commands are attempted through the real
   router and leave the session, selected tool, and empty canvas snapshots
   unchanged. Repeated metadata reads are equal.
5. Native key-view traversal at both widths: the actual palette key-view loop
   produces exactly the enabled, visible palette metadata order.

Every returned metadata row is required to have a unique identifier, a
nonempty accessible name, nonempty help, and a nonempty role. Expectations are
literal and independently derived; the tests do not use `PaletteLayoutPlan`
rows as rendered-row evidence.

## RED/GREEN evidence

The first focused invocation was intentionally red:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ControlMetadataHarnessTests
```

It failed at compile time because the new test-only `standard()` and
`clamped()` fixture helpers did not exist. After those helpers were added and
the test-only assertions were corrected, the focused matrix passed:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ControlMetadataHarnessTests
```

Result: `5 passed, 0 failed`.

Related metadata, palette, menu/router, shortcut, and harness coverage passed:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'ControlMetadataHarnessTests|AccessibilityMetadataTests|PaletteInteractionTests|CommandRouterTests|HotKeyControllerTests|ShortcutLifecycleTests|ShortcutSchedulingTests|CanvasIntegrationHarnessTests'
```

Result: `89 passed, 0 failed`.

## Evidence boundary

This is deterministic AppKit object and metadata evidence. It does not prove
physical hit-target geometry, real WindowServer ordering, live VoiceOver
navigation, or human discoverability. The metadata contract has no frame or
parent-topology fields, so overlap and physical stop/restart behavior remain
outside this slice. Those concerns stay with the visual/live integration and
lifecycle acceptance work.
