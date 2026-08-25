# Pointer

Pointer is an experimental native macOS project for drawing attention to
content during presentations. The intended app places transparent,
always-on-top annotation layers over normal, full-screen, and video apps on
every connected display.

> [!IMPORTANT]
> This repository is an MVP research and prototype workspace. It does not yet
> contain an installable Pointer application.

## Product direction

The first locally built MVP targets macOS 14 or later on Apple silicon. Its
planned interaction model includes:

- A compact palette that opens on the display containing the pointer.
- An independent, click-through annotation canvas on each physical display.
- Arrows, rectangles, ellipses, freehand strokes, emoji stamps, and a
  spotlight.
- Selection, movement, resizing, deletion, erasing, opacity, undo, and clear.
- A global shortcut for showing Pointer's controls. The exact mode-switching
  behavior remains to be specified.

See the [Pointer domain language](CONTEXT.md) and
[MVP decision map](.scratch/pointer-mvp/map.md) for the current specification.

## Prototype evidence

The repository keeps platform investigations isolated in disposable harnesses:

- [Mark rendering](.scratch/pointer-mvp/prototypes/mark-rendering/README.md)
  exercises drawing, selection, editing, erasing, emoji stamps, opacity, undo,
  and clear with an in-memory AppKit model.
- [Palette placement](.scratch/pointer-mvp/prototypes/palette-placement/README.md)
  exercises one overlay per display and a draggable palette that follows the
  pointer display.
- [Global shortcut](.scratch/pointer-mvp/prototypes/global-shortcut/README.md)
  records local macOS 26.6 observations for Carbon hotkey registration,
  delivery diagnostics, persistence, and rollback when a candidate shortcut
  is invalid. Its supported-range contract remains pending.

These harnesses provide local evidence for individual contracts. They are not
production components or a unified application.

## Run the mark-rendering prototype

Install Xcode, then run the prototype from the repository root:

```sh
cd .scratch/pointer-mvp/prototypes/mark-rendering
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift run MarkRenderingPrototype
```

Run its test suite from the same directory:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

The other prototype guides contain their own run instructions.

## Known boundaries

- The repository has no production target, installer, signing, notarization,
  automatic updates, or public distribution workflow.
- Saved canvases, screenshots, exports, text annotations, and mark rotation are
  outside the first MVP.
- Overlay behavior cannot guarantee coverage over DRM-protected video, secure
  system UI, the lock screen, or future WindowServer policy.
- The shortcut harness has observed results on macOS 26.6. macOS 14 and 15
  still require compatibility runs before the project can claim support across
  the full target range.
- The checked-in
  [mark-rendering benchmark](.codex/sdd/reports/mark-rendering-performance/results.md)
  measures only the gesture-handler and inspector-publication path. It does not
  measure drawing, frame rate, compositing, launch time, or multi-display
  performance.
