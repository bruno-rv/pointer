# Global-shortcut and permission strategy

**Decision — use Carbon Event Manager's `RegisterEventHotKey` for Pointer's
configurable, application-wide shortcuts.**  Keep a small Swift/AppKit wrapper
around the public C API; do not use a global `NSEvent` monitor or a
`CGEventTap` for the MVP.  The registration API is the supported public SDK
mechanism whose contract is specifically to register a *global hot key*, rather
than to observe the user's ordinary keystrokes.  It matches Pointer's need to
activate its own UI, and avoids asking for keyboard-observation privileges.

The current SDK evidence is particularly strong: the installed Apple macOS SDK
declares `RegisterEventHotKey` as available on macOS from 10.0, with no
deprecation attribute, and describes it as registering a global virtual-key
code/modifier combination.  Its source also says that an `EventHotKeyID` is
delivered in `kEventHotKeyPressed`, and that `UnregisterEventHotKey` is the
intended operation when the user changes a shortcut.  See
`Carbon.framework/.../HIToolbox.framework/Headers/CarbonEvents.h`, lines
15428–15511, in the local Xcode/CLT SDK.  (Apple no longer hosts a current
DocC reference page for this legacy-but-exported API, so the SDK header is the
authoritative contract.)

## Recommended implementation boundary

1. Store each configured shortcut as a **hardware virtual key code plus
   Carbon modifier flags**, not a rendered character.  Register it with
   `RegisterEventHotKey(..., GetApplicationEventTarget(),
   kEventHotKeyNoOptions, ...)`; install one application event handler for
   `kEventClassKeyboard` / `kEventHotKeyPressed`, extract the `EventHotKeyID`,
   and dispatch its action to the main actor.
2. On a settings change, validate the candidate, unregister the previous
   `EventHotKeyRef`, attempt the new registration, and retain the new ref only
   on success.  If it fails, restore the previous working registration and
   show the failure rather than persisting a dead shortcut.  Capture the
   candidate in Pointer's *own* settings UI using normal AppKit events; that is
   not global input monitoring.
3. Use non-exclusive registration (`kEventHotKeyNoOptions`) initially.  The
   header explicitly says ordinary registrations may notify more than one
   process.  `kEventHotKeyExclusive` only rejects another **exclusive**
   registration; it is not a reliable system-wide conflict detector and would
   make Pointer unnecessarily grabby.  Treat a successful registration as
   “Pointer will be notified”, not as proof that no other app or reserved
   system behavior also uses the chord.
4. In the handler, activate/order Pointer's palette and overlay; draw and
   receive pointer events in Pointer-owned windows/views.  No API needs to
   inspect another app's accessibility tree, inject an event, or read a display
   to perform that action.

`RegisterEventHotKey` is a C API, but that is a small interoperability surface
in an otherwise native Swift/AppKit app.  A third-party shortcut package would
not improve the platform/privacy contract; it would merely hide the same
choice (or, worse, select an event tap).  Keep the wrapper in-house and test
it directly.

## Native alternatives considered

| Mechanism | Fit for Pointer | Privacy / behavioral consequence | Decision |
| --- | --- | --- | --- |
| **Carbon `RegisterEventHotKey`** | Registers one configured chord directly with the system and delivers a hot-key event to Pointer even when it is not frontmost.  Supports re-registration on settings changes. | The public header describes a registration, not raw keyboard observation, and exposes no TCC preflight/request API.  It therefore needs no Accessibility, event-listening/Input Monitoring, or Screen Recording request for this use.  Collision and OS-reserved-chord behavior still need real-machine testing. | **Use.** |
| AppKit `NSEvent.addGlobalMonitorForEvents` | Can notice matching events sent to other apps, but is not a hot-key registration.  It cannot see events sent to Pointer, so a complete implementation needs a paired local monitor. | Apple says delivery is asynchronous, observation-only, and cannot prevent delivery to the original app.  Crucially, **key-related events require Accessibility to be enabled or the app to be a trusted accessibility client**. | Do not use for activation.  It creates an unnecessary privacy prompt and lets the foreground app also act on the chord. |
| Quartz `CGEventTapCreate` | Can pass, change, or discard low-level events, so it is useful only if Pointer someday must implement a key filter rather than a shortcut. | The current `CGEvent.h` says key-up/down delivery requires assistive-device / trusted-accessibility access; it also exposes `CGPreflightListenEventAccess` and `CGRequestListenEventAccess` for event listening, plus separate post/synthesis access APIs.  HID-level taps are root-only. | Do not use for the MVP; it has broader privacy and reliability implications than a registered shortcut. |
| AppKit/SwiftUI menu key equivalents | Correct for Pointer commands while Pointer is active. | They are responder/menu command shortcuts, not system registration. | Use only as local equivalents if useful; not a replacement for global activation. |

Apple's `NSEvent` documentation is explicit about the monitor's observation
semantics and Accessibility requirement.  The current Core Graphics SDK header
is explicit about event-tap filtering, the trusted-accessibility condition for
key events, and the separate listening/posting authorization checks.  These
are materially different capabilities from a registered hot key.

## Permission answer for the MVP

| User-controlled permission | Required for proposed global activation and Pointer-only annotation? | Why |
| --- | --- | --- |
| **Accessibility** | **No.** | Pointer does not use `AXUIElement`, a global AppKit key monitor, or a key event tap.  Its own overlay window receives its own drawing clicks.  `AXIsProcessTrusted` is relevant only if a later feature controls or inspects another process, or if the team switches to the monitor/tap alternatives. |
| **Input Monitoring / event-listening access** | **No.** | Pointer registers a discrete system hot key instead of listening to the keyboard stream.  Do not call `CGPreflightListenEventAccess` or `CGRequestListenEventAccess` in the MVP.  They belong to the rejected raw-event strategy. |
| **Screen Recording** | **No.** | The MVP draws a transparent local overlay and deliberately does not capture displays, windows, or audio.  Apple requires Screen Recording permission when using ScreenCaptureKit to capture content; the proposed path uses none of that API surface and must not add `NSScreenCaptureUsageDescription` or request capture access. |
| **Post/synthesize-input access** | **No.** | Drawing is handled by Pointer's view.  Do not use `CGEventPost`, `AXUIElementPostKeyboardEvent`, or the `CGRequestPostEventAccess` path. |

This is a statement about the stated MVP path, not a claim that annotation can
never need privacy access.  If product requirements change to observe other
apps, manipulate their UI, inject clicks/keys, or capture a display, introduce
the corresponding permission as a separate, just-in-time feature decision.

## Sandbox and Mac App Store relevance

The map explicitly makes signing and public distribution out of scope, so the
locally built MVP should not be delayed by App Store policy work.  Still, this
choice keeps that future door less constrained: Apple says App Sandbox is
required for Mac App Store distribution and lists **use of accessibility APIs
in assistive apps** among activities incompatible with App Sandbox.  The
recommended hot-key path deliberately avoids that listed activity.  Apple does
not list `RegisterEventHotKey` there, but that absence is not a substitute for
a sandboxed-build test; do not promise Mac App Store compatibility until that
test has passed.

## Local prototype required before the ticket can close

Build the thinnest unsigned/local macOS 14+ test app (and later repeat in a
sandboxed target if distribution becomes in scope) with no ScreenCaptureKit,
AX, `NSEvent.addGlobalMonitorForEvents`, or `CGEventTapCreate` calls.  It must
record the OSStatus from registration and received hot-key events.

- **Activation:** with another app focused, register/unregister/re-register a
  default and a user-picked chord; verify Pointer receives the event and can
  show/hide its palette/overlays.  Repeat after application relaunch.
- **Permission audit:** begin with Accessibility, Input Monitoring, and Screen
  Recording denied.  Verify no consent sheet or System Settings entry is
  requested/created while registration, activation, and drawing work.  This
  validates the important negative claim against the actual target OS.
- **Chord policy:** try commonly reserved system chords, an already-used app
  chord, and modifier-only / Option–Shift combinations.  Record both returned
  status and observed delivery.  An Apple Frameworks engineer documented a
  Sequoia restriction affecting Option–Shift registrations in early 15.x and a
  later 15.2-beta correction; Pointer supports macOS 14+, so the settings UI
  needs a real failure state rather than assuming every representable chord is
  usable.
- **Input continuity:** once annotation mode is active, verify Pointer's own
  canvas receives drag/up events and that toggling it off returns input to the
  prior app.  This confirms that drawing needs only Pointer's windows, not
  accessibility control or event injection.
- **Future sandbox check (conditional):** enable App Sandbox, run the same
  test, and inspect entitlements before making any Mac App Store claim.

## Sources

- Apple SDK source, locally installed:
  [`CarbonEvents.h`](/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks/Carbon.framework/Versions/A/Frameworks/HIToolbox.framework/Versions/A/Headers/CarbonEvents.h:15428)
  and
  [`CarbonEventsCore.h`](/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks/Carbon.framework/Versions/A/Frameworks/HIToolbox.framework/Versions/A/Headers/CarbonEventsCore.h:144).
  These declare `RegisterEventHotKey`, its global-registration and
  collision/exclusivity semantics, and `UnregisterEventHotKey`.
- Apple SDK source, locally installed:
  [`CGEvent.h`](/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks/CoreGraphics.framework/Versions/A/Headers/CGEvent.h:247):
  event-tap placement/filtering rules and listening/posting access functions.
- [Apple: `NSEvent.addGlobalMonitorForEvents`](https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents%28matching%3Ahandler%3A%29): asynchronous, observation-only delivery and the Accessibility condition for key events.
- [Apple: `AXIsProcessTrusted`](https://developer.apple.com/documentation/applicationservices/1460720-axisprocesstrusted): the trusted-accessibility-client check.
- [Apple: ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit): screen recording permission and `NSScreenCaptureUsageDescription` are for capturing content.
- [Apple: Protecting user data with App Sandbox](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox): App Sandbox is required for Mac App Store distribution and lists assistive-app accessibility APIs as incompatible.
- [Apple Frameworks Engineer: Sequoia `RegisterEventHotKey` modifier behavior](https://developer.apple.com/forums/thread/763878): documented 15.x compatibility caveat for Option–Shift registrations and follow-up change.

*Research snapshot: 2026-08-06.  Local SDK inspected: Command Line Tools
`MacOSX.sdk`; host was macOS 26.6, so the required macOS 14/15 behavior remains
a prototype-validation item rather than a host-only conclusion.*
