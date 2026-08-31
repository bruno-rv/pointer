# Pointer E Task2b: comparison schema and preflight

Status: implemented in the assigned comparison schema/preflight scope. No
commit was created; the parent coordinator owns integration and phase commits.

## Delivered

- Added the explicit Codable/Equatable comparison payloads in
  `Sources/PointerAppKit/Diagnostics/PerformanceComparisonReport.swift`:
  `ManualMetricEvidence`, `ManualMetricAdapter`, `MetricComparison`, and
  `PerformanceComparisonReport`.
- Persisted the complete baseline/candidate `MeasurementIdentity` values in
  the comparison report, alongside their source IDs and typed provenance.
- Reused `ValidatedFoundationProvenance`, `PerformancePairEligibility`,
  `BootstrapInterval`, `ResilienceCase`, and `ResilienceMeasurement` from the
  measurement-owned schema. No duplicate wire types were introduced.
- Added `PerformanceComparisonReport.validateStructure()` and
  `validateCompletion()` with fail-closed identity, provenance, version,
  metric, paired-array, derived ratio/delta, bootstrap, manual evidence,
  resilience, and disposition checks.
- Added `PerformanceComparisonHarness.preflight(...)` and the plan-required
  `compare(...)`/`writeComparison(...)` signatures. Preflight validates both
  measurement reports to completion before checking pair eligibility, rejects
  content-manifest diagnostics and failed/unmeasured inputs, and revalidates
  roots, commit identities, host, fixture, configuration, foundation, and
  build contract.
- Kept Task 3's sampling, ratio/bootstrap calculation, manual-evidence file
  loading, CLI, and pair orchestration out of this task. The forced `compare`
  and `writeComparison` entry points perform all preflight work and then throw a
  specific Task 3 deferral; they do not fabricate a report or touch output.
- Added comparison-specific baseline/candidate, eligibility, metric, manual
  evidence, and round-trip fixtures in
  `Tests/PointerAppKitTests/PerformanceFixtures.swift`.

## Validation decisions

- Comparison schema version is `1` and only `reportKind == .comparison` is
  accepted. Missing enum keys fail Codable decoding; wrong enum values fail
  structural validation.
- Authoritative comparison identities are distinct lowercase 40-hex commit
  SHAs. Both builds must be clean Release provenance with a matching accepted
  foundation artifact SHA; content-manifest identities remain diagnostic-only.
- A comparison carries every `PerformanceMetricID` exactly once. Baseline,
  candidate, ratio, and delta arrays must each contain exactly
  `pairsPerOrder * 2` (30 standard) finite samples. Ratios and deltas must
  equal candidate/baseline and candidate-minus-baseline respectively within a
  small floating-point tolerance; empty or short derived arrays are rejected.
- Full baseline/candidate measurement environments must match across host
  model, macOS, Xcode, developer directory, power state, display state, and
  Release build configuration. Each persisted identity must also agree with
  its corresponding clean commit build/run provenance.
- Bootstrap bounds must be finite/coherent and use the fixed comparison seed
  and resample count from the standard configuration. Manual metrics require
  complete UTC evidence with nonempty permissions, exact steps, result, path,
  finite samples, and a host matching the paired run; deterministic metrics
  reject manual evidence.
- Resilience evidence is measured, nonempty, uniquely identified, and resource
  coherent. Completion requires accepted overall/metric/resilience dispositions
  and no leaked or unexpected-growth case.
- `writeComparison` is intentionally non-mutating until Task 3 owns valid
  calculation/output mapping. Both invalid inputs and the explicit deferral
  leave no partial output.

## Evidence

TDD RED was observed before the comparison types/fixtures/harness existed:
the focused test target failed to compile with missing comparison types and
fixture members. GREEN was then verified with:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PerformanceComparisonHarnessTests
```

Result: 13 focused tests passed, covering full Codable round-trip and
completion, wrong/missing report kind, duplicate/missing IDs, exact 30-pair
array cardinality, every measurement-environment compatibility dimension,
host/config and eligibility mismatch, content-manifest rejection,
failed/unmeasured preflight, array/ratio/bootstrap errors, manual evidence and
host matching, resilience coherence, disposition rejection, atomic no-output
behavior, and valid-pair preflight with the Task 3 deferral.

The parent coordinator must rerun the full Swift suite, Release/debug build,
and `git diff --check` after all parallel E work is reconciled. Task 3 must
replace the explicit comparison deferral with fixed-seed paired calculations,
manual evidence loading, and atomic JSON output without weakening this
preflight boundary.
