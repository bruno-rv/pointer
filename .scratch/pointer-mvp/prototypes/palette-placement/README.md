# Palette Placement Prototype

> PROTOTYPE — throwaway AppKit code used to choose Pointer's palette window
> behavior. It is not production application code.

Run it:

```sh
cd /Users/bruno/Dev/pointer/.scratch/pointer-mvp/prototypes/palette-placement
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run PalettePlacementPrototype
```

The menu-bar item can show the palette from any application. The palette
compares three placement policies: follow the pointer whenever shown, remember
the last dragged position, or anchor to the main display. Diagnostic overlay
borders remain on every connected display and never intercept the mouse.

Use **Add mark at pointer** to prove that annotation availability follows the
pointer independently of the palette. The state inspector reports the pointer
display, palette display, overlay count, and test marks after every action.
