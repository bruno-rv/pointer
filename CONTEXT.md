# Pointer Domain Language

## Presentation Overlay

A transparent visual layer that remains above the applications being presented,
including full-screen applications and video.

## Annotation Mode

The state in which Pointer accepts presenter input to create and manipulate
marks on a presentation overlay.

## Standby Mode

The state in which Pointer remains available but does not intercept interaction
with the application underneath the presentation overlay.

## Mark

A visual item placed by the presenter to direct attention. The first version
supports arrows, rectangles, ellipses, freehand strokes, emoji stamps, and
spotlights.

## Tool Palette

The compact presenter control that appears on the display containing the
pointer. It provides access to annotation tools and their controls.

## Presentation Display

Any connected display on which the presenter can create or manipulate marks.
The menu-bar control may remain on the main display while presentation work
takes place on another display.

## Display Canvas

The collection of marks associated with one physical presentation display.
Marks remain on that display when Pointer enters standby mode or the presented
application changes, until the presenter clears them. If that display
temporarily disconnects, its canvas remains available during the same app run
and returns when the same display reconnects; it never migrates to another
display.

## Selection Tool

The tool used to choose, move, resize, or delete an existing mark. Rotation is
not part of the first version.

## Eraser Tool

The tool used to remove marks directly by clicking or dragging across them,
without selecting them first.

## Emoji Tool

The tool used to choose a common emoji and stamp it onto the presentation
display. Emoji stamps can be selected, moved, resized, deleted, and faded like
other marks.

## Spotlight

A movable circular focus area that leaves its subject visible while dimming the
rest of the presentation display. Its size and surrounding dimness are
presenter-adjustable.
