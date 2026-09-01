# Pointer E/F specification reconciliation

Date: August 31, 2026

Status: Reconciled for implementation planning. This report records the
cross-document decisions applied to the six-month design, E performance plan,
and F integration plan. It is a specification artifact only; it does not
claim that E/F implementation or physical evidence exists.

## Decisions made

| Concern | Reconciled contract |
| --- | --- |
| Diagnostic report boundary | `Pointer --benchmark-gestures --format json` remains the model-only serialized `GestureBenchmark.Result`. `--quality-performance --format json --fixture-profile standard12|dense1000` emits one typed `PerformanceMeasurementReport` for that profile; `--quality-compare --format json --fixture-profile standard12|dense1000` emits one typed `PerformanceComparisonReport` for the same profile. Task 3c/E-execution orchestrates the two full-quality commands once per profile. |
| Report typing | E defines `PerformanceReportKind` with `measurement` and `comparison` cases. Each report carries the matching typed `reportKind`; structural validation and tests reject missing or wrong kinds. |
| Source identity | A single measurement accepts exactly one `--source-commit-sha <40hex>` or `--content-manifest-sha256 <64hex>`. A clean tree uses the commit identity; a dirty tree uses the full content-manifest identity. Both, neither, malformed, symbolic, or stale identities are rejected. The authoritative paired comparison accepts clean commit identities only and requires explicit baseline/candidate roots, commit SHAs, foundation provenance, manual-evidence directory, and output directory. |
| Source-manifest scope | E and F use the same Git-tracked scope: `Package.swift`, `Sources/**`, `Tests/**`, `scripts/**`, `Bundle/Assets.xcassets/**`, bundle identity/Info.plist files, and the master plus six phase plan/design inputs. Sorted `<sha256>  <relative-path>` rows produce the aggregate SHA; generated reports/build products/signature metadata/mtimes/absolute paths/untracked files are excluded. |
| Baseline eligibility | Authoritative baseline and candidate use the same E schema/harness/fixture profile, typed harness/foundation/build-contract versions, F launcher/build foundation, and host. The baseline is pinned only after the F-foundation checkpoint; both refs are clean 40-hex commits, baseline is an ancestor of candidate, and both are descendants of the foundation checkpoint. Content-manifest measurements remain diagnostic-only. |
| Per-variant roots | F's build helper accepts `--output-root <root>` and emits exactly `<root>/Pointer.app`, `<root>/source-manifest.sha256`, `<root>/bundle-manifest.sha256`, and build-only `<root>/provenance.json` containing portable `BuildProvenance`, including exact `buildConfiguration` (`release` authoritative; `debug` bootstrap diagnostic), with no path or pair ancestry; E creates `build/<fixture-profile>/{baseline,candidate}` for both `standard12` and `dense1000`, writes each profile's separate measurements, provenance, pair artifact, comparison, resilience, and output paths, passes the accepted foundation path to both post-acceptance builds, and consumes those exact paths for repeat/idempotence comparisons. |
| Foundation checkpoint | F tasks 1–3 produce tracked `.codex/sdd/reports/quality-campaign/foundation/accepted-foundation.json` with fixed identity/version/hash/acceptance fields. The worker, reviewer, and adversarial gates must accept it before E-execution. E and clean-clone receive it through explicit `--foundation-provenance`; loaders validate hashes and derive foundation/harness/build-contract versions without hidden environment state. |
| Provenance | F build roots contain portable typed `BuildProvenance` only (source/executable/bundle hashes, exact build configuration, foundation/version fields, optional accepted-artifact SHA, and no path or pair ancestry); E-foundation's `benchmark-quality.sh` is the sole creator of per-variant `PerformanceRunProvenance` and `PerformancePairEligibility`, and E-execution consumes it, using two validated build artifacts plus roots/refs/foundation. An authoritative run requires nonnil 64-hex `acceptedFoundationArtifactSHA256` matching its embedded build and accepted artifact; bootstrap diagnostics may leave it nil. The app embeds validated build/run artifacts after syntax/hash checks, while the script proves Git cleanliness, ancestry, and checkout-to-binary correspondence. |
| Memory slope | E v1 `MemoryMeasurement` carries `postWarmupSlopeBytesPerSecond`, computed by ordinary least squares over post-warmup running RSS samples; structural validation requires finite values, and completion rejects growth above the exact `1e-9` B/s tolerance. |
| Resource boundary | Runtime ships only the executable, `Info.plist`, compiled `Contents/Resources/Assets.car`, and byte-identical `Contents/Resources/GuideAssetIdentity.json`. Raw PNG files and any `*.imageset` or `*.xcassets` file/directory anywhere under Resources fail the bundle contract. Source-input and bundle-output manifests are separate and both are compared across repeat builds and clean clone. |
| Composition injection | `PointerCompositionRoot.make(resourceBundle: Bundle = .main)` is the sole default selection point. It loads `GuideAssetIdentity.json` and passes that same explicit bundle to `GuideAssetCatalog`; the catalog never calls `Bundle.main`, uses a default bundle, or performs global lookup. |
| API boundary | F-foundation validates the importable composition boundary with a temporary external-module, symbol-aware `swiftc -typecheck` probe importing only `PointerComposition`/`PointerAppKit` and resolving `PointerCompositionRoot.make(resourceBundle:)`/`PointerComposition`; package-graph inspection proves `PointerCompositionTests` has no `Pointer` executable dependency. A source substring search is not acceptance evidence. |
| Phase order | `A-foundation → B-core → C → D → B-render-integration → A-harness → E-foundation (tasks 1–3, including Task 3c) → F-foundation (tasks 1–3) → E-execution → F-final (tasks 4–7)`. E-foundation defines and implements the CLI/script contracts before F; F-foundation imports and wires the existing CLI; paired execution waits for F; F-final consumes reconciled E reports. |
| Clean clone | Canonical input cleanliness is captured before any source-root write, excluding generated reports/build products and the final evidence output; temporary evidence stays under `$fixture`. The script validates `checkpointCommitSHA` and foundation/current manifests, build provenance, then tests, directly invokes the built executable with `--smoke --format json`, and runs `verify.sh`; it atomically publishes final `CleanCloneIdentity.md` on success or failure, and an immediate rerun must remain reproducible. |
| Chrome friction | F reruns the authoritative `ChromeFrictionReport` against the final F candidate and records the full immutable E baseline hash. D's Chrome checkpoint is historical provenance only and is never silently relabeled as final evidence. |
| Pair eligibility | E defines typed `PerformancePairEligibility`/validated foundation provenance arguments. The CLI/script constructs eligibility only after root/ref/clean/head/ancestry/foundation checks and exact `pairsPerOrder == 15`/derived `totalPairs == 30`; the harness revalidates report/provenance equality and direct fabricated eligibility cannot bypass it. |
| Fixture profile separation | E defines the canonical `PerformanceFixtureProfile` values `standard12` and `dense1000`, with versions `pointer-fixture-standard12/v1`/`pointer-fixture-dense1000/v1`, identifiers `pointer-standard-12-marks`/`pointer-dense-1000-marks`, and counts 12/1,000. Each variant emits separate configuration/provenance and measurement reports per profile under `build/<fixture-profile>/{baseline,candidate}` and `.codex/sdd/reports/quality-campaign/performance/<fixture-profile>/{measurements,provenance,comparisons,resilience}/`; pair artifacts and comparisons are separate per profile. Task 3c's typed `PerformanceCampaignCompletionManifest` requires exactly one accepted comparison for each profile and rejects missing, duplicate, or concatenated populations. Both profiles apply the 16.7 ms renderer-plus-compositor and combined-frame gates independently. |
| Measurement identities | `PerformanceComparisonReport` carries baseline/candidate configurations through their typed run provenance and equal persisted `baselineFixture`/`candidateFixture` values, each with matching `fixtureProfile`/`fixtureVersion`/`markCount`; one comparison is for one fixture profile only. Pair preflight requires exact equality for host model, macOS, Xcode, developerDirectory, power/display state, and buildConfiguration; source commits remain distinct and provenance-matched. Every metric has its canonical `PerformanceMetricUnit`, finite strictly positive baseline/candidate samples, and nonempty ratio/delta arrays of exactly `totalPairs` entries. It also carries lowercase 64-hex `baselineMeasurementReportSHA256` and `candidateMeasurementReportSHA256` values computed from and verified against the exact input report bytes before the comparison is written; F retains those input reports unchanged. For `memoryRSS`, comparison samples are strictly positive absolute RSS bytes; signed `finalWindowDeltaBytes` and `postWarmupSlopeBytesPerSecond` (B/s) remain measurement-report fields validated during pair preflight, not comparison sample units. |
| Timing arrays | E v1 exposes raw `frameMilliseconds`, redraw/layout `sampleMilliseconds`, `responseMilliseconds`, and input-to-visible `sampleMilliseconds`; measured reports require exactly `trialCount` finite strictly positive samples with recomputed p95, while failed/unmeasured diagnostics may use empty arrays. For measured frames, `missedFrameCount` equals the count of raw samples greater than 16.7 ms. |
| Pair execution artifact | `PerformancePairExecutionArtifact` JSON contains exactly `schemaVersion`, `baselineID`, `candidateID`, `baselineMeasurementReportSHA256`, `candidateMeasurementReportSHA256`, and `records` with 30 unique contiguous indexed records; records 0–14 are baseline-first and 15–29 candidate-first, each with sample indices and UTC start/end timestamps. The producer uses the canonical sorted-key encoder; `pairExecutionArtifactSHA256` is a separate draft/report field equal to SHA-256 of those canonical bytes and is recomputable from the embedded artifact. Unknown fields, alternate whitespace, or key order reject before decoding/acceptance. Internal preflight validates measurement/configuration/eligibility only; internal compare validates the decoded artifact/order and separate SHA, while the public writer alone reads/validates canonical URL bytes. The validator requires each variant's start ≤ its own end, the first variant's end < the second variant's start, and each pair's second end < the next pair's first start. Mismatches produce no output. |
| Pair order and improvement | The artifact records are the sole observed `PairOrder` source: exactly 15 baseline-first and 15 candidate-first; E-foundation's `benchmark-quality.sh` remains the Task3c producer that emits them per pair, and E-execution only consumes it. The validator recomputes bootstrap intervals from deltas/seed/resample count and rejects tampering; `improvementClaimed` is true only when the recomputed delta upper bound is strictly below zero, false otherwise, and `acceptedNoRegression` is not an improvement claim. |
| Manual pair evidence | `ManualMetricEvidencePair` contains `procedureVersion`, typed `pairOrders`, and baseline/candidate `ManualMetricEvidence`; each entry binds variant, commit, measurement-report hash, pair-artifact hash, host, timestamp, permissions, exact steps, samples, result, and evidence path. Both variants use the same ordered steps, permissions, evidencePath, and shared procedureVersion, with exactly the matching compositor/input files. The canonical sorted-key encoder/adapter emits each file; unknown fields, alternate whitespace, or key order reject before decoding/acceptance. Identity or procedure mismatches reject. |
| Adapter reality | E-foundation Task 3b defines compositor/process/manual/combined-frame protocols with honest `.unmeasured`/`revise` fallbacks. The profile-aware model/renderer fixture implementation covers both standard12 and dense1000 with tests; the offscreen renderer is real CanvasView/CGContext, while WindowServer compositor, process, combined-frame, and manual writer paths are currently unmeasured/schema-only. `CACurrentMediaTime` alone is not WindowServer measurement, `combinedFrame` is not a renderer-plus-compositor sum, and Task 3c/E-execution must provide external trace/process/manual sidecars. |
| Metric budgets | `budgetLimit` is optional and canonical: 16.7 milliseconds for `combinedFrame`, 100 milliseconds for `responsiveness` and `inputToVisible`, nil for other metrics, and never an absolute RSS p95 for `memoryRSS`. Completion recomputes ratio median/p95 ≤1.10 and candidate p95 only for the three budgeted metrics. It also requires candidate renderer p95 plus compositor p95 ≤16.7 milliseconds and candidate `combinedFrame` p95 ≤16.7 milliseconds for each fixture profile; wrong, huge, missing, or unexpected budgets/units are rejected. |
| Comparison writer boundary | Public persisted entry is the exact `writeComparison(draft:baselineURL:candidateURL:pairExecutionURL:manualEvidenceDirectory:outputDirectory:configuration:eligibility:)`: it accepts a hash-free `PerformanceComparisonDraft` plus the required existing manual-evidence directory and pair-execution URL, reads exact measurement bytes from the URLs, computes/verifies the lowercase 64-hex report hashes and canonical artifact bytes, decodes, cross-checks the draft and artifact, and writes atomically only after internal measurement/configuration/eligibility preflight and decoded artifact/manual-evidence validation; no overload omits either directory or artifact. The draft is public `Sendable, Equatable` opaque with no public initializer or stored properties and excludes `reportKind`, `schemaVersion`, and both input-report hashes; the writer owns and injects `reportKind == .comparison`, `schemaVersion == 1`, and those hashes. The CLI requires `--manual-evidence-dir` and binds it directly to both seams. Deterministic runs require that directory to be empty. Internal `compare(baseline:candidate:configuration:eligibility:pairExecutionArtifact:manualEvidenceDirectory:pairExecutionArtifactSHA256:baselineMeasurementReportSHA256:candidateMeasurementReportSHA256:)` returns only that draft after validating manual evidence and the decoded artifact with its separate SHA, including recomputing/validating the canonical artifact SHA. Exact input measurement-byte/source-URL hash verification remains public-writer-owned; it is the deferred, non-writing calculation seam. Any hash, identity, fixture, provenance, pair-artifact, or eligibility mismatch produces no output. |
| Comparison semantics | Structurally valid measurement reports may preserve failed/unmeasured statuses for diagnosis, but each such measurement report structurally requires disposition `revise`, never `blocked` or `acceptedNoRegression`; authoritative comparison first verifies typed eligibility from the shell's roots/refs/foundation checks and rejects any failed/unmeasured required input before constructing or writing any comparison. The CLI consumes only `--fixture-profile standard12|dense1000`, `--baseline-report`, `--candidate-report`, `--pair-eligibility-file`, `--pair-execution-artifact`, `--manual-evidence-dir`, and `--output-dir`; the writer reads the pair artifact URL and supplies its decoded value plus separate SHA to internal compare, which also receives the manual directory, and persists measured comparisons only through the public writer. |
| Required prerequisites | F-final requires accepted A-harness real-guide lifecycle evidence from `pointer-a-harness-lifecycle-report.md` and `pointer-a-harness-phase-report.md`, where the real `FirstUseGuideController`/panel is injected through controller start/stop/restart, plus the canonical 420-point narrow-display evidence. A static guide/catalog test or stale narrow-display report cannot substitute for either prerequisite. |

## Changed clauses by artifact

### Six-month quality design

- Split the E and F ownership/dependency map into E-foundation,
  F-foundation, E-execution, and F-final gates, and removed the former single
  `E → F` wording.
- Corrected the benchmark/report boundary and added typed report-kind and
  mutually exclusive source-identity requirements.
- Replaced copied-guide-resource language with the compiled-only runtime
  resource contract and separate source/output manifest requirement.
- Added explicit injected-bundle composition semantics and the catalog's
  prohibition on default/global bundle lookup.
- Made clean-clone evidence execution-time only, made the final Chrome report
  authoritative against the final F candidate/full E baseline hash, and
  linked the canonical 420-point and A-harness real-guide prerequisites.
- Updated completion-audit rows so the new phase graph, resource boundary,
  CLI report types, identity flags, and evidence provenance are testable.
- Added the canonical full source-manifest scope/aggregate and explicit
  A-harness real-guide artifact prerequisite.
- Defined the exact per-variant build roots and authoritative clean-commit
  lineage, and added the tracked accepted-foundation artifact contract.
- Added the typed pair-eligibility API, explicit foundation artifact gate, and
  separate foundation-checkpoint versus current source-manifest evidence.
- Added distinct F bootstrap/post-acceptance build modes and portable
  `BuildProvenance` semantics with E-owned run/pair provenance; all documented
  invocations now carry the correct bootstrap constants or accepted foundation
  path. The quality script writes root-local measurement/run artifacts before
  invoking the report-path compare CLI. `BuildProvenance` now carries the
  exact build configuration, and authoritative run provenance requires the
  matching accepted-foundation artifact SHA.
- Made E-foundation Task 3c the owner of `PerformanceCLI` and
  `scripts/benchmark-quality.sh`; F-foundation only imports and wires the
  existing CLI, and E-execution consumes it for runtime evidence. Replaced the
  executable-import substring check with an external-module, symbol-aware
  compile and package-graph proof.
- Added the canonical `PerformanceFixtureProfile` values `standard12` and
  `dense1000`, exact current identifiers/versions/counts, separate
  measurement/pair/comparison/resilience outputs, and the typed Task 3c
  campaign-completion manifest. Both profiles are required by that manifest,
  keep populations separate, and apply the 16.7 ms gates independently.
  Recorded the current adapter boundary: the profile-aware model/renderer is
  implemented and tested; compositor/process/combined-frame/manual evidence
  remains honest fallback or schema-only until Task 3c/E-execution sidecars.

### E performance plan

- Added `PerformanceReportKind`, `reportKind` fields, wrong-kind/missing-kind
  structural tests, and exact source-identity validation rules.
- Clarified that the gesture benchmark is `GestureBenchmark.Result`; only the
  full quality commands produce measurement/comparison reports.
- Split E tasks 1–3 into an E-foundation contract gate and moved paired
  immutable execution/reconciliation to a post-F-foundation E-execution gate.
- Replaced ambiguous legacy identity-flag wording with the explicit 40-hex
  commit or 64-hex content-manifest alternatives, and documented the complete
  compare command.
- Added baseline eligibility, same-schema/harness requirements, F foundation
  dependency, execution-time clean-status rule, typed provenance artifact,
  measured-only comparison preflight, and diagnostic-only content-manifest
  measurements. The authoritative compare now requires typed pair eligibility
  and cannot be bypassed by a direct fabricated harness call. F's build
  provenance and E's run/pair provenance now have separate owners, and the
  pair count is `pairsPerOrder == 15` with derived `totalPairs == 30`; build
  provenance has no portable filesystem path. Added the v1 post-warmup
  least-squares RSS slope field and completion tolerance rule, plus full paired
  measurement identities, fixture equality, positive budgets/baselines, and
  exact nonempty arrays with canonical units, optional metric budgets, and
  recomputed ratio/p95 gates.
- Clarified that `memoryRSS` comparison samples are strictly positive absolute
  RSS bytes while signed final-window delta and post-warmup slope remain
  preflight-validated measurement fields; added exact input-report SHA fields,
  writer verification, and renderer-plus-compositor/`combinedFrame` p95 gates.
- Made hash-free `PerformanceComparisonDraft` the internal output of
  `compare(...:pairExecutionArtifact:manualEvidenceDirectory:pairExecutionArtifactSHA256:...)`, with Task 3
  manual-evidence/artifact loading and validation before draft production; the public draft-plus-URL
  `writeComparison` accepts only a public `Sendable, Equatable` opaque carrier with no public
  initializer or stored properties, and injects report kind, schema version,
  and hashes derived from exact input bytes before atomic persistence. Its
  injection and mismatch tests prove
  identity/fixture/provenance/eligibility failures leave no output.
- Added v1 raw timing arrays with measured exact-trial/finite-positive/p95
  recomputation rules, typed 15+15 `PairOrder` sequencing, deterministic
  bootstrap tamper rejection, and the explicit `improvementClaimed` rule.
- Added exact `PerformanceHarness.run` provenance inputs, value-type-capable
  adapters, raw-frame missed-sample counting, indexed/interleaved pair-execution
  artifacts, and identity-bound manual compositor/input evidence. Missing,
  failed, or unmeasured required metrics now structurally require `revise`,
  never `blocked` or `acceptedNoRegression`; comparison rejects them before
  constructing or writing output.
- Finalized canonical sorted-key artifact/manual-evidence production and
  fail-closed unknown-field, whitespace, and key-order validation; procedure
  equivalence is shared ordered steps, permissions, evidencePath, and
  procedureVersion.
- Added canonical fixture-profile identity/version/count bindings through
  `PerformanceConfiguration` and `FixtureIdentity`, per-profile output roots,
  the Task 3c campaign-completion manifest, and independent 16.7 ms gates.
  Task 3b records current adapter fallbacks and Task 3c/E-execution owns the
  external trace/process/manual sidecars; `CACurrentMediaTime` is not treated
  as WindowServer timing and combined-frame is not a sum.

### F integration plan

- Made `resourceBundle` explicit in the composition factory and documented
  one-bundle identity from root through catalog and guide.
- Clarified the model-only benchmark versus full-quality report branches and
  required all quality command arguments.
- Replaced raw guide-resource copying with `Assets.car` plus the
  byte-identical identity JSON, separated source and runtime manifests, and
  required raw-asset absence and idempotence checks.
- Gated F tasks 1–3 on E-foundation and F tasks 4–7 on E-execution; added
  execution-time clean-clone observation and prerequisite checks.
- Required the final Chrome friction rerun to use the final F candidate and
  full E baseline hash, while retaining the D checkpoint only as provenance.
- Expanded the literal source-manifest recipe, resolved raw-asset absence with
  an explicit grouped `-P` predicate for nested `*.png`, `*.imageset`, and
  `*.xcassets` cases, added nested sentinel coverage, exact per-variant output
  roots, the explicit foundation-provenance loader, and ordered final
  clean-clone identity artifact.
- Added F ownership for foundation/provenance artifacts and parameterized all
  manifest output paths by the explicit build output root. Added explicit
  build-provenance validation and direct built-executable smoke before
  `verify.sh` in clean-clone order. Clean-clone now captures canonical input
  cleanliness before writes and keeps temporary evidence under `$fixture`.
- F retains the exact E measurement reports used to compute the comparison and
  verifies their persisted SHA fields; final completion also enforces the
  renderer-plus-compositor and `combinedFrame` 16.7 ms p95 gates.
- F's launcher/CompletionMatrix uses the exact draft-plus-URL writer boundary;
  `--manual-evidence-dir` binds directly to the internal draft seam and writer.
  Deterministic runs require an existing empty directory, decoded comparison
  construction remains deferred and hash-free, only the writer injects report
  metadata and hashes and persists atomically, and the composition API boundary
  is accepted by an external-module/symbol-aware compile proof rather than a
  source substring search.
- F's completion tests retain those raw-array, pair-order, bootstrap, and
  improvement-claim checks as final acceptance conditions.
- F retains and validates the interleaved pair-execution artifact, pairs by its
  recorded indices, and rejects unbound manual evidence or artifact mismatches.
- F-final now validates Task 3c's typed campaign-completion manifest, links
  both fixture-profile evidence sets at separate roots, rejects
  missing/cross-profile artifacts, and preserves current E adapter
  `.unmeasured`/`revise` fallbacks until Task 3c/E-execution supplies external
  sidecars.

## Remaining unknowns and explicit follow-up

- The exact Swift property/API names for the provenance and foundation value
  types remain implementation decisions inside E's owned diagnostics scope;
  the wire contracts, typed fields, and cross-report equality rules are fixed.
- The exact output directory for runtime provenance files remains an
  implementation detail, but each variant must have an immutable run envelope
  and the CLI must receive its `--run-provenance-file` path.
- Launch Services and WindowServer behavior remain host-dependent. F must
  record failures or unsupported observations as evidence gaps; it must not
  convert them into deterministic passes.
- Physical VoiceOver, display/Space, reconnect, denied-permission, and
  long-session evidence still require a capable host and direct manual use.

No commit was created by this reconciliation task. The coordinating agent
must run the document consistency checks and obtain the required worker,
reviewer, and adversarial gates before treating these plans as accepted.
