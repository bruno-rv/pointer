# Pointer E Task3a: comparison calculation foundation

Status: implemented in the shared worktree; not committed by this worker.

## Delivered

- Replaced the calculation deferral in `PerformanceComparisonHarness.compare` with a
  measured-only, hash-free draft calculation seam. Existing preflight remains first,
  so failed/unmeasured inputs and ineligible lineage are rejected before any draft
  or output path is touched.
- Added typed `PairOrder` labels to `MetricComparison`. Every generated metric uses
  the canonical sequence of 15 `baselineFirst` followed by 15 `candidateFirst`
  pairs; comparison validation rejects any other sequence.
- Mapped the typed measurement report into all eleven comparison metrics. Raw
  30-sample arrays are retained for model, renderer, compositor, combined frame,
  launch, allocation, redraw/layout, responsiveness, and input-to-visible metrics;
  memory uses the first 30 running RSS samples. Manual evidence replaces candidate
  samples only for the explicitly manual-capable physical metrics (`compositor` and
  `inputToVisible`).
- Added deterministic candidate/baseline ratios and candidate-minus-baseline
  deltas, canonical units and budgets, per-metric/overall `acceptedNoRegression`
  or `revise` dispositions, and an `improvementClaimed` bit that is true only
  when the recomputed bootstrap upper delta is strictly negative. The
  renderer-plus-compositor and combined-frame gates are included in the overall
  disposition.
- Added a SplitMix64-backed, seeded bootstrap interval over paired deltas. The
  implementation records the configured seed and resample count and uses nearest
  rank 2.5%/97.5% bounds, making the interval reproducible without global state.
- Added strict manual evidence directory loading: exact supported filenames,
  regular non-symlink files, strict JSON envelope/field shape, matching metric and
  host, UTC timestamp, nonempty permissions/steps/result, exactly 30 positive
  samples, and an exact relative `<metricID>.json` evidence path. Hidden/unknown
  files and manual evidence for deterministic metrics fail closed.
- The sole public persistence API is
  `writeComparison(draft:baselineURL:candidateURL:manualEvidenceDirectory:outputDirectory:configuration:eligibility:)`.
  It decodes and preflights both source reports, recomputes the expected draft
  from that same required evidence directory, and rejects any stale or synthetic
  draft before calculating hashes or writing output.
  The report validator independently recomputes bootstrap intervals and checks
  `improvementClaimed`, manual sample binding, and canonical manual IDs.
- Mapped resilience from the completed candidate input only after matching case
  identifiers and checking both baseline and candidate completed cases. No healthy
  result is fabricated when either input reports an unhealthy resilience case.

## Verification

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PerformanceComparisonHarnessTests
git diff --check
```

Results from the final gates: focused comparison tests passed 34/34; the full
suite passed 406/406; build passed; and `git diff --check` passed.
The focused tests cover fixed pair order/count, exact ratios/deltas, a known
bootstrap vector plus repeatability/seed sensitivity, valid and malformed manual
evidence, deterministic/manual separation, resilience mapping, revise
disposition, manual compositor participation in the frame-budget gate, and the
existing writer trust boundary.

## Deferred boundary

This task does not execute real paired baseline/candidate runs, build provenance,
CLI argument orchestration, or release-bundle smoke. Those remain E Task3b/E
execution and F-foundation responsibilities. The comparison writer still owns
exact input-byte hashing and remains the only persisted comparison entry point.
