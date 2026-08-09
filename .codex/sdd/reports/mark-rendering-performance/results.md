# Mark-rendering publication-boundary benchmark

## Scope

This is a prototype-only measurement of the shared `CanvasView` gesture
event-handler path. It does not measure drawing or path rebuilds, the grid,
AppKit event dispatch, WindowServer composition, frame rate, application launch,
or multi-display behavior.

The candidate removes the continuation-path `publishState()` call. Gesture
begin and end still publish inspector state, and every continuation still
mutates the model and sets `needsDisplay = true`.

## Conditions

- Measured on August 9, 2026 at 06:28 WEST on `Mac17,9` (`arm64`), macOS 26.6
  (25G72).
- Toolchain: Apple Swift 6.3.3, target `arm64-apple-macosx26.0`, with
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- Both preserved executables were release builds. The candidate was built with
  `swift build -c release --product MarkRenderingPrototype`.
- Fixture: 12 pre-existing basic marks, followed by one freehand gesture with
  240 continuation samples and 241 total points.
- Each run discards five warmup gestures, then measures 30 trials of 20 fresh
  gestures. Whole-gesture and continuation-loop timing scopes are in
  nanoseconds.
- Timed: direct shared `CanvasView` gesture methods plus the real `NSTextView`
  inspector sink. Excluded: drawing, grid drawing, AppKit event dispatch, and
  compositing.

## Preserved artifacts

- Baseline binary: `MarkRenderingPrototype-before`
  (`b2d9a1c198426a48b27213bca7c5c7edc3686854e47acfe92de842332d4303ec`).
- Candidate binary: `MarkRenderingPrototype-after`
  (`246df45e011c2c7a497219448798560cfffb211dc3cd72f6e1c288e06331e73b`).
- Source manifests: `before-source.sha256` and `after-source.sha256`.
- Raw results: `before-a1.json`, `after-b1.json`, `after-b2.json`, and
  `before-a2.json`.

## A-B-B-A results

All values are nanoseconds, rounded to three decimal places from the raw JSON.

| Run | Whole median | Whole p95 | Whole MAD | Continuation median | Continuation p95 | Continuation MAD | Publications/gesture |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| before-a1 | 8,124,683.375 | 8,221,316.600 | 33,748.000 | 8,051,648.000 | 8,147,837.450 | 33,639.675 | 242 |
| after-b1 | 100,006.275 | 109,512.450 | 728.200 | 21,412.500 | 23,000.150 | 181.300 | 2 |
| after-b2 | 100,475.050 | 103,329.200 | 826.100 | 21,323.950 | 22,141.650 | 97.850 | 2 |
| before-a2 | 8,131,204.075 | 8,208,993.750 | 38,958.400 | 8,058,109.450 | 8,133,443.800 | 38,084.275 | 242 |

For each pair, reduction is `before median - after median`; the percentage is
the reduction divided by the corresponding before median.

| Pair | Whole-median reduction | Continuation-median reduction |
| --- | ---: | ---: |
| before-a1 to after-b1 | 8,024,677.100 ns (98.769%) | 8,030,235.500 ns (99.734%) |
| before-a2 to after-b2 | 8,030,729.025 ns (98.764%) | 8,036,785.500 ns (99.735%) |

Both alternating pairs reproduce the improvement. Publication count falls from
242 to 2 per gesture: begin and end only.

## Validity gates

All four runs report 30 trials with finite, positive whole-gesture,
continuation-loop, and per-sample timings. Every baseline trial has a uniform
publication count of 242; every candidate trial has a uniform count of 2.

All four reports have `finalStateValid: true`, model checksum
`09065ce0c629f3d3`, and normalized-inspector checksum
`600d013814a4fcd6`. Therefore, the measured paths preserve the fixture's final
model, final inspector state, and undo restoration while changing publication
frequency.

## Conclusion and remaining work

For this prototype event-handler fixture, removing per-sample inspector
publication accounts for a reproducible reduction in the continuation-loop
median. The measurement supports only that narrow causal conclusion.

Unmeasured residual bottlenecks include rendering and path rebuilds, the grid,
WindowServer composition, array growth and remapping, eraser traversal, and
undo retention.
