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
  the complete report structure, and chooses `.acceptedNoRegression` or
  `.revise` from adapter status/evidence. It accepts exactly the schema-owned
  `PerformanceConfiguration.standard12` and `.dense1000` profiles; arbitrary
  configurations fail closed before fixed campaign adapters run. `.blocked`
  remains reserved for a future explicit external-authority state.
- Specialized adapters cover model, renderer, compositor, combined frame,
  launch, allocations, redraw/layout, responsiveness, input-to-visible,
  memory, and resilience. The internal bundle permits each production path to
  be replaced by an explicit test adapter without synthesizing input or
  bypassing the application model.
- `GestureBenchmarkInstrumentationAdapter` drives the existing production
  `PointerSession` benchmark for standard12 and maps its trial statistics and
  final-state evidence into `ModelMeasurement`. The dense1000 path builds and
  commits 1,000 deterministic marks, exercises the same session lifecycle,
  and independently records its checksum, publication entries, and final
  state. Both profiles report `.measured` only when the checksum is stable,
  final state is valid, and exactly one publication entry of `2` exists for
  every configured trial; otherwise they preserve diagnostic fields and
  report `.failed`.
- `OffscreenCanvasRendererAdapter` measures the real `CanvasView` draw path
  into a private 512×512 explicit-sRGB RGBA8 CGContext. Standard12 validates
  all 12 canonical marks. Dense1000 validates all 1,000 deterministic varied
  marks through the full plan identity and representative arrow, rectangle,
  ellipse, and freehand probes. Neither path orders a window front, installs
  monitors, dispatches synthetic events, or captures the screen.
  Each warmup is discarded and each measured trial is persisted as a positive
  raw `frameMilliseconds` sample; p95 is recomputed from that exact array.
  Untimed pre/post semantic checks bind the canonical fixture to its complete
  canonical RenderPlan identity (including display/mode/tool state,
  kind payload, RGBA style, selection/selected display, hover, draft, and
  resize/delete handles), no active draft, independent tolerant color/alpha
  positives, and clear interior/exterior/off-path negative regions. Standard12
  retains arrow shaft/head, rectangle edge, and ellipse perimeter probes for
  every mark. Dense1000 generates one safe geometry/color/alpha probe for all
  1,000 marks on its deterministic lattice, and validates all 16 occupied
  raster strata without doing O(N²) work in the timed path. Real bitmap tests
  clear a late mark or a whole stratum while retaining the canonical plan and
  fail closed. The current host observed 10,050 nontransparent pixels
  and digest `0x7491c6e8b3682118` for standard12, and 99,616 nontransparent
  pixels and digest `15893408161499261541` for dense1000. Those raw values are
  used only for same-host pre/post stability, not as a cross-platform
  correctness gate. Bitmap clearing is outside each timed interval; the timed
  region covers graphics-state binding, `view.draw`, and restoration only.
- All measured frame, redraw/layout, responsiveness, and input-to-visible
  adapters must persist exactly `trialCount` positive raw samples with p95
  derived from those samples. Failed and unavailable adapters retain empty raw
  arrays, as required by the report validator.
- Measured frame evidence derives `missedFrameCount` from raw samples above
  the canonical 16.7 ms threshold; the shared report validator rejects any
  underreported slow-frame count, including a single slow outlier hidden by a
  fast p95.
- The semantic oracle rejects wrong cardinality or plan/style identity, sparse
  four-dot geometry, missing per-mark probes, unexpected negative-region
  pixels, and empty/no-op output. Legitimate rasterizer edge drift can pass
  tolerant semantic checks, while a same-host pre/post checksum change fails.
  No caller-supplied expected checksum or coverage values are accepted.
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

Result: 57 tests passed. This includes measured injected-adapter propagation,
raw-array and p95 alignment, model checksum/publication/final-state gates,
failed and unavailable adapter dispositions, configuration mismatch rejection,
nonstandard public-run rejection, separate standard12 and dense1000 model and
renderer evidence, exact dense freehand and timer-boundary checks, real
offscreen renderer coverage and bitmap omission checks, and the existing
complete schema/memory validation suite.

The shared suite contains 444 tests; all 444 passed with zero failures. The
build and `git diff --check` also passed.

## Measured versus deferred

The default harness measures standard12 and dense1000 model and offscreen
renderer work now. Compositor timing, launch timing, allocation bytes,
redraw/layout counters, responsiveness, physical input-to-visible latency,
process RSS/resource sampling, and resilience lifecycle cases remain
explicitly unmeasured until the host/launcher and accepted F/A-harness
instrumentation exist. Those statuses intentionally produce a revise
diagnostic report and cannot satisfy `validateCompletion()`.

F tasks 1–3 must provide the executable composition, Release bundle/resource
foundation, and launcher/provenance path before E can run an authoritative
paired baseline/candidate measurement. E comparison/CLI work remains outside
this slice.
