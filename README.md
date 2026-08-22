# Pointer

Pointer is a native macOS presentation-annotation app. It provides a floating
palette and one transparent, always-on-top annotation overlay per connected
display, while keeping standby mode click-through for the application behind it.

## Quick start

On an Apple silicon Mac with macOS 14 or later and Xcode 15.4 or later, run
this from the repository root:

```sh
./scripts/run-app.sh
```

The script builds a Release SwiftPM executable, creates and ad-hoc-signs
`build/Pointer.app`, and opens that bundle. No package manager, developer
account, secret, or machine-specific project file is required.

## Controls

Pointer starts in standby. The palette remains available, and overlays ignore
mouse events so another app stays usable. The default global shortcut is
Control-Option-Command-P:

- Press the shortcut to toggle annotation and standby.
- Choose Select, Arrow, Rectangle, Ellipse, Pen, Eraser, Emoji, or Spotlight
  from the palette. Choosing an annotation tool enters annotation mode.
- Press Escape to return to standby without clearing marks.
- Use the menu-bar item to show the palette, enter or leave annotation mode,
  choose the alternate Control-Option-Command-O shortcut, clear all displays,
  undo, or quit.

The shortcut registration is non-exclusive. If a candidate is unavailable or
its delivery test times out, Pointer restores the previous working shortcut and
the menu-bar controls remain usable as a fallback. The current session keeps
display-local canvases through mode changes, Space changes, and temporary
display disconnects; canvases are not saved after the process exits.

## Verification

Run the same source-built gate used by CI:

```sh
./scripts/verify.sh
```

The gate runs the Swift test suite, builds and ad-hoc-signs the Release app
bundle, checks its property list and arm64 executable, and exercises the
non-interactive smoke report. It does not claim that a hosted runner has a
usable interactive desktop.

## Gesture benchmark

Run the production-model benchmark after a Release build:

```sh
./scripts/benchmark-gestures.sh
```

The benchmark drives `PointerSession.beginGesture`, `advanceGesture`, and
`commitGesture` directly. Each measured gesture starts with 12 existing marks
and adds a pen stroke with 240 continuation samples. It discards five warmups,
measures 30 trials, reports median, p95, and median absolute deviation in
nanoseconds, and requires a stable literal model checksum plus exactly two
boundary publications (begin and commit). The timed scope is the gesture model
path only; rendering, compositing, AppKit event dispatch, launch, and
multi-display performance are explicitly not measured.

## Support and verification environments

These terms describe different things:

| Environment | Contract |
| --- | --- |
| Deployment target | macOS 14 or later, Apple silicon, as declared by `Package.swift`. |
| CI images | `macos-15` is the durable public arm64 lane. `macos-14` is a temporary compatibility lane while public; GitHub's announced retirement deadline is 2026-11-02. Both assert `uname -m` is `arm64`. |
| Observed physical host | Manual checks are reported with the exact macOS, Xcode, architecture, and connected displays in [validation.md](.codex/sdd/reports/stable-source-build/validation.md). They are evidence for that host and date, not a claim that every display or privacy configuration has been tested. |

## Project evidence and boundaries

The production package is split into AppKit-free `PointerCore`, AppKit
coordination and rendering in `PointerAppKit`, and the minimal `Pointer`
launcher. The domain vocabulary is in [CONTEXT.md](CONTEXT.md), and the
decision map is retained in `.scratch/pointer-mvp/map.md`.

The disposable prototype investigations remain useful evidence but are not
production dependencies:

- [Mark rendering](.scratch/pointer-mvp/prototypes/mark-rendering/README.md)
  explores drawing, selection, editing, erasing, emoji stamps, opacity, undo,
  and clear.
- [Palette placement](.scratch/pointer-mvp/prototypes/palette-placement/README.md)
  explores one overlay per display and a draggable palette that follows the
  pointer display.
- [Global shortcut](.scratch/pointer-mvp/prototypes/global-shortcut/README.md)
  records local Carbon registration, delivery diagnostics, persistence, and
  rollback observations.

This source-build milestone deliberately excludes saved canvases, screenshots,
exports, text annotations, mark rotation, Intel support, Developer ID signing,
notarization, disk images, installers, automatic updates, and downloadable
releases. Pointer cannot guarantee overlays over DRM-protected video, secure
system UI, the lock screen, or future WindowServer policy. Physical multi-
display, Spaces/full-screen, reconnect, shortcut-conflict, accessibility, TCC,
and visual-interaction evidence is tracked candidly in the validation report;
unchecked cases are not implied passes.
