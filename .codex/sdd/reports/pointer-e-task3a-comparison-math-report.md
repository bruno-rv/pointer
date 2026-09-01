# Pointer E Task3a: comparison calculation foundation

Status: implemented in the shared worktree; not committed by this worker.

## Delivered

- Replaced the calculation deferral in `PerformanceComparisonHarness.compare` with a
  measured-only, hash-free draft calculation seam. Existing preflight remains first,
  so failed/unmeasured inputs and ineligible lineage are rejected before any draft
  or output path is touched.
- Added observed pair provenance with typed `PerformancePairExecutionRecord` and
  `PerformancePairExecutionArtifact`. The artifact binds both report IDs and
  exact report hashes, records the observed order/timestamps/sample indices for
  all 30 pairs, and validates unique contiguous pair/sample indices, the exact
  first-15 baseline-first/next-15 candidate-first sequence, and complete
  non-overlapping per-pair timestamps. The artifact and its SHA-256 are persisted
  in both the hash-free draft and final report; metric arrays are paired by
  recorded (including non-identity) sample indices rather than generated labels.
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
  regular non-symlink files, strict JSON envelope/field shape, an identity-bound
  baseline/candidate `ManualMetricEvidencePair`, matching report IDs/hashes,
  pair-artifact hash, procedure version, observed pair order, host, UTC timestamp,
  nonempty permissions/steps/result, exactly 30 positive samples, and an exact
  relative `<metricID>.json` evidence path. Hidden/unknown files and manual
  evidence for deterministic metrics fail closed.
- Pair-artifact and manual-pair JSON uses strict recursive key validation and
  sorted-key canonical bytes. The writer rejects whitespace/key-order variants or
  unknown nested fields, and persisted report validation recomputes the canonical
  embedded artifact SHA rather than trusting a supplied arbitrary hash.
- The sole public persistence API is
  `writeComparison(draft:baselineURL:candidateURL:pairExecutionURL:manualEvidenceDirectory:outputDirectory:configuration:eligibility:)`.
  It decodes and hashes both source reports and the observed pair artifact,
  recomputes the expected draft from those exact inputs and the same required
  evidence directory, and rejects any stale or synthetic draft before writing.
  The report validator independently recomputes bootstrap intervals and checks
  `improvementClaimed`, manual sample binding, and canonical manual IDs.
- `PerformanceComparisonDraft` is a public opaque carrier: its initializer and
  stored fields are internal, while the writer injects report kind, schema
  version, and source-report hashes into the persisted report. A symbol graph
  extracted from the built debug module is authoritative for the complete
  comparison public inventory: the draft has no public members and the harness
  exposes only the exact writer symbol. External `swiftc` probes additionally
  verify the exact writer signature and that `preflight`, `compare`, draft
  construction/properties, and legacy writer shapes are not callable.
- Mapped resilience from the completed candidate input only after matching case
  identifiers and checking both baseline and candidate completed cases. No healthy
  result is fabricated when either input reports an unhealthy resilience case.
- Comparison preflight and report validation accept either canonical fixture
  profile, while requiring the baseline and candidate configurations and typed
  fixtures to match exactly. The profile regression proof shows that a forged
  standard12/dense1000 cross-pair is rejected even with matching host, commit,
  and sample shape; matching dense1000 reports remain separate, single-profile
  artifacts whose pair execution binds their report hashes.
- Persisted dense comparison validation independently binds both fixture sides
  to the run configuration's profile, version, canonical identifier, and mark
  count. Decoded tamper cases for each of those fields are rejected while
  baseline/candidate fixture equality remains intact.

## Verification

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PerformanceComparisonHarnessTests
git diff --check
```

Latest gates: focused comparison tests passed 45/45; the full suite passed
444/444; build passed; and `git diff --check` passed. The public-surface probe
resolved the built debug `PointerAppKit` module and macOS SDK, extracted a
non-empty symbol graph with the expected module identity, and matched its
complete comparison declaration/member/relationship inventory against a strict
allowlist. It also passed a known public-symbol sanity compile, probes every one
of the draft's 21 current stored properties individually, and separately rejects
writer calls missing either the pair artifact URL or the manual evidence
directory with access/member/signature diagnostics.
The focused tests cover observed pair artifact order/index/count, exact ratios/deltas, a known
bootstrap vector plus repeatability/seed sensitivity, valid and malformed manual
evidence, deterministic/manual separation, resilience mapping, revise
disposition, observed-index manual binding, procedure equivalence, exact artifact
sequence/timestamp validation, recursive shape/canonical-byte rejection, dual
fixture-profile pairing, and the existing writer trust boundary.

## Deferred boundary

This task does not execute real paired baseline/candidate runs, build provenance,
CLI argument orchestration, or release-bundle smoke. Those remain E Task3b/E
execution and F-foundation responsibilities. The comparison writer still owns
exact input-byte hashing and remains the only persisted comparison entry point.
