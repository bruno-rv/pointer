# Pointer D Task 4 Report — Persistent Chrome and Common Path

Status: `DONE_WITH_CONCERNS`

## Scope and identities

This task changed only the D-owned test/report paths below. No production
source, C-owned palette/menu/controller source, or Task 3 asset was edited.

- Baseline: `caa2bd0` (`fix: preserve Pointer gesture boundary delivery`), the
  accepted B-core commit immediately before C product-surface work.
- Candidate: `b3cef8c` (`test: verify Pointer asset identity`), the worktree
  HEAD used for the measurement.
- Worktree: `/Users/bruno/Dev/pointer/.worktrees/stable-app`, branch
  `codex/stable-app`.
- Added: `Tests/PointerAppKitTests/ChromeFrictionTests.swift`.
- Added: `.codex/sdd/reports/pointer-d/task-4-report.md`.

The worktree already contained unrelated changes in
`Tests/PointerAppKitTests/AssetIdentityTests.swift` and
`.codex/sdd/reports/pointer-d/task-3-report.md`; they were preserved.

## Strict RED/GREEN evidence

The first test-only RED run was:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ChromeFrictionTests
```

It failed at compilation because the new test's `ChromeInventory`,
`CommonPathInventory`, and candidate-measurement helpers were not yet defined.
No production code was present behind the test. Adding those measurement
helpers in the same test file produced GREEN:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ChromeFrictionTests
GREEN: 2 tests, 0 failures.
```

## Inventory method and exact counts

The comparison uses the baseline's 760-point palette width for both sides.
This holds available width constant instead of treating the candidate's wider
preferred width as an improvement. Candidate counts are measured from a real
`DisplayCoordinator`/`CommandRouter` display sync, a real
`PaletteViewController`, `loadViewIfNeeded()`, `refresh(session:)`,
`applyLayout(for: 760)`, and `layoutSubtreeIfNeeded()`.

| Dimension | Baseline `caa2bd0` | Candidate `b3cef8c` | Change |
| --- | ---: | ---: | ---: |
| Always-visible palette controls | 17 | 15 | -2 |
| Palette layout rows | 2 | 1 | -1 |
| Visible semantic status elements | 1 | 1 | 0 |
| Enabled focus stops | 17 | 10 | -7 |
| Required pointer/control clicks | 1 | 1 | 0 |
| Required keyboard keys | 1 | 1 | 0 |
| Required semantic steps | 3 | 3 | 0 |

Baseline counts are derived from `git show caa2bd0` source. Its
`PaletteViewController.controls` contains one mode control, eight direct tool
controls, one overflow control, six style controls, and Undo/Clear. At the
760-point baseline layout, the overflow control is hidden and the eight direct
tools occupy two `PaletteLayoutPlan.rows`, leaving 17 visible controls. The
separate `palette.status` label is visible and the baseline controls are
configured as enabled action/focus controls, giving 1 status element and 17
focus stops.

Candidate always-visible controls are the runtime controls whose identifier is
not `palette.status` and whose `isHidden` is false. At 760 points these are
mode, Select, Arrow, Rectangle, Ellipse, Pen, the visible More popup, six style
controls, and Undo/Clear: 15. The candidate's `palette.status` identifier is
counted separately as the one visible semantic status element. Focus stops are
the same visible runtime controls after requiring `isEnabled` and
`acceptsFirstResponder`: mode, five direct tools, More, Color, Stroke, and
Opacity: 10. The candidate's disabled contextual controls and empty-history
Undo/Clear remain visible, but do not create focus stops.

`PaletteLayoutPlan.rows.count` supplies the row count: baseline source returns
two rows at 760 points; candidate runtime metadata returns one row containing
the visible tools and overflow. The candidate test also asserts the exact
visible identifier set, Arrow accessibility element/name/responder route, and
hidden standby `palette.delete` control.

The first-use guide is not included in permanent chrome: it is a separate,
nonpersistent panel and its existing guide tests cover dismissal and focus.
It therefore adds no required common-path interaction or permanent status
element.

## Additions and removals

At the fixed 760-point viewport, the candidate removes the second direct tool
row and replaces the always-visible Eraser, Emoji, and Spotlight buttons with
the named More overflow route. The visible overflow control costs one control
while three direct controls leave the persistent surface, producing the
measured net reduction of two controls and one row. The overflow menu retains
stable accessible actions for those tools.

The candidate also adds contextual `palette.delete` (hidden in standby), a
`menu.learn-pointer` action (available only when the menu is opened), native
tool symbols on existing controls, and four noninteractive numeric value
captions for sliders. These are disclosed additions, not counted as
always-visible controls, focus stops, or semantic status elements: the status
metric is specifically the visible `palette.status` element. Existing C
accessibility/overflow tests retain the keyboard and accessible routes; this
task does not hide or remove them to lower the inventory.

No C-owned deletion finding is required by this measured inventory: every
requested persistent dimension is non-increasing and at least two dimensions
decrease. If a later review elects to classify static slider value captions as
status elements rather than control-value labels, that alternate taxonomy must
be measured separately and returned to C; this report does not silently fold
them into the one semantic status count.

## Common-path proof

The test creates the fresh default session (standby, Arrow tool), synchronizes
one display, loads the real palette at the comparison width, performs the
visible Arrow control action, draws one real `PointerSession` arrow gesture
(begin/advance/commit), then sends the real Escape key route (`keyCode: 53`).
The route assertions prove:

1. one Arrow control activation enters annotation without a separate mode
   click;
2. one draw gesture commits an arrow; and
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

No commit was created. Physical fresh-launch/manual VoiceOver proof remains
outside this deterministic test-only task and belongs to the later F gate.
