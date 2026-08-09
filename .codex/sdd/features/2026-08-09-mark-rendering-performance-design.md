# Mark-Rendering Prototype Performance Design

**Status:** Approved for implementation on 2026-08-09

**Scope:** The throwaway `MarkRenderingPrototype` only. This workspace has no production Pointer target, so benchmark results must be described as prototype event-handler measurements, never as production application, rendering, frame-rate, compositor, launch, or multi-display performance.

## Goal

Establish a deterministic release-mode benchmark for the prototype's real freehand gesture path, prove whether per-sample inspector publication is the dominant measured cost, remove that cost from drag samples while preserving final state and undo behavior, and report repeatable before-and-after results.

## Evidence and bottleneck hypothesis

Every `mouseDragged` event currently mutates the active mark, calls `publishState()`, and invalidates the view. `publishState()` serializes every mark, while a freehand mark recomputes its bounds by reducing every point. A growing freehand stroke therefore performs cumulative quadratic diagnostic work across its samples. Rendering also remains linear in all marks and points, but this design deliberately measures only the event-handler path because the prototype has no production renderer or compositor benchmark.

The hypothesis is: **whole-state inspector serialization and synchronous `NSTextView.string` assignment on every drag sample dominate the measured freehand event-handler cost.** The benchmark must confirm or reject that hypothesis before the behavior change is accepted.

## Chosen approach

Extract the existing point-based logic from `mouseDown`, `mouseDragged`, and `mouseUp` into internal `CanvasView` methods:

```swift
func beginGesture(at point: NSPoint)
func continueGesture(to point: NSPoint)
func endGesture()
```

The AppKit overrides will only translate events into view coordinates and call those methods. Tests and the headless benchmark will call the same methods, so no gesture logic is copied or simulated through accessibility or synthetic GUI events.

The optimized contract publishes inspector state at gesture boundaries, not on every continuation sample. `continueGesture(to:)` must still perform the same geometry mutation and set `needsDisplay = true`. `endGesture()` must publish the complete final inspector state. Tool changes, opacity changes, selection, erase, move, resize, and undo behavior remain unchanged.

Alternatives rejected:

- Caching freehand bounds retains synchronous all-mark inspector publication and adds model invalidation complexity without addressing the proven boundary cost.
- Path and dirty-region caching require a real renderer/compositor benchmark and a wider rendering redesign; the current headless evidence cannot validate them.

## Benchmark contract

Add a headless benchmark mode to `MarkRenderingPrototype`. It must create the minimum AppKit objects required by the real code, attach a real `NSTextView` sink through `onStateChange`, execute before any window is created or `app.run()` is entered, print machine-readable results, and exit.

The deterministic fixture contains 12 fixed existing basic marks plus one freehand gesture with 240 continuation samples (241 points including the start). The benchmark uses five discarded warmup gestures, then 30 measured trials with 20 fresh gestures per trial in a release build.

Two scopes are timed:

1. Whole gesture: `beginGesture` + all 240 `continueGesture` calls + `endGesture`.
2. Continuation loop: the 240 `continueGesture` calls alone.

Fixture construction, point generation, statistics, JSON formatting, grid drawing, AppKit event dispatch, actual `draw(_:)` execution, and WindowServer composition are outside the timed scopes. `needsDisplay = true` remains inside the real continuation path.

Each result records the fixture identifier, build configuration, warmups, trials, gestures per trial, samples per gesture, whole-gesture time, continuation-loop time, nanoseconds per drag sample, publication count, model checksum, inspector checksum, and explicit false flags for render, grid, and event-dispatch timing. The checksums are consumed after timing so the release optimizer cannot remove the measured work.

Report median, p95, and median absolute deviation for both timing scopes. Preserve raw trial output for the baseline and optimized candidate. The same release toolchain and host conditions must be used for both runs.

## Test-first behavior contract

Add a SwiftPM test target that imports the executable target with `@testable`. Before changing publication behavior, add a failing main-actor test that drives one three-point freehand gesture through the shared methods and proves the desired contract:

- no inspector publication occurs during the two continuation calls;
- the completed gesture publishes the final inspector state;
- final state contains one freehand mark with three points and the expected bounds;
- each continuation still invalidates drawing;
- undo restores the pre-gesture canvas with one undo action.

The test must be observed failing against the baseline specifically because continuation samples still publish inspector state. After the one-line root-cause change, the focused test and full test suite must pass.

## Success criteria

- The release benchmark exercises the same `CanvasView` gesture methods used by AppKit event handling.
- Baseline evidence shows 242 publications for the 240-sample fixture; optimized evidence shows two boundary publications while final model and inspector checksums remain equivalent.
- The optimized continuation-loop median improves materially and the direction is reproduced in a second clean run; exact gains are reported from measurements, not projected.
- Final geometry, redraw invalidation, inspector state, and undo behavior pass focused automated tests.
- A fresh release build and full Swift test run exit successfully.
- An independent Terra-max review finds no important correctness, scope, or benchmark-validity defect.

## Explicit residual risks

The optimization does not measure or improve path rebuilding, grid drawing, WindowServer composition, multi-display transparent panels, freehand array growth, freehand move/resize remapping, eraser traversal, or unbounded undo retention. These remain separate bottleneck candidates for a future production target and must not be folded into this prototype-only result.
