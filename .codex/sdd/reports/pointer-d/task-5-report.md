# Pointer D Task 5 Report — Reconciliation Gate

Status: `READY_FOR_PHASE_REVIEW`

Worktree: `/Users/bruno/Dev/pointer/.worktrees/stable-app`

Head: `d57f07c` (`test: measure real Pointer chrome`)

D range: `9e6e175..d57f07c`

## Reconciliation verdict

Tasks 1–4 each received an independent reviewer verdict of `APPROVED`, and
each then received an adversarial Codex verdict of `RECONCILED`. These are
current facts from the active orchestration record, not repository markers or
claims inferred from test names.

The four task reports remain the detailed evidence for their individual
contracts:

- [Task 1 — Render Plan](task-1-report.md)
- [Task 2 — First-Use Guide](task-2-report.md)
- [Task 3 — Raster Assets and Identity](task-3-report.md)
- [Task 4 — Persistent Chrome and Common Path](task-4-report.md)

## Accepted D evidence

### Rendering

- `RenderPlan.make` retains committed marks in standby, partitions the
  explicit preview draft, and fail-closes invalid selection/hover inventories.
- Standby and annotation drawing order is committed marks, active draft, then
  visible selection handles.
- Canonical 512 × 512 sRGB RGBA8 standby renderer digest:
  `049d2e0cfbdd8f6c02f4db31955dc408f6eda47ad93f2e4bf50516acfd4d5771`.

### First-use guide

- Catalog schema version: `1`.
- Catalog identifier: `pointer.first-use-guide.v1`.
- Eight informative entries: Arrow, Rectangle, Ellipse, Pen, Spotlight,
  Emoji, Select, and Eraser.
- Three variants per entry: light, dark, and high contrast.
- Every example resolves through the injected catalog and injected bundle
  route; strict metadata, identifier, hash, duplicate, missing-variant, and
  missing-image validation is covered.
- The guide has injected state, placement, appearance, focus, accessibility,
  display-loss, stop, dismissal, and retry behavior. A `.shown` result is not
  committed until the panel reports visibility.

### Visual assets

- App icon identity digest:
  `dc9bb4ae78701a0d79004050eb062b836f1aa7623ad13c0b09b45d5a6dd59068`.
- Ten distinct tracked AppIcon PNG files cover the required macOS physical
  sizes and are bound by `AppIconIdentity.json`.
- There are 24 tracked first-use guide PNGs (8 entries × 3 variants), each
  512 × 512, sRGB, and no alpha channel.
- The generated masters, exact built-in ImageGen prompts, master hashes,
  sips-only deterministic crop commands, per-source hashes, visual inspection,
  and recorded temporary `actool`/`assetutil` proof are in
  [Task 3’s asset report](task-3-report.md). That recorded asset-catalog proof
  is not rerun in this gate; packaged `Assets.car` validation remains F-owned.

### Persistent chrome and common path

The Task 4 tuple is, in order, **always-visible controls / rendered tool rows /
visible semantic status elements / enabled keyboard focus stops**. Rendered
tool rows are measured from the actual stack hierarchy; the old
`PaletteLayoutPlan.rows` value is not treated as rendered topology.

| Scenario | Baseline | Candidate | Result |
| --- | --- | --- | --- |
| Standard display, 1920 × 1080, measured 822 pt | `17/1/1/17` | `17/1/1/12` | no increase; focus −5 |
| Clamped display, 792 pt visible, measured 760 pt | `17/1/1/17` | `15/1/1/10` | controls −2; focus −7 |

The candidate keeps the common path at exactly **1 click / 1 key / 3 semantic
steps**: choose Arrow, draw, return to standby. At the clamped width, More
preserves access to the overflowed tools while reducing persistent chrome. The
guide is a separate nonpersistent panel and is excluded from this chrome
inventory.

## Fresh verification

All commands below were run at `d57f07c` with
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'RenderPlanTests|FirstUseGuideTests|AssetIdentityTests|ChromeFrictionTests'
exit 0
PointerPackageTests.xctest: 38 tests, 0 failures
Selected tests: 38 tests, 0 failures

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
exit 0
PointerPackageTests.xctest: 301 tests, 0 failures
All tests: 301 tests, 0 failures

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build
exit 0
Build complete

git diff --check
exit 0
No whitespace errors
```

The focused suites cover 4 asset-identity tests, 2 chrome-friction tests, 24
first-use-guide tests, and 8 render-plan tests. The full suite also covers the
existing lifecycle, accessibility, palette, router, gesture, and smoke
contracts.

## Scope and path inventory

`git diff --name-status 9e6e175..d57f07c` reports 83 changed paths:

- 9 D plan/report/brief paths;
- 61 tracked D asset and identity paths;
- 7 D production paths (`MarkRenderer`, rendering values, and first-use guide
  implementation);
- 6 D test paths (render, guide, asset, and chrome evidence).

The range contains only these D-owned categories. It does not change B’s
CanvasView integration, C’s composition surface, A diagnostics, E
performance work, or F packaging/build files. Before this report was created,
the worktree was clean at `d57f07c` on `codex/stable-app` (ahead of its remote
by 30 commits). After this uncommitted report is written, the only expected
working-tree path is this file:

```text
?? .codex/sdd/reports/pointer-d/task-5-report.md
```

No commit is created by this task.

## Explicit handoffs and remaining phase-gate work

D does **not** compose the live CanvasView render path or the packaged
launcher.

- **B owns live CanvasView render integration.** The D render contract is
  standalone and tested, but the current `CanvasView.draw(_:)` still uses the
  existing canvas/selection renderer route. B must derive the committed canvas,
  preview canvas, and explicit active draft on session updates and gesture
  boundaries, then pass the D `RenderPlan` into the live view.
- **F owns real guide/catalog composition.** F must load
  `GuideAssetIdentity.json`, construct the throwing catalog against the
  packaged bundle, and wire the real first-use controller at the composition
  root.
- **F owns packaged assets and launch behavior.** This includes compiling and
  shipping `Assets.car`, the AppIcon, Launch Services/icon-cache and
  idempotence checks, the packaged unseen-guide/manual VoiceOver matrix, and
  the final release smoke path.

The current `Sources/Pointer/main.swift` still contains the no-op
`LauncherFirstUseGuide`: `showIfNeeded` and `show` return `.notNeeded`, and its
state store never marks the guide seen. That is an explicit F composition
handoff, not a D completion claim. The D tests prove the injected controller,
view, assets, rendering contract, and friction inventory independently; they
do not prove the packaged unseen-guide launch path.

