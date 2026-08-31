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
  resource maxima, the final resource checkpoint, and matched baseline arrays.
  It intentionally does not require exactly 120 or 121 samples; the inclusive
  600-second endpoint remains valid. Failed/unmeasured reports remain flexible
  when no samples exist, while any supplied samples must still have truthful
  resource checkpoints.

## Evidence

TDD RED was observed with the new tests before the production schema existed:
the test target failed to compile with missing measurement types. GREEN was
then verified with:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PerformanceHarnessTests
```

Result: 12 tests passed, including full Equatable round-trip coverage, typed report-kind
rejection, clean/dirty identity rules, provenance mismatches, non-finite and
negative values, memory phase/duration/interval/aggregate/resource-checkpoint
failures, diagnostic status preservation, nonstandard diagnostic configuration,
and completion acceptance/rejection.

The implementation intentionally stops at schema/validation. Instrumentation,
`PerformanceHarness`, CLI dispatch, paired comparisons, and runtime evidence
remain owned by later E tasks.
