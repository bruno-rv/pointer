# Pointer C Phase-Wide Reconciliation

Date: 2026-08-30
Worktree: `/Users/bruno/Dev/pointer/.worktrees/stable-app`
Status: `DONE_WITH_CONCERNS` (reviewer revisions reconciled; no commit)

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
runtime assertion typo. After the protocol, controller, spy, command, palette,
and test-fake changes, the focused suites were rerun GREEN. The follow-up
reviewer requirements were then written RED before implementation:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'GuideIntegrationTests|PaletteInteractionTests|CommandRouterTests'
exit 1
GuideIntegrationTests.swift: cannot find 'GuideRetryFixture' in scope
PaletteInteractionTests.swift: stale post-resolution expectation omitted the
active shortcut label
```

The durable-suppression follow-up was also run RED by adding a second
post-resolution refresh:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PaletteInteractionTests/testShortcutErrorKeepsPriorityOverFeedbackAndRestoresNormalStatus
exit 1
XCTAssertEqual failed: "Select a mark to delete" is not equal to
"Annotation enabled · Shortcut: control-option-command-p"
```

After the explicit Learn Pointer tests, fresh-context real-fixture test, shortcut
precedence guard, and single tool-label source were implemented, the focused
suite was rerun GREEN:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'CommandRouterTests|GuideIntegrationTests|PaletteInteractionTests'
exit 0
CommandRouterTests: 18 passed
GuideIntegrationTests: 35 passed
PaletteInteractionTests: 35 passed
total: 88 passed, 0 failed
```

The fresh-context test reuses the existing real `GuideControllerFixture` and
`PalettePanel`: its placement provider suppresses only the context-request
label after startup, while the manually dragged real window provides the
no-re-show oracle. This avoids maintaining a parallel 140-line fake palette
and keeps the assertion on production behavior.

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
  Retry recomputes a fresh context from the injected provider, current display,
  and current palette frame, so it does not reposition the palette on an
  ordinary connected sync. Explicit Learn Pointer/showGuide success consumes
  superseded pending intent; failed or hidden explicit shows remain retryable.
- Successful mode/tool routes publish explicit status text: annotation entry,
  standby click-through state, every tool name, and the combined standby-to-tool
  transition. Existing no-display/no-op feedback remains authoritative.
- `CommandRouter.updateDisplayState` clears only the exact stale
  `No presentation display connected` message after an accepted valid pointer
  display. Unrelated feedback survives, and the palette status returns to its
  normal mode message after refresh.
- Palette status gives shortcut registration errors precedence over immediate
  success and no-op feedback, preserves frame/focus, and returns to the current
  normal mode/shortcut status after the error resolves. The module-internal
  `PointerTool.displayName` is the single source for tool labels.
- Shortcut-error suppression is durable across repeated refreshes while the
  router still holds the exact hidden feedback; changing or clearing that
  feedback releases suppression for the next status update.

## Current source context

The reviewer revision was applied on top of `433a943` (`fix: reconcile Pointer
product surface`), which contains the prior C phase implementation. This
handoff intentionally has no new commit; the coordinator owns commit grouping
and publication.

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
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'CommandRouterTests|PaletteLayoutTests|PaletteInteractionTests|GuideIntegrationTests|HotKeyControllerTests|ShortcutLifecycleTests|AccessibilityMetadataTests|PointerApplicationControllerTests'
exit 0
C phase-wide filter: 127 passed, 0 failed

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
exit 0
PointerPackageTests.xctest: 252 passed, 0 failed

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/verify.sh
exit 0
full tests: 252 passed, 0 failed
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
