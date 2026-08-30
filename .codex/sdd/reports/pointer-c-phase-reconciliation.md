# Pointer C Phase-Wide Reconciliation

Date: 2026-08-30
Worktree: `/Users/bruno/Dev/pointer/.worktrees/stable-app`
Status: `DONE_WITH_CONCERNS` (worker handoff; no commit)

## Scope

This reconciliation consumes B's accepted `PointerSession.selectedDisplay`,
`DisplaySyncResult`, and `DisplayStopResult` contracts. It changes only C-owned
controller, command, guide-protocol, launcher-bootstrap, and test/documentation
paths. The B-owned selected-display implementation is preserved; future changes
to that ownership return to B.

## TDD evidence

The new tests were written before the production implementation and run RED:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'CommandRouterTests|GuideIntegrationTests'
exit 1
GuideIntegrationTests.swift: value of type 'GuideTestSpyGuide' has no member
'showIfNeededResult' / 'restoreAfterDisplayLossResult'
```

The failure was caused by the missing explicit guide-result test seam, not a
runtime assertion typo. After the protocol, controller, spy, command, and
palette changes, the focused suites were rerun GREEN:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'CommandRouterTests|GuideIntegrationTests|PaletteInteractionTests'
exit 0
CommandRouterTests: 18 passed
GuideIntegrationTests: 31 passed
PaletteInteractionTests: 34 passed
total: 83 passed, 0 failed
```

## Reconciled behavior

- Initial palette presentation is explicit and independent from guide dismissal.
  Zero-display startup keeps the presentation pending; an ordinary connected
  sync does not call `palette.show(on:)` or move a manually dragged palette.
  A palette hidden before the zero-display transition remains hidden; a
  visible palette is restored and clamped. Repeated zero-display notifications
  preserve pending restore intent. Explicit Show Palette still repositions.
- `GuidePresentationResult` is `Equatable`/`Sendable`, and all guide
  presentation methods are `@discardableResult`. The controller clears pending
  first-use/restore intent only for `.shown` when `guide.isVisible` is true or
  `.notNeeded`; `.failed` and hidden/false `.shown` results remain retryable.
  Retry uses the last successful palette context, so it does not reposition the
  palette on an ordinary connected sync.
- Successful mode/tool routes publish explicit status text: annotation entry,
  standby click-through state, every tool name, and the combined standby-to-tool
  transition. Existing no-display/no-op feedback remains authoritative.
- `CommandRouter.updateDisplayState` clears only the exact stale
  `No presentation display connected` message after an accepted valid pointer
  display. Unrelated feedback survives, and the palette status returns to its
  normal mode message after refresh.

## Current source context

The worktree started at `677d974` (`fix: refresh Pointer effective
appearance`), with C's prior accepted history through `118486a` and the
shortcut/guide lifecycle commits preceding it. This handoff intentionally has
no new commit; the coordinator owns commit grouping and publication.

Changed paths in this worker diff:

- `.codex/sdd/features/2026-08-23-pointer-c-product-surface-accessibility-plan.md`
- `.codex/sdd/features/2026-08-23-pointer-d-visual-language-plan.md`
- `.codex/sdd/features/2026-08-23-pointer-six-month-quality-design.md`
- `Sources/Pointer/main.swift`
- `Sources/PointerAppKit/CommandRouter.swift`
- `Sources/PointerAppKit/Help/FirstUseGuidePresenting.swift`
- `Sources/PointerAppKit/PointerApplicationController.swift`
- `Tests/PointerAppKitTests/CommandRouterTests.swift`
- `Tests/PointerAppKitTests/GuideIntegrationTests.swift`
- `Tests/PointerAppKitTests/PaletteInteractionTests.swift`
- `Tests/PointerAppKitTests/PointerApplicationControllerTests.swift`
- `.codex/sdd/reports/pointer-c-phase-reconciliation.md`

No D concrete guide implementation, raster assets, F composition root, live
VoiceOver session, physical multi-display/manual composition check, or D/F
release claim is included here. The temporary launcher remains a no-op guide
bootstrap until F replaces it with the final composition root.

## Verification evidence

After the focused GREEN run:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
exit 0
PointerPackageTests.xctest: 247 passed, 0 failed

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/verify.sh
exit 0
full tests: 247 passed, 0 failed
Info.plist: OK; codesign: OK; arm64 bundle: OK; smoke contract: passed

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/benchmark-gestures.sh
exit 0
release benchmark: finalStateValid=true, checksumIsStable=true,
trialCount=30, rendererTimed=false, compositorTimed=false

git diff --check
exit 0
```

## Remaining verification / concerns

The coordinator must still send this diff through the independent reviewer and
adversarial Codex loop. The automated tests and release contracts do not
substitute for D's concrete guide tests or F's live/manual composition,
VoiceOver, and physical multi-display evidence. The temporary launcher remains
an explicit no-op guide bootstrap until F replaces it with the final
composition root.
