# Choose the multi-display overlay architecture

Type: prototype
Status: resolved
Blocked by: 01

## Question

Should Pointer use one presentation overlay and display canvas per physical
display or a single virtual-desktop overlay, and how should it preserve marks
and coordinates as displays, resolutions, and Spaces change?

## Answer

Use one presentation overlay and one display canvas per physical display. A
single virtual-desktop overlay is rejected because independent full-screen
Spaces and topology changes belong to physical displays, while one changing
global frame makes display ownership implicit and forces global coordinate
remapping.

Identify each presentation display with its Core Graphics display UUID and
keep its canvas in an in-memory dictionary. Store mark geometry in normalized
display-local coordinates and project it into the display's current AppKit
frame. Resolution, scale-factor, rotation, or arrangement changes therefore
resize or relocate the overlay without rewriting the marks or moving them to a
different display.

Reconcile overlays whenever screen parameters change:

- update the panel frame for every still-connected display;
- create a panel and empty canvas for a newly seen display;
- close the panel but retain its canvas when a display disconnects; and
- recreate the panel from that retained canvas if the same display reconnects
  during the same app run.

Each display panel joins Spaces independently using the already chosen overlay
contract. Space and application changes never move marks between canvases.
Canvases remain memory-only and are cleared by the presenter or app relaunch;
saved canvases remain outside the MVP.

The approved comparison prototype exercised resolution changes, display
rearrangement, disconnect/reconnect, and Space changes. It showed display-local
normalized marks remaining attached to their display, while the virtual canvas
reprojected marks as its union frame changed.

Prototype asset: [Multi-display overlay architecture](../prototypes/multi-display-overlay/multi-display-overlay.html)
