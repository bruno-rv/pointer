# Pointer MVP

Label: wayfinder:map

## Destination

A native macOS 14+ Apple Silicon menu-bar application that can annotate any
connected display above normal, full-screen, and video applications, delivered
as a locally built and tested MVP with current validation evidence.

## Notes

- This map continues through specification into implementation and tests once
  its decisions make the route clear.
- Use native macOS capabilities and keep the first version locally buildable.
- The overlay is transparent, always on top, and available on every connected
  display.
- The palette opens on the display containing the pointer and can be moved.
- First-version marks are arrows, rectangles, ellipses, freehand strokes, emoji
  stamps, and spotlights. Screenshot capture is not required.
- Marks have adjustable opacity. Spotlight size and dimness are separate
  controls.
- Finished marks can be selected, moved, resized, or deleted, but not rotated.
- The eraser removes marks directly by clicking or dragging across them; one
  undo restores the marks removed by an eraser gesture.
- The emoji tool offers a compact preset picker and stamps the chosen emoji;
  emoji marks support the same opacity and edit operations as other marks.
- Marks persist across mode, application, and Space changes until cleared.
- Consult `wayfinder`, `domain-modeling`, `coding-guidelines`,
  `superpowers:test-driven-development`, and
  `superpowers:verification-before-completion` as applicable.

## Decisions so far

- [Prove the full-screen overlay contract](issues/01-prove-full-screen-overlay-contract.md)
  — Use one public-API, transparent non-activating panel per display, with
  full-screen coverage qualified by mandatory local compositor testing.
- [Choose the global-shortcut and permission strategy](issues/02-choose-global-shortcut-strategy.md)
  — Use non-exclusive `RegisterEventHotKey`; avoid raw event monitoring and
  validate that the MVP requests no privacy permissions.
- [Choose the mark rendering and edit model](issues/03-choose-mark-rendering-and-edit-model.md)
  — Use direct AppKit drawing over ordered value-type marks with stable IDs,
  transient edit gestures, and one value snapshot per undoable gesture.
- [Choose the multi-display overlay architecture](issues/04-choose-multi-display-overlay-architecture.md)
  — Use one overlay and normalized in-memory canvas per physical display,
  retaining its canvas across temporary disconnects during the same app run.
- [Prove palette placement across displays and Spaces](issues/05-prove-palette-placement-across-displays.md)
  — Show one draggable palette on the pointer display while independent,
  click-through annotation overlays remain available on every display.
- [Lock the MVP interaction specification](issues/06-lock-the-mvp-interaction-specification.md)
  — Use the approved production interaction, failure, build, and validation
  contract in the stable source-build design.

## Not yet specified

- The implementation sequence, which will be derived when the decision
  frontier closes.

## Out of scope

- Screenshot capture, export, saved canvases, and text annotations.
- Rotating completed marks.
- Intel Mac support for the first version.
- Developer ID signing, notarization, automatic updates, and downloadable app
  distribution.
