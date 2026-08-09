# Prove palette placement across displays and Spaces

Type: prototype
Status: resolved
Blocked by: 04

## Question

What palette window behavior lets Pointer open controls on the display
containing the pointer, move the palette manually, reactivate it from the
main-display menu bar, and keep annotation available on every other display
without disrupting a presentation?

## Answer

Use one compact, draggable, nonactivating palette panel, separate from the
per-display annotation overlays. Whenever the presenter explicitly shows the
palette, place it near the top center of the visible frame of the display that
currently contains the pointer and clamp it within that display. While it is
visible, allow the presenter to drag it freely to any connected display.

Keep a status item on the primary menu bar. Hiding or closing the palette hides
only that panel; it must not remove, move, or disable the annotation overlays.
Selecting **Show Palette** from the status item reopens the same palette using
the pointer-on-show rule, so activation from the primary display does not
restrict annotation to that display.

Create and reconcile one click-through overlay panel for every connected
display independently of the palette. A palette move never changes overlay or
canvas ownership. If the display holding the palette disconnects, reopen the
palette on the display containing the pointer while retaining the separate
display-canvas behavior already chosen by the multi-display architecture.

The approved native prototype validated this behavior with an external display
and the built-in Retina display in extended mode. The palette followed the
pointer in both directions, accepted a manual cross-display drag, and reopened
from the primary menu-bar item. Each display accepted its own test mark while
both overlays remained present. With a host window confirmed as a native
full-screen Space, the palette and both overlays remained on screen at the
chosen top window level. The user approved the behavior on 2026-08-08.

Prototype asset: [Palette placement prototype](../prototypes/palette-placement/README.md)
