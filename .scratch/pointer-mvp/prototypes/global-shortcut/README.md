# Global Shortcut Prototype

> PROTOTYPE — throwaway AppKit/Carbon code used to validate Pointer's global
> shortcut contract. It is not production application code.

This native harness answers a platform-runtime question that a browser logic
demo cannot: does `RegisterEventHotKey` deliver configurable shortcuts from
other applications, preserve the last working shortcut across relaunches, and
fail visibly without requiring privacy permissions?

Run it:

```sh
cd /Users/bruno/Dev/pointer/.scratch/pointer-mvp/prototypes/global-shortcut
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run GlobalShortcutPrototype
```

The diagnostics window exposes the full registration and delivery state after
every action. Apply a candidate, start the five-second delivery test, focus a
different application, and press the displayed chord. A delivered chord
toggles the small proof palette. A registration error or delivery timeout is
reported without replacing the previous working shortcut.

The prototype deliberately contains no global AppKit event monitor, Quartz
event tap, accessibility operation, input synthesis, or screen-capture API.
Its preferences suite is
`dev.pointer.global-shortcut-prototype.PROTOTYPE-WIPE-ME` because relaunch
persistence is part of the question being tested.

## Observed local results

Host: Apple Silicon, macOS 26.6 (25G72), Xcode 26.6 SDK.

- The default `⌃⌥⌘P` chord registered with `OSStatus 0` and a physical
  keypress from another application delivered a counted Carbon event.
- Changing to `⌃⌥⌘O` unregistered and replaced the active chord; the saved
  chord was restored and registered with `OSStatus 0` after process relaunch.
- A modifier-only candidate was rejected as `eventHotKeyInvalidErr` (`-9879`)
  while the previous working registration and persisted setting remained.
- `⌘Space` registered and delivered even though Spotlight also uses it. This
  confirms that non-exclusive registration success is not a uniqueness check.
- With a separate process holding `⌃⌥⌘O` exclusively, Pointer's non-exclusive
  registration still returned success but the five-second verifier reported no
  delivery. Delivery resumed as soon as the exclusive process exited.
- The Option–Shift compatibility probe `⌥⇧P` registered and delivered on this
  host. macOS 14 and 15 still require their own compatibility runs before the
  app can claim validation across the entire supported range.
- The linked binary imports `RegisterEventHotKey`, `UnregisterEventHotKey`, and
  `InstallEventHandler`, but none of the rejected monitoring, accessibility,
  input-synthesis, or screen-capture APIs. No matching TCC activity appeared in
  the system log and no privacy prompt appeared during the run.
