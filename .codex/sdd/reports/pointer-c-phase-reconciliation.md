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

The phase-review hidden-palette intent tests were then run RED:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'GuideIntegrationTests/testFailedFirstUseKeepsIntentWhenPaletteHiddenBeforeZeroDisplay|GuideIntegrationTests/testFailedRestoreKeepsIntentWhenPaletteIsHiddenBeforeExplicitShow'
exit 1
first-use explicit Show Palette: expected guide.showIfNeeded, got palette.show only
display-loss explicit Show Palette: expected guide.restoreAfterDisplayLoss, got palette.show only
```

The overflow accessibility/inventory test was then run RED before adding the
menu-item contract:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PaletteInteractionTests/testOverflowToolItemsExposeStableAccessibilityMetadataAndInventory
exit 1
XCTAssertEqual failed: "1" is not equal to "6"
missing stable palette.overflow.tool.* identifiers, selected/not-selected
accessibility values, and overflow rows in ControlMetadataInventory
```

The canonical guide protocol-ownership test was then run RED before moving
the state-store declaration:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter GuideIntegrationTests/testGuideProtocolOwnershipUsesCanonicalFilesWithoutDuplicates
exit 1
FirstUseGuideStateStoring.swift could not be opened because the file does not exist
```

After the explicit Learn Pointer tests, fresh-context real-fixture test,
hidden-palette intent preservation, shortcut precedence guard, and single
tool-label source were implemented, the focused suite was rerun GREEN:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'CommandRouterTests|GuideIntegrationTests|PaletteInteractionTests'
exit 0
CommandRouterTests: 18 passed
GuideIntegrationTests: 38 passed
PaletteInteractionTests: 38 passed
total: 94 passed, 0 failed
```

The ownership split was then verified GREEN by the same source-contract test:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter GuideIntegrationTests/testGuideProtocolOwnershipUsesCanonicalFilesWithoutDuplicates
exit 0
exactly one state-store declaration, one presenting declaration, and zero
duplicate declarations/extensions across Sources and Help files
```

The state-store protocol appears exactly once in its canonical file, the
presenting protocol exactly once in its canonical file, and no other Help
source redeclares or extends either protocol.

The final Clear All and semantic-tool-row tests were run RED before the router,
menu, and inventory guards:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'PaletteInteractionTests/testClearAllMenuItemAndRouteStayDisabledUntilAcceptedMarksExist|PaletteInteractionTests/testMetadataReplacesHiddenToolRowsWithOverflowActionsAtSupportedWidths'
exit 1
empty Clear All still invoked confirmation and overflow layouts exposed both
palette.tool.* and palette.overflow.tool.* semantic rows
```

The final pending-shortcut/no-display tests were authored before their seams
were implemented. The first invocation with the host's default developer
directory could not load XCTest; rerunning with the repository's Xcode toolchain
exposed and corrected the test-only fixture conformance/lookup errors before
the production behavior was accepted:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'PaletteInteractionTests/testPendingShortcutGuidanceIsSharedByPaletteAndMenuThroughDelivery|PaletteInteractionTests/testPendingShortcutReplacementTimeoutAndRegistrationFailureStayActionable|PointerApplicationControllerTests/testZeroDisplayKeepsMenuFallbackActionableAndHotkeyFeedbackVisible'
initial compile: PendingShortcutScheduler missing activeTimerCount;
PendingShortcutUIFixture used a non-existent controller; nested shortcut items
were looked up from the top-level menu
after fixture-only corrections: 3 passed, 0 failed
```

The final precedence regression was added RED before changing the palette
status ordering:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'PaletteInteractionTests/testPendingShortcutGuidanceOutranksTransientFeedbackThroughDelivery|PaletteInteractionTests/testPendingShortcutGuidanceKeepsPriorityUntilTimeoutError'
exit 1
pending guidance was replaced by Nothing to undo, Nothing to clear, and
Select a mark to delete in visible and accessibility status; timeout branch
was similarly replaced by Select a mark to delete
after the palette captured the exact transient feedback while pending:
2 passed, 0 failed
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
  preserve pending restore intent. Failed first-use intent survives a manual
  hide and is retried by explicit Show Palette; failed display-loss restore
  intent survives temporary hiding until explicit Show Palette/Learn or a
  documented terminal outcome. Explicit Show Palette still repositions.
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
- Overflow tool menu items have stable unique identifiers, accessible
  label/help/value/role, and are included immediately after the parent popup
  in deterministic metadata inventory without duplicating hidden tool buttons.
  Rebuilding at 420 and 760 points preserves item count, IDs, selected state,
  and routed actions. At overflow widths hidden direct tool rows are replaced
  by their overflow rows; all-tools layouts retain direct rows only. Emoji
  presets remain one native value popup rather than a separate action
  hierarchy, so no additional popup contract was introduced.
- `CommandRouter.canClearAll` now derives from accepted connected display UUIDs
  and nonempty canvases. Direct Clear All no-ops publish `Nothing to clear`
  without confirmation; the menu item exposes `Available` or
  `Unavailable — no marks to clear` and preserves Undo Clear All.
- Palette status gives shortcut registration errors precedence over immediate
  feedback, pending shortcut guidance precedence over transient no-op feedback,
  and normal mode status lowest priority. It preserves frame/focus, captures
  the exact suppressed feedback while pending, and returns to the current
  normal mode/shortcut status after delivery or error resolution without
  replaying stale feedback. The module-internal `PointerTool.displayName` is
  the single source for tool labels.
- Pending shortcut state is read-only through `CommandRouter.pendingShortcutDisplayName`
  and `pendingShortcutGuidance`, derived from `HotKeyController.pendingPreset`.
  The palette, shortcut parent, status item, and candidate menu action share the
  same canonical display name/guidance; candidate state is non-color `Pending`
  while the old active item remains selected until delivery. Timeout and
  registration failure retain actionable errors, and successful delivery updates
  the active item.
- When no accepted pointer display exists, the menu bar remains visible and
  actionable while the palette is hidden: annotation mode is disabled with the
  exact unavailable help/value, the status item presents a native warning image
  and `No presentation display connected`, and no-display hotkey rejection
  refreshes that warning without mutating mode/tool. Reconnect restores the
  normal status affordance; Show Palette, Learn, shortcut settings, and Quit
  remain enabled.
- Shortcut-error suppression is durable across repeated refreshes while the
  router still holds the exact hidden feedback; changing or clearing that
  feedback releases suppression for the next status update.
- `FirstUseGuideStateStoring` is a separate canonical public `@MainActor` seam
  consumed by C and D, while `FirstUseGuidePresenting` remains the sole
  presenting-protocol declaration. The source contract rejects duplicate
  declarations or extensions in D Help sources.

## Current source context

The reviewer revision was applied on top of `1f6df3a` (`refactor: separate
Pointer guide state seam`), which contains the prior C phase implementation.
This
handoff intentionally has no new commit; the coordinator owns commit grouping
and publication.

Changed paths in this worker diff:

- `.codex/sdd/features/2026-08-23-pointer-c-product-surface-accessibility-plan.md`
- `.codex/sdd/features/2026-08-23-pointer-d-visual-language-plan.md`
- `.codex/sdd/features/2026-08-23-pointer-six-month-quality-design.md`
- `Sources/Pointer/main.swift`
- `Sources/PointerAppKit/CommandRouter.swift`
- `Sources/PointerAppKit/Palette/ControlMetadataProvider.swift`
- `Sources/PointerAppKit/Palette/PaletteViewController.swift`
- `Sources/PointerAppKit/Help/FirstUseGuidePresenting.swift`
- `Sources/PointerAppKit/Help/FirstUseGuideStateStoring.swift`
- `Sources/PointerAppKit/PointerApplicationController.swift`
- `Tests/PointerAppKitTests/CommandRouterTests.swift`
- `Tests/PointerAppKitTests/GuideIntegrationTests.swift`
- `Tests/PointerAppKitTests/PaletteInteractionTests.swift`
- `Tests/PointerAppKitTests/AccessibilityMetadataTests.swift`
- `Tests/PointerAppKitTests/PointerApplicationControllerTests.swift`
- `.codex/sdd/reports/pointer-c-phase-reconciliation.md`

No D concrete guide implementation, raster assets, F composition root, live
VoiceOver session, physical multi-display/manual composition check, or D/F
release claim is included here. The temporary launcher remains a no-op guide
bootstrap until F replaces it with the final composition root.

## Verification evidence

After the final focused GREEN run, including pending-guidance precedence:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'CommandRouterTests|PaletteLayoutTests|PaletteInteractionTests|GuideIntegrationTests|HotKeyControllerTests|ShortcutLifecycleTests|AccessibilityMetadataTests|PointerApplicationControllerTests'
exit 0
C phase-wide filter: 138 passed, 0 failed

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
exit 0
PointerPackageTests.xctest: 263 passed, 0 failed

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/verify.sh
exit 0
full tests: 263 passed, 0 failed
Info.plist: OK; codesign: OK; arm64 bundle: OK; smoke contract: passed

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/benchmark-gestures.sh
exit 0
release benchmark: finalStateValid=true, checksumIsStable=true,
trialCount=30, rendererTimed=false, compositorTimed=false

git diff --check
exit 0
```

## Metadata role correction

The real AppKit metadata fixture exposed a host-specific accessibility gap: the
native role query returns `AXUnknown` as a non-`nil` value for several palette
controls and the status-item button. The previous helper treated that value as
authoritative, so the type fallback was skipped. The helper now treats both
`nil` and `AXUnknown` as missing, preserves any other native role, and maps
known control types to their concrete roles (`NSButton` to `AXButton`,
`NSPopUpButton` to `AXPopUpButton`, `NSColorWell` to `AXColorWell`, `NSSlider`
to `AXSlider`, and `NSTextField` to `AXStaticText`). Menu items use the same
missing-role rule and retain their `AXMenuItem` fallback.

The regression test was written and run RED before the production change:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'AccessibilityMetadataTests/testRealPaletteAndMenuMetadataUsesConcreteNativeRoles'
exit 1
20 real palette/menu-bar controls reported AXUnknown (40 role assertions)
```

After the minimal helper change, the same fixture ran GREEN:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'AccessibilityMetadataTests/testRealPaletteAndMenuMetadataUsesConcreteNativeRoles'
exit 0
1 passed, 0 failed
```

The matrix covers mode, all eight tools, overflow, emoji, color, all four
sliders, undo, clear, delete, status, and `pointer.menu-bar`; compact-layout
overflow headers and tool rows are also asserted as `AXMenuItem`. The existing
dirty A-owned `ControlMetadataHarnessTests.swift` and
`pointer-a-harness-metadata-report.md` paths were preserved and not edited.

## Narrow-display reconciliation addendum

The canonical 420-point visible display now remains a 388-point palette after
the real synchronized overlay and shortcut surface are initialized. The root
cause was the active-shortcut status string contributing an unconstrained
intrinsic width: AppKit computed a 487-point palette fitting width before the
panel was ordered. The status field now stays on one truncated line and allows
horizontal compression; the style row remains an intrinsic 635-point
document inside its horizontal scroll view, so no essential control hit target
is compressed.

The regression was observed RED in the real A-owned narrow fixture:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ControlMetadataHarnessTests/testCanonicalNarrowFixtureKeepsNativePaletteAndOverflowAccessible
exit 1
palette.show(on:) returned .failed after the synchronized fixture measured a
487-point final frame for a 388-point request
```

The focused C regression coverage is now GREEN:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'PaletteInteractionTests/testNarrowPaletteKeepsRequestedWidthAndScrollsStyleControls|PaletteInteractionTests/testFinalPaletteLayoutGuardRejectsFrameOrContentOverflow|ControlMetadataHarnessTests/testCanonicalNarrowFixtureKeepsNativePaletteAndOverflowAccessible'
exit 0
3 passed, 0 failed
```

`PalettePanel` also performs a fail-closed post-ordering check over the final
window frame and content frame. A violation hides the panel, stops appearance
observation, and returns an actionable `.failed` result. Existing smaller-than-
native coverage continues to assert `.failed`, hidden state, and zero
observers. The new narrow test asserts exact 388-point sizing, 16-point
visible-frame margins, horizontal style scrolling, and Select/More topology.
The A harness files and their six-test metadata fixture remain unchanged by
this addendum; the coordinator should rerun that complete six-test filter
before phase sign-off.

## Remaining verification / concerns

The coordinator must still send this diff through the independent reviewer and
adversarial Codex loop. The automated tests and release contracts do not
substitute for D's concrete guide tests or F's live/manual composition,
VoiceOver, and physical multi-display evidence. The temporary launcher remains
an explicit no-op guide bootstrap until F replaces it with the final
composition root.
