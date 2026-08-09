# Choose the global-shortcut and permission strategy

Type: research
Status: resolved
Blocked by: none

## Question

Which supported macOS mechanism should Pointer use for configurable global
shortcuts, and which user permissions—if any—are genuinely required for global
activation and annotation without screen capture?

## Answer

Use Carbon Event Manager's public `RegisterEventHotKey` API behind a small
Swift wrapper, with non-exclusive registration and explicit
unregister/re-register behavior when settings change. Store hardware virtual
key codes plus modifiers, handle registration failure without replacing the
last working shortcut, and keep normal menu key equivalents separate.

The MVP should not use a global `NSEvent` monitor or `CGEventTap`. With no raw
keyboard observation, accessibility inspection, input synthesis, or screen
capture, the selected path is expected to require no Accessibility, Input
Monitoring, Screen Recording, or event-posting permission. A local negative
permission test is still required before this becomes a validated product
claim.

The installed Xcode 26.6 SDK independently confirms that
`RegisterEventHotKey` remains declared, available from macOS 10.0, and not
deprecated.

Research asset: [Global-shortcut and permission strategy](../research/global-shortcuts.md)
