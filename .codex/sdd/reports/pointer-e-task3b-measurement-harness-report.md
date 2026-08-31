# Pointer E Task 3b — Measurement Harness

Implemented the measurement-harness foundation in the assigned worktree. This
slice adds the production/default `PerformanceHarness`, an internal injected
adapter bundle for deterministic tests, and focused contract coverage. It does
not implement the comparison harness, CLI, benchmark scripts, or paired
execution protocol.

## Implemented

- `PerformanceHarness.run(configuration:buildProvenance:runProvenance:)`
  assembles one typed `.measurement` report, propagates the configuration and
  both provenance envelopes, derives one immutable source identity, validates
  the complete report structure, and chooses `.acceptedNoRegression`,
  `.revise`, or `.blocked` from adapter status/evidence.
- Specialized adapters cover model, renderer, compositor, combined frame,
  launch, allocations, redraw/layout, responsiveness, input-to-visible,
  memory, and resilience. The internal bundle permits each production path to
  be replaced by an explicit test adapter without synthesizing input or
  bypassing the application model.
- `GestureBenchmarkInstrumentationAdapter` drives the existing production
  `PointerSession` benchmark and maps its trial statistics and final-state
  evidence into `ModelMeasurement`. It reports `.measured` only when the
  checksum is stable, final state is valid, and exactly one publication entry
  of `2` exists for every configured trial; otherwise it preserves the
  diagnostic fields and reports `.failed`.
- `OffscreenCanvasRendererAdapter` measures the real `CanvasView` draw path
  into a private 512×512 RGBA CGContext. It does not order a window front,
  install monitors, dispatch synthetic events, or capture the screen.
  Each warmup is discarded and each measured trial is persisted as a positive
  raw `frameMilliseconds` sample; p95 is recomputed from that exact array.
- All measured frame, redraw/layout, responsiveness, and input-to-visible
  adapters must persist exactly `trialCount` positive raw samples with p95
  derived from those samples. Failed and unavailable adapters retain empty raw
  arrays, as required by the report validator.
- The public full-quality run rejects any nonstandard `PerformanceConfiguration`
  before invoking fixed campaign adapters. Diagnostic schema fixtures may still
  be nonstandard, but cannot be presented as authoritative harness output.
- `SignpostWindowServerAdapter` and the default process/physical/resource
  adapters fail closed as `.unmeasured` with explicit instrumentation status
  where this in-process foundation cannot observe the host metric. No zero is
  promoted to a measured value.
- The memory adapter contract remains schema-owned: a measured adapter must
  return the complete 600-second/5-second series (121 running samples followed
  by stopping, stopped, and restarted checkpoints), and the report validator
  rejects incomplete cadence/checkpoints.

## Verification

From `/Users/bruno/Dev/pointer/.worktrees/stable-app`:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PerformanceHarnessTests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build
git diff --check
```

Result: 30 tests passed. This includes measured injected-adapter propagation,
raw-array and p95 alignment, model checksum/publication/final-state gates,
failed and unavailable adapter dispositions, configuration mismatch rejection,
nonstandard public-run rejection, real offscreen renderer coverage, and the
existing complete schema/memory validation suite.

The shared suite contains 406 tests; the full run passed with zero failures.
The build and `git diff --check` also passed.

## Measured versus deferred

The default harness measures model and offscreen renderer work now. Compositor
timing, launch timing, allocation bytes, redraw/layout counters,
responsiveness, physical input-to-visible latency, process RSS/resource
sampling, and resilience lifecycle cases remain explicitly unmeasured until
the host/launcher and accepted F/A-harness instrumentation exist. Those
statuses intentionally produce a blocked diagnostic report and cannot satisfy
`validateCompletion()`.

F tasks 1–3 must provide the executable composition, Release bundle/resource
foundation, and launcher/provenance path before E can run an authoritative
paired baseline/candidate measurement. E comparison/CLI work remains outside
this slice.
