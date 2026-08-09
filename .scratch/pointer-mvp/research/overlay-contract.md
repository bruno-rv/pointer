# Full-screen overlay contract

Research date: 2026-08-06. Target: macOS 14+ on Apple silicon.

## Decision

The supported AppKit configuration to prototype is **one transparent `NSPanel`
per `NSScreen`**, not a single spanning window. Each panel should be
borderless and non-activating, remain visible while Pointer is inactive, and
join all Spaces and other applications' full-screen sets:

```swift
let panel = NSPanel(
    contentRect: screen.frame,
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered,
    defer: false,
    screen: screen
)

panel.isOpaque = false
panel.backgroundColor = .clear
panel.hasShadow = false
panel.hidesOnDeactivate = false
panel.level = .screenSaver
panel.collectionBehavior = [
    .canJoinAllSpaces,
    .canJoinAllApplications,
    .stationary,
    .ignoresCycle,
    .fullScreenAuxiliary,
]
panel.ignoresMouseEvents = true       // standby
panel.orderFrontRegardless()          // initial presentation only
```

This is a supported composition of public AppKit APIs on the stated minimum
OS. It has a **qualified** contract:

- it is designed to be above normal app windows, remain across Spaces, and
  participate beside an app's full-screen window;
- it can remain on screen without activating Pointer and can be made
  click-through in standby; but
- it is **not a public guarantee** that an arbitrary third-party video path,
  DRM/protected surface, system UI, lock screen, or future WindowServer policy
  will render below it. Apple describes the relevant full-screen behavior as
  “can be shown” / “when eligible,” not as an absolute z-order guarantee.

The ticket can therefore proceed to a local proof-of-behavior prototype, not
to a claim of universal coverage. Do not use private `CGS*` APIs or invented
raw window levels to close that gap.

## Why this configuration

### Window class, style, and transparency

Use `NSPanel`, because `.nonactivatingPanel` is specifically the style for a
panel (or panel subclass) that does not activate its owning app. `.borderless`
removes normal window chrome. A borderless window cannot become key or main by
default; that is desirable in standby, but an editing subclass must opt into
key status if it needs keyboard focus. Set `isOpaque = false`, a clear
`backgroundColor`, and `hasShadow = false` to obtain a transparent, shadowless
canvas rather than merely a translucent normal window.

- [`NSWindow.StyleMask.nonactivatingPanel`](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel)
  says that the panel does not activate the owning app.
- [`NSWindow.StyleMask.borderless`](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/borderless)
  removes peripheral elements and documents the default key/main restriction.
- [`NSWindow` appearance properties](https://developer.apple.com/documentation/appkit/nswindow)
  expose `isOpaque`, `backgroundColor`, and `hasShadow`.

`NSPanel` has a critical default that must be overridden: `hidesOnDeactivate`
defaults to `true` for a panel (and `false` for `NSWindow`). Explicitly set it
to `false`, otherwise the overlay disappears when the user activates the app
under it.

- [`hidesOnDeactivate`](https://developer.apple.com/documentation/appkit/nswindow/hidesondeactivate)

### Spaces, full screen, Stage Manager, and Mission Control

Set the following flags as one `collectionBehavior` option set:

| Flag | Supported effect | Reason for Pointer |
| --- | --- | --- |
| `.canJoinAllSpaces` | The window can appear in all Spaces. | Retain marks while users switch desktop Spaces. |
| `.canJoinAllApplications` | A macOS 13+ window can join other apps' sets and full-screen Spaces when eligible; Apple specifically calls it appropriate for floating windows and system overlays. | The modern full-screen/Stage Manager behavior for this target. |
| `.stationary` | Mission Control leaves the window visible and stationary. | Avoid treating the canvas as an ordinary movable app window. |
| `.ignoresCycle` | Removes a non-normal-level overlay from the normal window-cycle path. | Do not expose a full-screen canvas through Command-Backtick. |
| `.fullScreenAuxiliary` | The window displays in the same Space as a full-screen window. | Keep the legacy/full-screen-specific intent explicit. |

Apple documents mutually exclusive groups. Set **only**
`.canJoinAllApplications` from `{ .primary, .auxiliary,
.canJoinAllApplications }`; do not add `.auxiliary`. Set **only**
`.fullScreenAuxiliary` from `{ .fullScreenPrimary, .fullScreenAuxiliary,
.fullScreenNone }`; do not add `.fullScreenNone`. Also set only one of
`.managed`, `.transient`, and `.stationary`.

- [`NSWindow.CollectionBehavior`](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct)
  lists the flags and their mutually exclusive groups.
- [`canJoinAllSpaces`](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallspaces)
- [`canJoinAllApplications`](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallapplications)
- [`stationary`](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/stationary)
- [`fullScreenAuxiliary`](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/fullscreenauxiliary)

Do **not** use `.moveToActiveSpace`: it moves a window to the active Space
when it becomes active, which conflicts with a persistent, all-Spaces canvas.

### Level and ordering

`NSWindow.Level.screenSaver` is the strongest standard AppKit level exposed for
this purpose. AppKit says higher listed levels are in front of every preceding
level; this puts the canvas above ordinary (`.normal`) and floating windows,
and its level is therefore suitable for the required cross-app overlay test.
`.floating` or `.statusBar` might be less disruptive in manual experiments,
but neither can establish the requested “above ordinary apps and video”
behavior when another app uses a higher public level.

The use is intentionally conservative:

- choose the public `NSWindow.Level.screenSaver`, rather than a magic integer;
- do not equate the name with permission to cover all system UI;
- use `orderFrontRegardless()` only for initial/recovery presentation. Apple
  documents it as moving a window to the front of its *current level* without
  changing key/main status and says it should rarely be needed.

Core Graphics also names standard levels including `overlayWindow`,
`screenSaverWindow`, and system-reserved levels, but its documentation says
applications do not need to use them directly. It does not upgrade the AppKit
contract into a universal z-order promise.

- [`NSWindow.level`](https://developer.apple.com/documentation/appkit/nswindow/level-swift.property)
- [`NSWindow.Level.screenSaver`](https://developer.apple.com/documentation/appkit/nswindow/level-swift.struct/screensaver)
- [`orderFrontRegardless()`](https://developer.apple.com/documentation/appkit/nswindow/orderfrontregardless())
- [`CGWindowLevelKey`](https://developer.apple.com/documentation/coregraphics/cgwindowlevelkey)

### Standby input and activation

For standby, set `panel.ignoresMouseEvents = true`. AppKit defines `true` as
the window being transparent to mouse events, so the underlying application is
the mouse target even though the overlay remains drawn. Switch the property to
`false` only after Pointer's activation mechanism has entered draw/edit mode;
then switch it back before returning to standby. This is a mode transition,
not a partial pass-through mechanism: an overlay window either ignores mouse
events or receives them.

The menu-bar app should use `.accessory` activation policy. It stays out of the
Dock and menu bar while remaining eligible for programmatic activation or a
click on one of its windows. The non-activating panel style then prevents
ordinary canvas clicks from bringing Pointer forward. Do not call the
deprecated “ignoring other apps” activation API merely to maintain standby;
Apple warns that it can steal focus.

For a canvas that needs keyboard editing, subclass the borderless panel to
return `true` from `canBecomeKey`, and make key behavior an explicit edit-mode
choice. `becomesKeyOnlyIfNeeded = true` is useful only if the hit view reports
`needsPanelToBecomeKey`; that gives a non-activating panel precise control over
when it receives keyboard focus. Pointer's shortcut and mode design is a
separate decision, so this report does not select it.

- [`ignoresMouseEvents`](https://developer.apple.com/documentation/appkit/nswindow/ignoresmouseevents)
- [`NSApplication.ActivationPolicy.accessory`](https://developer.apple.com/documentation/appkit/nsapplication/activationpolicy-swift.enum/accessory)
- [`becomesKeyOnlyIfNeeded`](https://developer.apple.com/documentation/appkit/nspanel/becomeskeyonlyifneeded)
- [`needsPanelToBecomeKey`](https://developer.apple.com/documentation/appkit/nsview/needspaneltobecomekey)
- [`activateIgnoringOtherApps`](https://developer.apple.com/documentation/appkit/nsapplication/activationoptions/activateignoringotherapps)

### Displays

Create and maintain one panel for each current member of `NSScreen.screens`,
using that screen's **`frame`** (the complete rectangle, including menu bar and
Dock), not `visibleFrame`. Apple says not to cache the screen array: displays
can be added, removed, or reconfigured at any time, and it posts
`NSApplication.didChangeScreenParametersNotification` when this happens.
Reconcile the panel set there on the main actor.

One panel per display avoids a single canvas being split over screens with
different scale factors and Spaces. It is a design conclusion, not an AppKit
requirement: `NSWindow` can span several screens. Per-screen panels make the
frame, backing scale, lifecycle, and full-screen/Space result independently
testable. Treat mirrored screens and the user’s “Displays have separate
Spaces” setting as explicit test cases.

- [`NSScreen.screens`](https://developer.apple.com/documentation/appkit/nsscreen/screens)
- [`NSScreen.frame`](https://developer.apple.com/documentation/appkit/nsscreen/frame)
- [`NSScreen.backingScaleFactor`](https://developer.apple.com/documentation/appkit/nsscreen/backingscalefactor)
- [`didChangeScreenParametersNotification`](https://developer.apple.com/documentation/appkit/nsapplication/didchangescreenparametersnotification)
- [`NSWindow.deepestScreen`](https://developer.apple.com/documentation/appkit/nswindow/deepestscreen)

## Local prototype required before implementation

Apple’s API documentation establishes that these are public mechanisms and
their intended behaviors. It does not document the exact compositor result for
every external video player, DRM path, display topology, or system overlay.
Build a throwaway panel-only prototype on a macOS 14+ Apple-silicon machine and
record OS build, displays, Space setting, Stage Manager state, and outcome.

| Scenario | Pass condition | Specific uncertainty resolved |
| --- | --- | --- |
| Normal app windows at normal/floating/status levels | Mark remains visible; standby click reaches the app. | Level and `ignoresMouseEvents` behavior. |
| Safari/Chrome/QuickTime local video and full-screen video | Mark remains visible in windowed and full-screen playback; playback controls still work in standby. | Player/compositor behavior. |
| App full screen on every connected display | The corresponding panel appears in the same full-screen Space. | `canJoinAllApplications` plus `fullScreenAuxiliary` on real apps. |
| Mission Control, Space switch, Stage Manager on/off | Marks remain attached to each display without becoming a selectable normal window. | `stationary`, all-Spaces, and Stage Manager interaction. |
| Enter/exit draw mode while another app remains frontmost | Standby clicks pass through; edit clicks draw; no unwanted Dock activation or focus theft; keyboard policy matches the selected mode. | Non-activating/key-window transition. |
| Add, remove, rearrange, mirror, and mix 1x/2x displays; test separate-Spaces both ways | Exactly one correctly framed panel per current display, no stale panel, no scale/frame drift. | Screen reconciliation and topology. |
| Apple TV/protected playback, lock screen, notifications, menu extras, Control Center | Record visibility and never work around a failure with private APIs or raw levels. | Boundary of the public contract. |

If `.screenSaver` causes unacceptable interference with menus, system UI, or
the desired presentation, test `.statusBar` and `.floating` as lower-risk
alternatives, but record the coverage loss rather than assuming equivalence.

## Explicit non-claims

- This does not guarantee drawing above the lock screen, login window, screen
  saver, secure system prompts, assistive-technology UI, or the cursor.
- This does not guarantee visibility over DRM/protected or hardware-overlay
  video. The prototype result is an observed macOS build/player combination,
  not a durable API promise.
- This does not provide global shortcut capture, event tapping, capture,
  accessibility permissions, or palette placement. Those are separate design
  questions.
- This report does not change the ticket status.
