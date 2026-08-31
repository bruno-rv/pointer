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
`narrow()` reuses the canonical `DisplayFixtures.narrowDisplay()` 420-point
visible display.

## Matrix covered

`ControlMetadataHarnessTests` uses the real `DisplayCoordinator`,
`OverlayPanel`, `CanvasView`, `CommandRouter`, `PalettePanel`,
`MenuBarController`, `HotKeyController`, and `ControlMetadataInventory` held
by the fixture. Its six tests cover:

1. A standard display: `palette.show(on:)` produces an 822-point palette with
   all eight direct tools, no overflow tool rows, complete unique metadata,
   slider/popup values, and expected enabled/focus reachability. The real More
   control is hidden and not keyboard reachable at this width.
2. A clamped display: the palette is 760 points wide; Select, Arrow,
   Rectangle, Ellipse, and Pen remain direct controls while Eraser, Emoji, and
   Spotlight appear exactly once under the real More menu. The metadata order
   is explicitly contiguous: More, its disabled header, Eraser, Emoji, then
   Spotlight, with no intervening rows. The More control is visible, enabled,
   and keyboard reachable. Its header has the exact accessible name, help,
   value, `AXMenuItem` role, and disabled/nonreachable state. Active Eraser
   selection is represented by the overflow metadata value.
3. The canonical narrow display fixture: synchronization creates a real
   overlay and `PalettePanel.show(on:)` returns `.shown` for the 420-point
   visible frame. After C's narrow containment fix at `4db806f`, the content
   and frame width is exactly 388 points after the 32 points of placement
   margins, with Select as the only direct tool; Arrow, Rectangle, Ellipse,
   Pen, Eraser, Emoji, and Spotlight appear exactly once under More. More
   remains visible/enabled/reachable; all style controls retain metadata
   values/help and the horizontal style scroller is present. A literal native
   focus sequence through More is verified with wrap-around.
   These are metadata/layout assertions only; they do not claim physical
   no-clipping or no-overlap proof.
4. A pending shortcut: the retained real hot-key controller routes the O
   candidate through `CommandRouter`, preserving P as Selected, exposing O as
   Pending, and publishing the shared five-second guidance on the shortcut
   parent, palette status, and menu-bar status values and help. Both candidates
   and their parent remain enabled/reachable and action-capable through the
   native menu hierarchy.
5. A no-display sync: the real menu metadata reports the disabled annotation,
   Clear All, and Undo Clear All states plus the no-display warning while Show
   Palette, Learn Pointer, and Quit remain discoverable. Toggle mode, explicit
   annotation mode, and tool-selection commands are attempted through the real
   router and leave the session, selected tool, and empty canvas snapshots
   unchanged. Repeated metadata reads are equal.
6. Native key-view traversal at both widths: the actual palette key-view loop
   produces a literal expected identifier sequence and wraps back to Mode.

Every returned metadata row is required to have a unique identifier, a
nonempty accessible name, nonempty help, and a nonempty role. Expectations are
literal and independently derived; the tests do not use `PaletteLayoutPlan`
rows as rendered-row evidence.

The palette's explicit AppKit role descriptions are asserted for buttons,
popups, color well, sliders, status, menu-bar item, and the Shortcut group;
metadata rows for those controls, menu items, and the overflow header must
expose their exact native roles and reject `AXUnknown`. The earlier custom
control-role mapping finding was fixed and independently approved in C at
`cb791f8`; the A matrix now verifies the corrected metadata end to end.

## RED/GREEN evidence

The first focused invocation was intentionally red:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ControlMetadataHarnessTests
```

It failed at compile time because the new test-only `standard()` and
`clamped()` fixture helpers did not exist. After those helpers were added and
the test-only assertions were corrected, the original pre-narrow matrix passed:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ControlMetadataHarnessTests
```

The final focused run includes the canonical narrow case. An earlier run
captured a real production mismatch: `PalettePanel.show(on:)` returned
`.shown`, but AppKit expanded the narrow frame to 487 points instead of the
requested 388. C fixed that containment issue at `4db806f` and independently
reconciled it; the current focused run is green:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ControlMetadataHarnessTests
```

Result: `6 passed, 0 failed`, including the exact 388-point narrow
content/frame assertion and all subsequent overflow/More traversal checks.

Related metadata, palette, menu/router, shortcut, and harness coverage passed
before the canonical narrow case was added:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'ControlMetadataHarnessTests|AccessibilityMetadataTests|PaletteInteractionTests|CommandRouterTests|HotKeyControllerTests|ShortcutLifecycleTests|ShortcutSchedulingTests|CanvasIntegrationHarnessTests'
```

Result: `89 passed, 0 failed`.

After C's native role fix at `cb791f8` and narrow containment fix at
`4db806f`, the related command was rerun:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'ControlMetadataHarnessTests|AccessibilityMetadataTests|PaletteInteractionTests|CommandRouterTests|HotKeyControllerTests|ShortcutLifecycleTests|ShortcutSchedulingTests|CanvasIntegrationHarnessTests'
```

Result: `93 passed, 0 failed`.

The full package gate was also rerun:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Result: `340 passed, 0 failed`.

The debug build, `git diff --check`, and a whitespace scan of the changed test
and report files also passed. No C files were modified by this slice. The
earlier 487-point mismatch is historical evidence superseded by the
`4db806f` containment fix; the final post-fix counts above are current.

## Evidence boundary

This is deterministic AppKit object and metadata evidence. It does not prove
physical hit-target geometry, real WindowServer ordering, live VoiceOver
navigation, or human discoverability. The metadata contract has no frame or
parent-topology fields, so overlap and physical stop/restart behavior remain
outside this slice. Those concerns stay with the visual/live integration and
lifecycle acceptance work.
