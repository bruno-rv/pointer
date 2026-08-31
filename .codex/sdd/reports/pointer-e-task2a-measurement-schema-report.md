# Pointer E Task2a: measurement schema

Status: implemented in the assigned schema/test scope; no commit created.

## Delivered

- Added the typed, Codable measurement schema in
  `Sources/PointerAppKit/Diagnostics/PerformanceMeasurementReport.swift`.
- Added fixture-only report construction and focused validation coverage in
  `Tests/PointerAppKitTests/PerformanceFixtures.swift` and
  `Tests/PointerAppKitTests/PerformanceHarnessTests.swift`.
- Added the shared `PerformanceValidationError`, report/metric/status enums,
  immutable source/build/run/foundation identities, fixed configuration (with
  `pairsPerOrder` and derived `totalPairs`), all measurement payloads,
  resilience/resource types, and the shared bootstrap interval value type for
  later comparison work.

## Validation decisions

- `PerformanceMeasurementReport.currentSchemaVersion` is `1`; structural
  validation accepts only `reportKind == .measurement` and that version.
- Source identity is fail-closed: exactly one lowercase 40-hex commit or
  lowercase 64-hex content manifest is required. Clean trees must use the
  commit identity; dirty trees must use the content-manifest identity.
- Build provenance is portable and contains no output path or pair ancestry.
  Run provenance carries variant/root/source-reference context and embeds the
  build provenance; report, build, run, host, fixture, and configuration
  versions must agree.
- Codable enum decoding rejects unknown values before validation. Diagnostic
  reports may retain `failed` or `unmeasured` statuses and partial arrays, but
  completion requires every required metric to be measured, valid final state,
  zero missed-frame/input samples and stalls, explicit 16.7 ms/100 ms budgets,
  the exact campaign-standard configuration, bounded memory delta, clean
  resilience cases, and accepted disposition.
- Memory validation enforces the 600-second/5-second contract, ordered samples,
  running/stopping/stopped/restarted phases, nonnegative/coherent resources,
  contiguous aggregates that reconcile to the running RSS series, exact peak
  RSS/resource maxima, the final resource checkpoint, and matched baseline
  arrays. A measured standard report requires all 121 running samples at
  exactly 0...600 seconds in 5-second increments followed by stopping,
  stopped, and restarted checkpoints at 605/610/615 seconds; stopped resources
  must be zero and restarted resources remain within running bounds. It does
  not conflate a 120-vs-121 endpoint choice with a diagnostic failure: the
  structural contract is fixed to the inclusive 121-point standard window,
  while failed/unmeasured reports remain flexible when no samples exist.
- Memory's matched-baseline series is defined as the elapsed-time series for
  the running candidate samples; matched-baseline values are the corresponding
  baseline RSS values. The final-window byte and percentage deltas are derived
  from the final running candidate RSS and final matched baseline RSS (a zero
  baseline is invalid), with an exact byte match and a small floating-point
  percentage tolerance. Completion also rejects a positive post-warmup RSS
  slope.
- Measured model, frame, launch, allocation, redraw/layout, and input evidence
  counts must match the fixture/trial configuration; diagnostic failed or
  unmeasured objects may retain partial arrays. Completion additionally
  requires the exact standard configuration, Release build identity and
  provenance, and a valid non-nil accepted foundation artifact hash echoed by
  run provenance.

## Evidence

TDD RED was observed with the new tests before the production schema existed:
the test target failed to compile with missing measurement types. GREEN was
then verified with:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PerformanceHarnessTests
```

Result: 16 tests passed, including full Equatable round-trip coverage, typed report-kind
rejection, clean/dirty identity rules, provenance mismatches, non-finite and
negative values, memory phase/duration/interval/aggregate/resource-checkpoint
failures, derived RSS/delta and slope checks, full lifecycle cadence,
configuration cardinality, diagnostic status preservation, nonstandard/debug
diagnostic configurations, and completion acceptance/rejection.

The implementation intentionally stops at schema/validation. Instrumentation,
`PerformanceHarness`, CLI dispatch, paired comparisons, and runtime evidence
remain owned by later E tasks.
