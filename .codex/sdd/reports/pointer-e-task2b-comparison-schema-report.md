# Pointer E Task2b: comparison schema and preflight

Status: implemented in the assigned comparison schema/preflight scope. No
commit was created; the parent coordinator owns integration and phase commits.

## Delivered

- Added the typed `PerformanceMetricUnit` mapping and explicit
  Codable/Equatable comparison payloads in
  `Sources/PointerAppKit/Diagnostics/PerformanceComparisonReport.swift`:
  `ManualMetricEvidence`, `ManualMetricAdapter`, `MetricComparison` (including
  its typed absolute `budgetLimit`), and `PerformanceComparisonReport`.
- Persisted the complete baseline/candidate `MeasurementIdentity` values in
  the comparison report, alongside their source IDs and typed provenance.
- Persisted exact baseline/candidate `FixtureIdentity` values and enforced the
  canonical `baseline` and `candidate` run variants.
- Persisted lowercase-64hex SHA-256 bindings for the exact baseline and
  candidate measurement-report bytes. Added an atomic report-bound writer that
  hashes and matches both input files before writing `paired-comparison.json`.
- Reused `ValidatedFoundationProvenance`, `PerformancePairEligibility`,
  `BootstrapInterval`, `ResilienceCase`, and `ResilienceMeasurement` from the
  measurement-owned schema. No duplicate wire types were introduced.
- Added `PerformanceComparisonReport.validateStructure()` and
  `validateCompletion()` with fail-closed identity, provenance, version,
  metric, paired-array, derived ratio/delta, bootstrap, manual evidence,
  resilience, and disposition checks.
- Added `PerformanceComparisonHarness.preflight(...)` and the internal,
  calculation-deferred `compare(...)` seam. The public report-bound
  `writeComparison(report:baselineURL:candidateURL:outputDirectory:configuration:eligibility:)`
  is the sole persistence API. Preflight validates both
  measurement reports to completion before checking pair eligibility, rejects
  content-manifest diagnostics and failed/unmeasured inputs, and revalidates
  roots, commit identities, host, fixture, configuration, foundation, and
  build contract.
- The persisted-output URL writer decodes the exact input bytes, runs full
  preflight, cross-checks IDs, full measurement identities, fixtures, build/run
  provenance, hosts/configuration, versions, and pair eligibility, then writes
  only with exact SHA-256 bindings. The decoded-value `compare` entry point is
  internal and remains calculation-deferred for Task 3.
- Kept Task 3's sampling, ratio/bootstrap calculation, manual-evidence file
  loading, CLI, and pair orchestration out of this task. The plan-signature
  `compare` entry point performs preflight and then throws a specific Task 3
  deferral; it does not fabricate a report. Persisted output is available only
  through the report-bound URL writer after all binding checks pass.
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
  Baseline and candidate samples must be strictly positive. Only
  `combinedFrame` (16.7 ms), `responsiveness` (100 ms), and `inputToVisible`
  (100 ms) carry exact canonical absolute budgets; all other metrics persist
  `nil` budgets, preventing caller-selected limits from hiding regressions.
  The canonical unit table uses milliseconds for `redrawLayout` (as well as
  frame, launch, responsiveness, and input metrics), nanoseconds for `model`,
  and bytes for allocation and memory metrics.
- `memoryRSS` comparisons use strictly positive absolute RSS samples in bytes
  and no absolute budget; signed memory deltas and post-warmup slopes remain
  governed by the measurement report's completion validator.
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
- Completion independently recomputes each metric's ratio median and
  nearest-rank p95, requiring both ratio statistics to be at most 1.10. For
  the three contract-defined absolute budgets, candidate p95 must also remain
  at or below the canonical `budgetLimit`.
- Completion also recomputes candidate renderer and compositor p95 values and
  requires their sum to remain at or below 16.7 ms. A 16 ms combined-frame
  boundary remains valid while a 10 ms + 10 ms renderer/compositor pair is
  rejected.
- The internal `compare` seam remains non-writing until Task 3 owns calculation
  and output mapping. The public report-bound writer hashes exact input bytes,
  validates matching persisted bindings, and writes atomically; mismatch and
  missing-input paths leave no partial output.

## Evidence

TDD RED was observed before the comparison types/fixtures/harness existed:
the focused test target failed to compile with missing comparison types and
fixture members. GREEN was then verified with:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PerformanceComparisonHarnessTests
```

Result: 22 focused tests passed, covering full Codable round-trip and
completion, wrong/missing report kind, duplicate/missing IDs, exact 30-pair
array cardinality, every measurement-environment compatibility dimension,
positive-sample, canonical-unit, non-spoofable budget, ratio regression, and
16.7/100 ms budget breach rejection, persisted fixture and
baseline/candidate variant mismatch, absolute RSS semantics, exact input-byte
SHA-256 binding and mismatch rejection, decoded-input identity/fixture/build/
run/host/config/eligibility cross-checks, renderer/compositor and combined-frame
budget boundaries, host/config and eligibility mismatch, content-manifest
rejection,
failed/unmeasured preflight, array/ratio/bootstrap errors, manual evidence and
host matching, resilience coherence, disposition rejection, atomic no-output
behavior, and valid-pair preflight with the Task 3 deferral.

The parent coordinator must rerun the full Swift suite, Release/debug build,
and `git diff --check` after all parallel E work is reconciled. Task 3 must
replace the explicit comparison deferral with fixed-seed paired calculations,
manual evidence loading, and atomic JSON output without weakening this
preflight boundary.
