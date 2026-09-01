# Pointer E Task2a: measurement schema

Status: implemented and committed in the assigned schema/test scope.
Implementation commit: `48ce323`.
Synchronized contract documentation: `121fdbf`.

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
  later comparison work. Schema v1 now also carries raw frame, redraw/layout,
  responsiveness, and input-to-visible timing arrays plus the explicit
  `standard12`/`dense1000` fixture profiles.

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
  one of the exact canonical fixture configurations, bounded memory delta, clean
  resilience cases, and accepted disposition.
- Memory validation enforces the 600-second/5-second contract, ordered samples,
  running/stopping/stopped/restarted phases, nonnegative/coherent resources,
  contiguous aggregates that reconcile to the running RSS series, exact peak
  RSS/resource maxima, the final resource checkpoint, and matched baseline
  arrays. A measured canonical report requires all 121 running samples at
  exactly 0...600 seconds in 5-second increments followed by stopping,
  stopped, and restarted checkpoints at 605/610/615 seconds; stopping and
  stopped resources must be exactly zero and restarted resources must exactly
  return to the initial steady running baseline. It does
  not conflate a 120-vs-121 endpoint choice with a diagnostic failure: the
  structural contract is fixed to the inclusive 121-point standard window,
  while failed/unmeasured reports remain flexible when no samples exist.
- Memory's matched-baseline series is defined as the elapsed-time series for
  the running candidate samples; matched-baseline values are the corresponding
  baseline RSS values. The final-window byte and percentage deltas are derived
  from the final running candidate RSS and final matched baseline RSS (a zero
  baseline is invalid), with an exact byte match and a small floating-point
  percentage tolerance. The reported post-warmup slope is the least-squares
  regression over every post-warmup running sample, with an exact documented
  tolerance of `1e-9` bytes/second; completion rejects a positive regression
  above that master noise tolerance even when the final sample falls. A tiny
  positive slope within the tolerance remains acceptable, while NaN or
  infinity is rejected even for failed/unmeasured reports with no samples.
- Measured model, frame, launch, allocation, redraw/layout, and input evidence
  counts must match the fixture/trial configuration, and each raw timing
  array is finite, strictly positive, cardinality-aligned, and the source of
  truth for its p95 value. Measured frame evidence also derives
  `missedFrameCount` exactly from raw samples above 16.7 ms, so a fast p95 does
  not hide a single slow outlier. Diagnostic failed or unmeasured objects carry
  empty raw arrays while retaining finite scalar diagnostics. Completion additionally
  requires an exact canonical profile configuration, Release build identity and
  provenance, and a valid non-nil accepted foundation artifact hash echoed by
  run provenance. Canonical profile identifiers and versions are bound to their
  mark counts in both configuration and fixture identity, so a matching mark
  count cannot spoof the other profile. Structurally valid failed or unmeasured reports must carry
  `.revise` disposition; `.acceptedNoRegression` and `.blocked` are rejected
  for those diagnostic states. Legacy standard-12 fixture identifiers are not
  accepted; the internal compatibility initializer emits only the canonical
  profile identifier.

## Evidence

TDD RED was observed with the new tests before the production schema existed:
the test target failed to compile with missing measurement types. GREEN was
then verified with:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PerformanceHarnessTests
```

Result: 57 tests passed, including full Equatable round-trip coverage, typed report-kind
rejection, clean/dirty identity rules, provenance mismatches, non-finite and
negative values, memory phase/duration/interval/aggregate/resource-checkpoint
failures, derived RSS/delta and slope checks, full lifecycle cadence,
configuration cardinality, diagnostic status preservation, nonstandard/debug
diagnostic configurations, named authoritative accepted-foundation rejection,
and completion acceptance/rejection.

The focused Task3-integrated target passes 57/57 tests, including raw-array
round-trip, p95/cardinality, non-finite diagnostic, missed-frame outlier,
canonical standard12/dense1000 profile identity, cross-profile spoof rejection,
and dense single-profile report coverage. The full package suite passes 444/444
tests. The profile schema addition is a pre-release working-tree change; the
prior implementation and
synchronized contract documentation are committed as noted above. The current
build passes; no comparison or harness file is changed here.

The implementation intentionally stops at schema/validation. Instrumentation,
`PerformanceHarness`, CLI dispatch, paired comparisons, and runtime evidence
remain owned by later E tasks.
