# Pointer D Task 4 Report — Persistent Chrome and Common Path

Status: `DONE_WITH_CONCERNS`

## Scope and identities

This task changed only the D-owned test/report paths below. No production
source, C-owned palette/menu/controller source, or Task 3 asset was edited.

- Baseline: `caa2bd0212c617ba6d4d599ede55be3624e525f4` (`fix: preserve Pointer
  gesture boundary delivery`), the accepted B-core commit immediately before C
  product-surface work.
- Candidate evidence: source state `f28ffac` (`test: exercise Pointer common
  path`), the authoritative D candidate state for this inventory. The counts
  below are intentionally described against this source state rather than
  against a future coordinator integration commit.
- Worktree: `/Users/bruno/Dev/pointer/.worktrees/stable-app`, branch
  `codex/stable-app`.
- Evidence test: `Tests/PointerAppKitTests/ChromeFrictionTests.swift`.
- Evidence report: `.codex/sdd/reports/pointer-d/task-4-report.md`.

The inventory repair is limited to the test/report pair named above. The
candidate asset work and its report remain outside this task's scope.

The immutable baseline source fingerprints, computed from Git objects, are:

| Baseline source | SHA-256 of `git show <baseline>:<path>` |
| --- | --- |
| `Sources/PointerAppKit/Palette/PalettePanel.swift` | `94d350cbc58e3f9e909c87a4888253b89ba078b4909c738f1819c4984d8b1163` |
| `Sources/PointerAppKit/Palette/PaletteViewController.swift` | `faaf563522dfe4c4b658bc4efdb1001d79b240c478a8e8c113c9734171e27c52` |
| `Sources/PointerAppKit/Palette/PaletteLayout.swift` | `06d061e3b54e150ded44efb082c3a6f3e1faa43d77430f1f68d8092200bb20c0` |

They were computed with:

```text
git show caa2bd0212c617ba6d4d599ede55be3624e525f4:Sources/PointerAppKit/Palette/PalettePanel.swift | shasum -a 256
git show caa2bd0212c617ba6d4d599ede55be3624e525f4:Sources/PointerAppKit/Palette/PaletteViewController.swift | shasum -a 256
git show caa2bd0212c617ba6d4d599ede55be3624e525f4:Sources/PointerAppKit/Palette/PaletteLayout.swift | shasum -a 256
```

## Strict RED/GREEN evidence

The first test-only RED run for the repaired inventory was:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ChromeFrictionTests
```

It failed at compilation because the new baseline/evidence types and
panel-backed candidate helper were not yet defined. No production code was
present behind the test. Adding those test-only measurement helpers produced
the first runtime RED when AppKit exposed its internal `Standby` button-title
text field outside the intended taxonomy; filtering button-title descendants
and asserting the remaining text fields as a complete 1 + 4 + 6 classification
produced GREEN:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ChromeFrictionTests
GREEN: 2 tests, 0 failures.
```

The reviewer P1 correction was then written test-first. The focused RED run
failed to compile because the existing test overlay had no `canvasView`, and
the new non-void geometry failure branch was not yet throwable. Adding only a
test-owned `CanvasView` overlay with `DisplayCoordinator` callback wiring and
the explicit test error produced GREEN:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ChromeFrictionTests/testFreshLaunchArrowDrawStandbyPathNeedsNoAdditionalClickOrKey
GREEN: 1 test, 0 failures.
```

## Inventory method and exact counts

The candidate is measured through a real `PalettePanel.show(on:)` for two
display descriptors, then through its `paletteViewController` after AppKit
layout. The standard case models a 1920 x 1080 display and yields the panel's
822-point preferred width. The clamped case models a display with a 792-point
visible width and yields a 760-point panel (`792 - 2 x 16` placement margin).

| Scenario | Metric | Baseline `caa2bd0212c617ba6d4d599ede55be3624e525f4` | Candidate evidence at `f28ffac` | Change |
| --- | --- | ---: | ---: | ---: |
| Standard, 1920 x 1080 -> 822 pt | Panel content width | 760* | 822 | +62 |
| Standard | Always-visible palette controls | 17 | 17 | 0 |
| Standard | Rendered tool rows | 1 | 1 | 0 |
| Standard | Visible semantic status elements | 1 | 1 | 0 |
| Standard | Enabled keyboard focus stops | 17 | 12 | -5 |
| Clamped, 792 pt visible -> 760 pt | Panel content width | 760 | 760 | 0 |
| Clamped | Always-visible palette controls | 17 | 15 | -2 |
| Clamped | Rendered tool rows | 1 | 1 | 0 |
| Clamped | Visible semantic status elements | 1 | 1 | 0 |
| Clamped | Enabled keyboard focus stops | 17 | 10 | -7 |

\* The baseline `PalettePanel.preferredSize` was 760 points even on a wide
display; 822 is the candidate's measured preferred width. Width is reported
for honesty but is not one of the persistent non-increase dimensions below.

Baseline control counts come from the immutable source object above: one mode
control, eight direct tools, one overflow control, six style controls, and
Undo/Clear are present in `PaletteViewController.controls`; at both measured
widths the baseline overflow is hidden and the eight direct tools remain
visible, giving 17 visible controls. A temporary AppKit baseline runtime probe
instantiated those default AppKit controls and reported:

```text
baseline visible controls (excluding palette.status)=17
baseline controls accepting first responder=17
baseline visible semantic status elements=1
```

The baseline source's `layoutControls()` creates one horizontal `firstRow`
stack. Its two `PaletteLayoutPlan.rows` at 760 points are a planning artifact,
not two rendered view rows, so this report deliberately records rendered tool
rows as 1 for both baseline scenarios.

Candidate always-visible controls are measured from the shown panel's runtime
controls whose identifier is not `palette.status` and whose `isHidden` is
false. The standard surface keeps all eight direct tools and hides More,
yielding 17. The clamped surface shows the first five tools plus More and
keeps the six style controls and Undo/Clear, yielding 15. Enabled focus stops
add `isEnabled` and `acceptsFirstResponder`: 12 at the standard width and 10
at the clamped width. Disabled contextual controls and empty-history Undo/Clear
remain visible but do not create focus stops.

Rendered tool rows are not taken from `PaletteLayoutPlan.rows`. The test finds
the actual horizontal `NSStackView` whose arranged subviews contain mode,
every tool, and More, filters hidden arranged subviews, converts their frames
into the controller view, and clusters their y-centers. Both candidate
scenarios therefore measure one real tool row.

The candidate test also asserts the exact visible identifier set, panel width,
Arrow accessibility element/name/responder route, and hidden standby
`palette.delete` control.

The first-use guide is not included in permanent chrome: it is a separate,
nonpersistent panel and its existing guide tests cover dismissal and focus.
It therefore adds no required common-path interaction or permanent status
element.

## Text taxonomy and additions/removals

The candidate has exactly one semantic text element: `palette.status`. The
runtime view hierarchy also contains exactly four numeric, noninteractive value
captions (`4`, `100%`, `15%`, `50%`) and six noninteractive context labels
(`Color`, `Emoji`, `Stroke`, `Opacity`, `Radius`, `Dimness`). The test classifies
all visible text fields after excluding AppKit's internal `Standby` button-title
field, then asserts the complete 1 + 4 + 6 set. Every value/context caption is
absent from `PaletteViewController.controls`, does not accept first responder,
and is absent from the enabled focus loop; none carries the `palette.status`
identifier. This keeps control-value text useful for learning without inflating
the persistent control, focus, or semantic-status counts.

At the clamped 760-point viewport, the candidate replaces the always-visible
Eraser, Emoji, and Spotlight buttons with the named More overflow route. The
visible overflow control costs one control while three direct controls leave
the persistent surface, producing the measured net reduction of two controls.
Rendered tool rows remain one in both baseline and candidate; the candidate
does not claim a row reduction. The overflow menu retains stable accessible
actions for those tools.

The candidate also adds contextual `palette.delete` (hidden in standby), a
`menu.learn-pointer` action (available only when the menu is opened), native
tool symbols on existing controls, and the four value captions above. These
are disclosed additions, not counted as always-visible controls, focus stops,
or semantic status elements. Existing C accessibility/overflow tests retain
the keyboard and accessible routes; this task does not hide or remove them to
lower the inventory.

No C-owned deletion finding is required by this measured inventory: all four
tracked dimensions are non-increasing at both widths, with focus decreasing at
the standard width and controls plus focus decreasing at the clamped width.

## Common-path proof

The test creates the fresh default session (standby, Arrow tool), synchronizes
one display, loads the real palette at the comparison width, performs the
visible Arrow control action, then uses the synchronized test overlay's real
`CanvasView` gesture (begin/continue/end). `ChromeFrictionOverlay` owns that
CanvasView and forwards its `onSessionUpdate`/`onBoundaryEvent` callbacks to
the closures installed by `DisplayCoordinator`, matching the production
overlay ownership route. The test then reads the committed mark from
`router.session.canvas(for:)` before sending the real Escape key route
(`keyCode: 53`). The route assertions prove:

1. one Arrow control activation enters annotation without a separate mode
   click;
2. one CanvasView gesture commits an arrow through DisplayCoordinator into the
   router session, with normalized endpoints `(0.2, 0.2)` and `(0.8, 0.8)`;
   and
3. one Escape key returns the router to standby.

The resulting inventory is exactly 1 required click, 1 required key, and 3
semantic steps (choose Arrow, draw, return to standby). The baseline
`CommandRouter` source already routed `setTool` to annotation and handled
Escape, so the candidate adds no common-path interaction.

## Verification

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ChromeFrictionTests
GREEN: 2 tests, 0 failures.

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'ChromeFrictionTests|FirstUseGuideTests|RenderPlanTests'
GREEN: 34 tests, 0 failures.

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
GREEN: 301 tests, 0 failures.

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build
GREEN: Build complete (exit 0).

git diff --check
GREEN: no whitespace errors (exit 0).
```

The Task 4 artifact originated in coordinator commit `48aef59`; this inventory
evidence supersedes its fixed-width/model-row claims. Physical fresh-launch and
manual VoiceOver proof remain outside this deterministic test-only task and
belong to the later F gate.
