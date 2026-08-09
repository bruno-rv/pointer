# Prove the full-screen overlay contract

Type: research
Status: resolved
Blocked by: none

## Question

Which supported AppKit window, collection-behavior, activation, and window-level
configuration can keep a transparent Pointer overlay available on every display
above normal applications, full-screen Spaces, and playing video while allowing
underlying applications to receive input in standby mode?

## Answer

Use one transparent, borderless, non-activating `NSPanel` per `NSScreen`.
Explicitly disable `hidesOnDeactivate`, start with the public `.screenSaver`
window level, and combine `.canJoinAllSpaces`, `.canJoinAllApplications`,
`.stationary`, `.ignoresCycle`, and `.fullScreenAuxiliary`. Standby sets
`ignoresMouseEvents` to `true`; annotation mode sets it to `false`.

This is a supported public-API composition for macOS 14+, but it is not a
universal guarantee over DRM/protected video, secure system UI, or future
WindowServer policy. Full-screen applications, representative video players,
Spaces, Stage Manager, and mixed-display topologies must therefore be verified
by the overlay prototype before implementation relies on the contract.

The installed Xcode 26.6 SDK independently confirms the collection-behavior
semantics and that `.canJoinAllApplications` is available from macOS 13.

Research asset: [Full-screen overlay contract](../research/overlay-contract.md)
