# Pointer E/F specification reconciliation

Date: August 31, 2026

Status: Reconciled for implementation planning. This report records the
cross-document decisions applied to the six-month design, E performance plan,
and F integration plan. It is a specification artifact only; it does not
claim that E/F implementation or physical evidence exists.

## Decisions made

| Concern | Reconciled contract |
| --- | --- |
| Diagnostic report boundary | `Pointer --benchmark-gestures --format json` remains the model-only serialized `GestureBenchmark.Result`. `--quality-performance --format json --operation trial` constructs a strict schema-version-1 request from flags plus validated provenance/eligibility, performs one scalar sample per metric after five local warmups, and atomically updates the derived partial under its directory; it has no request file or trial output directory. `--operation finalize` takes one partial directory, two provenance files, pair eligibility, and one profile evidence output directory, requires exactly 30 complete partials, aggregates all metric scalars with model-checksum agreement, and derives `measurements/{baseline,candidate}.json` plus `pair-execution/pair-execution.json`, written last. `--quality-compare --format json --fixture-profile <standard12|dense1000>` emits one typed `PerformanceComparisonReport` for the same profile only after F-foundation and typed external sidecars. |
| Report typing | E defines `PerformanceReportKind` with `measurement` and `comparison` cases. Each report carries the matching typed `reportKind`; structural validation and tests reject missing or wrong kinds. |
| Source identity | A single measurement accepts exactly one `--source-commit-sha <40hex>` or `--content-manifest-sha256 <64hex>`. A clean tree uses the commit identity; a dirty tree uses the full content-manifest identity. Both, neither, malformed, symbolic, or stale identities are rejected. For a content-manifest diagnostic, the selected 64-hex value binds the build source manifest while `PerformancePairEligibility` binds the corresponding commit through the run's 40-hex `sourceRef`; the hash is never compared directly to an eligibility commit. The authoritative paired comparison accepts clean commit identities only and requires explicit baseline/candidate roots, commit SHAs, foundation provenance, manual-evidence directory, and output directory. |
| Source-manifest scope | E and F use the same Git-tracked scope: `Package.swift`, `Sources/**`, `Tests/**`, `scripts/**`, `Bundle/Assets.xcassets/**`, bundle identity/Info.plist files, and the master plus six phase plan/design inputs. Sorted `<sha256>  <relative-path>` rows produce the aggregate SHA; generated reports/build products/signature metadata/mtimes/absolute paths/untracked files are excluded. |
| Baseline eligibility | Authoritative baseline and candidate use the same E schema/harness/fixture profile, typed harness/foundation/build-contract versions, F launcher/build foundation, and host. The baseline is pinned only after the F-foundation checkpoint; both refs are clean 40-hex commits, baseline is an ancestor of candidate, and both are descendants of the foundation checkpoint. Content-manifest measurements remain diagnostic-only. |
| Per-variant roots | F's build helper accepts `--output-root <root>` and emits exactly `<root>/Pointer.app`, `<root>/source-manifest.sha256`, `<root>/bundle-manifest.sha256`, and build-only `<root>/provenance.json` containing portable `BuildProvenance`, including exact `buildConfiguration` (`release` authoritative; `debug` bootstrap diagnostic), with no path or pair ancestry. F owns clean/ref/ancestry/build-app/hash creation and supplies prevalidated build/provenance inputs; E's one-profile script consumes them and derives measurements under the selected profile evidence root plus `pair-execution/pair-execution.json`, with all paths physically contained and whole-profile publication atomic. |
| Foundation checkpoint | F tasks 1–3 produce tracked `.codex/sdd/reports/quality-campaign/foundation/accepted-foundation.json` with fixed identity/version/hash/acceptance fields. The worker, reviewer, and adversarial gates must accept it before E-execution. E and clean-clone receive it through explicit `--foundation-provenance`; loaders validate hashes and derive foundation/harness/build-contract versions without hidden environment state. |
| Provenance | F build roots contain portable typed `BuildProvenance` only (source/executable/bundle hashes, exact build configuration, foundation/version fields, optional accepted-artifact SHA, and no path or pair ancestry); F validates and supplies the build/run provenance and typed `PerformancePairEligibility`. The diagnostic script enforces its canonical path/JSON boundary and passes those inputs to `PerformanceCLI`, whose typed validators reject invalid provenance, eligibility, profile, or hash bindings before any partial. An authoritative run requires nonnil 64-hex `acceptedFoundationArtifactSHA256` matching its embedded build and accepted artifact; bootstrap diagnostics may leave it nil. F owns Git cleanliness, ancestry, checkout-to-binary correspondence, and hash proof; the app only validates and embeds typed artifacts. |
| Memory slope | E v1 `MemoryMeasurement` carries `postWarmupSlopeBytesPerSecond`, computed by ordinary least squares over post-warmup running RSS samples; structural validation requires finite values, and completion rejects growth above the exact `1e-9` B/s tolerance. |
| Resource boundary | Runtime ships only the executable, `Info.plist`, compiled `Contents/Resources/Assets.car`, and byte-identical `Contents/Resources/GuideAssetIdentity.json`. Raw PNG files and any `*.imageset` or `*.xcassets` file/directory anywhere under Resources fail the bundle contract. Source-input and bundle-output manifests are separate and both are compared across repeat builds and clean clone. |
| Composition injection | `PointerCompositionRoot.make(resourceBundle: Bundle = .main)` is the sole default selection point. It loads `GuideAssetIdentity.json` and passes that same explicit bundle to `GuideAssetCatalog`; the catalog never calls `Bundle.main`, uses a default bundle, or performs global lookup. |
| API boundary | F-foundation validates the importable composition boundary with a temporary external-module, symbol-aware `swiftc -typecheck` probe importing only `PointerComposition`/`PointerAppKit` and resolving `PointerCompositionRoot.make(resourceBundle:)`/`PointerComposition`; package-graph inspection proves `PointerCompositionTests` has no `Pointer` executable dependency. A source substring search is not acceptance evidence. |
| Phase order | `A-foundation → B-core → C → D → B-render-integration → A-harness → E-foundation (tasks 1–3, including Task 3c) → F-foundation (tasks 1–3) → E-execution → F-final (tasks 4–7)`. E-foundation defines and implements the CLI/script contracts before F; F-foundation imports and wires the existing CLI; paired execution waits for F; F-final consumes reconciled E reports. |
| Clean clone | Canonical input cleanliness is captured before any source-root write, excluding generated reports/build products and the final evidence output; temporary evidence stays under `$fixture`. The script validates `checkpointCommitSHA` and foundation/current manifests, build provenance, then tests, directly invokes the built executable with `--smoke --format json`, and runs `verify.sh`; it atomically publishes final `CleanCloneIdentity.md` on success or failure, and an immediate rerun must remain reproducible. |
| Chrome friction | F reruns the authoritative `ChromeFrictionReport` against the final F candidate and records the full immutable E baseline hash. D's Chrome checkpoint is historical provenance only and is never silently relabeled as final evidence. |
| Pair eligibility | F supplies the typed `PerformancePairEligibility` and validated build/run provenance after its clean/ref/ancestry/build/hash checks. The Task3c CLI/script fully revalidates those inputs before the first partial and enforces exact `pairsPerOrder == 15`/derived `totalPairs == 30`; the harness also revalidates report/provenance equality and direct fabricated eligibility cannot bypass it. |
| Fixture profile separation | E defines the canonical `PerformanceFixtureProfile` values `standard12` and `dense1000`, with versions `pointer-fixture-standard12/v1`/`pointer-fixture-dense1000/v1`, identifiers `pointer-standard-12-marks`/`pointer-dense-1000-marks`, and counts 12/1,000. Each one-profile invocation resolves all build and evidence paths under the same physical `<repo-root>`: `<repo-root>/build/<fixture-profile>/{baseline,candidate}` and `<repo-root>/.codex/sdd/reports/quality-campaign/performance/<fixture-profile>/{measurements,provenance,comparisons,resilience}/`, plus `pair-execution/pair-execution.json`; pair artifacts and comparisons are separate per profile. Task 3c's typed `PerformanceCampaignCompletionManifest` has fixed `standard12ComparisonPath`/`standard12ComparisonSHA256` and `dense1000ComparisonPath`/`dense1000ComparisonSHA256` entries containing exactly the repo-relative strings `.codex/sdd/reports/quality-campaign/performance/standard12/comparisons/paired-comparison.json` and `.codex/sdd/reports/quality-campaign/performance/dense1000/comparisons/paired-comparison.json`, plus lowercase 64-hex hashes, never absolute paths, exactly one accepted comparison per profile, and rejects missing, duplicate, or concatenated populations. Both entries must share the same baseline/candidate commits, accepted foundation identity, schema/harness/build-contract versions, and host lineage; only the fixture profile differs. Both profiles apply the 16.7 ms renderer-plus-compositor and combined-frame gates independently. |
| Measurement identities | `PerformanceComparisonReport` carries baseline/candidate configurations through their typed run provenance and equal persisted `baselineFixture`/`candidateFixture` values, each with matching `fixtureProfile`/`fixtureVersion`/`markCount`; one comparison is for one fixture profile only. Pair preflight requires exact equality for host model, macOS, Xcode, developerDirectory, power/display state, and buildConfiguration; source commits remain distinct and provenance-matched. Every metric has its canonical `PerformanceMetricUnit`, finite strictly positive baseline/candidate samples, and nonempty ratio/delta arrays of exactly `totalPairs` entries. It also carries lowercase 64-hex `baselineMeasurementReportSHA256` and `candidateMeasurementReportSHA256` values computed from and verified against the exact input report bytes before the comparison is written; F retains those input reports unchanged. For `memoryRSS`, comparison samples are strictly positive absolute RSS bytes; signed `finalWindowDeltaBytes` and `postWarmupSlopeBytesPerSecond` (B/s) remain measurement-report fields validated during pair preflight, not comparison sample units. |
| Timing arrays | E v1 exposes raw `frameMilliseconds`, redraw/layout `sampleMilliseconds`, `responseMilliseconds`, and input-to-visible `sampleMilliseconds`; measured reports require exactly `trialCount` finite strictly positive samples with recomputed p95, while failed/unmeasured diagnostics may use empty arrays. For measured frames, `missedFrameCount` equals the count of raw samples greater than 16.7 ms. |
| Pair execution artifact | `PerformancePairExecutionArtifact` JSON contains exactly `schemaVersion`, `baselineID`, `candidateID`, `baselineMeasurementReportSHA256`, `candidateMeasurementReportSHA256`, and `records` with 30 unique contiguous indexed records; records 0–14 are baseline-first and 15–29 candidate-first, each with sample indices and UTC start/end timestamps. Task3c trial operations write exactly 30 strict canonical `PerformancePartialPair` files as the only resumable state; before warmup/measurement, the store audits the whole partial directory, acquires an exclusive per-slot `.json.lock`, and rechecks the directory while holding that lock; finalization derives `measurements/{baseline,candidate}.json` and writes `pair-execution/pair-execution.json` last. The producer uses the canonical sorted-key encoder; `pairExecutionArtifactSHA256` is a separate draft/report field equal to SHA-256 of those canonical bytes and is recomputable from the embedded artifact. Unknown fields, alternate whitespace, key order, extra entries, or active locks reject before acceptance. Internal preflight validates measurement/configuration/eligibility only; internal compare validates the decoded artifact/order and separate SHA, while the public writer alone reads/validates canonical URL bytes. The validator requires each variant's start ≤ its own end, the first variant's end < the second variant's start, and each pair's second end < the next pair's first start. Mismatches produce no output. |
| Pair order and improvement | The artifact records are the sole observed `PairOrder` source: exactly 15 baseline-first and 15 candidate-first; E-foundation's `benchmark-quality.sh` handles one fixture profile per invocation and the campaign caller loops over both profiles. Each isolated trial performs five local warmups and emits one scalar metric sample with `sampleIndex == pairIndex`; identical retries are no-ops and conflicts reject. The validator recomputes bootstrap intervals from deltas/seed/resample count and rejects tampering; `improvementClaimed` is true only when the recomputed delta upper bound is strictly below zero, false otherwise, and `acceptedNoRegression` is not an improvement claim. `benchmark-quality.sh` never invokes compare or writes the manifest; after F foundation and typed sidecars, the F-owned authoritative caller invokes `PerformanceCLI` compare and writes the manifest. |
| Trial/finalize trust boundary | `PerformanceTrialRequest`, `PerformanceTrialMetricSample`, `PerformanceTrialResult`, and `PerformancePartialPair` are public strict canonical schema-version-1 JSON with exact fields: the request is minimal (`schemaVersion`, `fixtureProfile`, typed `variant`, `order`, `pairIndex`, `sampleIndex`); each metric sample carries `metricID`, `unit`, `status`, `value`, and `diagnostic`; and each result carries `sourceIdentity`, `runProvenanceSHA256`, `pairEligibilitySHA256`, `startedAtUTC`, `endedAtUTC`, `warmupCountExecuted`, all metric samples, and required `PerformanceModelTrialEvidence`/`PerformanceRendererTrialEvidence`. The provenance hash binds canonical provenance containing the source/executable/bundle artifact hashes; `PerformanceModelTrialEvidence` owns model checksum/publication/final-state values and `PerformanceRendererTrialEvidence` owns frame/instrumentation/semantic-pass values. The CLI constructs the request from flags plus validated provenance/eligibility; no separate request artifact or trial output directory exists. Before warmup/measurement, the store audits the whole partial directory, acquires an exclusive per-slot `<pairIndex>.json.lock`, and rechecks the directory while holding that lock; identical retries are no-ops, conflicts reject, and any partial-directory entry outside slots 0...29 rejects. Filenames have no order prefix and first/second order is enforced by the global index. Every canonical metric is emitted exactly once; unavailable metrics are `unmeasured` with nil value and a nonempty diagnostic, and all nullable metric/partial keys are encoded as explicit `null`. Finalize accepts one partial directory, the two provenance files, pair eligibility, and one profile evidence output directory; it requires exactly 30 complete partials, aggregates all metric scalars in sorted index order with unconditional model-checksum agreement, derives `measurements/{baseline,candidate}.json`, and writes `pair-execution/pair-execution.json` last. The pre-F diagnostic script performs 60 trials then finalize and stops; an F-owned authoritative caller must gate trial/finalize, sidecars, compare, and manifest until F foundation is accepted. Compare is not invoked and the fixed-profile hash-bound `PerformanceCampaignCompletionManifest` is not written in that diagnostic path. |
| Partial slot naming | The canonical partial directory uses only `<pairIndex>.json` filenames (no order prefix) for global slots 0...29; before warmup/measurement the store audits the whole directory, acquires an exclusive per-slot `<pairIndex>.json.lock`, and rechecks the directory while holding that lock. It enforces baseline-first 0...14 and candidate-first 15...29 and rejects any extra entry or active lock. |
| Authority ordering | `benchmark-quality.sh` never invokes compare or writes the manifest. After F foundation and typed sidecars, the F-owned authoritative caller runs validated trial/finalize orchestration first, then invokes `PerformanceCLI` compare and writes the completion manifest. |
| Diagnostic script boundary | Pre-F `benchmark-quality.sh` requires explicit F-supplied build roots, run-provenance files, and pair eligibility, accepts no foundation or manual-evidence arguments, copies provenance into staged profile evidence, and makes no checkout-to-binary hash-correspondence claim. Before the first trial it validates the logical output scope before creating any directory. All paths resolve under the same physical `$REPO`: `$REPO/build/<fixture-profile>/{baseline,candidate}` and `$REPO/.codex/sdd/reports/quality-campaign/performance/<fixture-profile>`; relative script arguments resolve from that root and direct CLI URL arguments must be canonical absolute paths under it. `PerformanceRunProvenance.outputRoot` is exactly `$REPO/build/<fixture-profile>/<variant>`, `PerformancePairEligibility.baselineRoot`/`.candidateRoot` are exactly `$REPO/build/<fixture-profile>/baseline`/`candidate`, and the partial directory is `$REPO/build/<fixture-profile>/pair-execution/partial`; direct legacy evidence roots are rejected. It canonicalizes and validates distinct non-symlink roots, then acquires a live-owner profile lock before recovery or staging; the lock remains held through trials, finalization, and publication. The starting gate durably records only a starting intent/token, shell PID, and transaction identity before any child is spawned; after spawning, the child enters a private readiness gate, and after readiness the profile lock records the child PID and child PGID/process-group identity before releasing that gate. A recorded running owner may be taken over only after its shell PID, child PID, and process group are dead and descendants are quiescent. If the lock remains in the unrecorded `starting` state, recovery does not guess wrapper liveness: it atomically revokes and quarantines that transaction's private capability namespace/token, and the wrapper must fail closed before publication, readiness-gate release, executable invocation, or mutation. The journal owns transaction state and paths. It validates the outside-root profile destination, exact `<profile-evidence>/comparisons/pair-eligibility.json`, and regular provenance files contained by their matching roots; default executable routing is `<variant-root>/Pointer.app/Contents/MacOS/Pointer`, explicit overrides remain executable/canonical/in-root, and an optional runner receives the selected executable followed by exact argv without `eval`. It rejects traversal, aliases/symlinks, profile mismatches, overlap, and out-of-root paths. The staged profile allowlist is exactly `provenance/{baseline,candidate}.json`, `comparisons/pair-eligibility.json`, `measurements/{baseline,candidate}.json`, and `pair-execution/pair-execution.json` beneath only those four root directories; manual, resilience, comparison, partial, lock, and extra entries are excluded. The shell checks only regular, non-symlink, well-formed JSON; `PerformanceCLI` finalization and its real integration test own the canonical sorted-key bytes for generated reports and the pair artifact. Publication is a crash-recoverable journaled transaction: after the scope check and live-owner lock, the script journals transaction state plus canonical staging/destination/backup paths and `had-existing` state before creating pending staging at `$REPO/.codex/sdd/reports/quality-campaign/performance/.benchmark-quality.pending.<fixture-profile>/<fixture-profile>`, then installs a fully validated profile through `prepared`, `backed-up`, and `installed` states before recording commit and removing backup/journal. Handled `INT`/`TERM` signals are forwarded to the child process group and awaited until descendants quiesce; each mutation-capable hook is awaited and followed by complete path/allowlist/JSON revalidation before commit. Recovery and signal cleanup handle dead owners in those journaled states by removing abandoned staging, restoring the prior profile, or resolving the installed destination from recorded state. A pending tree or backup with no journal is an orphan, not safely recoverable; only an empty pending tree may be removed, while nonempty orphan state is rejected as requiring recovery. It never accepts a half-published tree. `BenchmarkQualityScriptTests` covers the orphaned active-child/process-group lock, handled-signal group forwarding and descendant waiting, successful hook mutation revalidation, and the three pre-prepared, post-backup, and post-install crash windows. It performs 60 trials plus finalize for one profile and stops. |
| External sidecars | Public schema-version-1 `PerformanceExternalTrialSidecar` binds `PerformanceTrialRequest`, `sourceIdentity`, `runProvenanceSHA256`, `pairEligibilitySHA256`, and UTC bounds to exactly the ordered external metrics `compositor`, `combinedFrame`, `launchCold`, `launchWarm`, `allocations`, `redrawLayout`, `responsiveness`, and `inputToVisible`; each scalar always has `metricID`, `unit`, `status`, `value`, and `diagnostic`, with unavailable values encoded as explicit `null` plus a diagnostic. The trial CLI accepts optional `--external-trial-sidecar <path>`; when absent it supplies those eight metrics as honest `unmeasured` null-value entries. Public `PerformanceExternalAggregateSidecar` binds typed variant/profile/source/hash fields, exactly 30 ordered `resultSHA256s`, and full `MemoryMeasurement`/`ResilienceMeasurement`; finalize accepts optional `--baseline-external-aggregate-sidecar <path>` and `--candidate-external-aggregate-sidecar <path>`. When supplied, trial sidecars use exactly `$REPO/.codex/sdd/reports/quality-campaign/performance/<fixture-profile>/external/trials/<variant>/<pairIndex>.json`, and aggregate sidecars use exactly `$REPO/.codex/sdd/reports/quality-campaign/performance/<fixture-profile>/external/aggregate/<variant>.json`; alternate evidence roots and direct legacy paths are rejected. Before finalization accepts an existing external preseed, it audits every regular, non-symlink entry and binds each trial filename index to its request's `pairIndex`/`sampleIndex` plus the current variant source identity, run-provenance hash, and pair-eligibility hash; aggregate filenames must bind the current variant/profile and hashes as well. Stale, extra, or mismatched preseed files reject. An absent aggregate sidecar does not fabricate external evidence: memory falls back to in-process `memoryRSS` when available, while resilience remains `unmeasured` with disposition `revise`. Nullable keys, including scalar `value`/`diagnostic` and partial `baseline`/`candidate`, are never omitted and are encoded as explicit `null`. |
| Model evidence invariant | Every `PerformanceTrialResult` requires model and renderer evidence; finalization unconditionally requires model-checksum agreement within each variant, regardless of optional external sidecars. |
| Campaign completion operation | The F-owned authoritative caller invokes `--quality-campaign-complete --format json --standard12-comparison "$PWD/.codex/sdd/reports/quality-campaign/performance/standard12/comparisons/paired-comparison.json" --dense1000-comparison "$PWD/.codex/sdd/reports/quality-campaign/performance/dense1000/comparisons/paired-comparison.json" --output-file "$PWD/.codex/sdd/reports/quality-campaign/performance/campaign-completion/manifest.json"` from the physical repository root (`$PWD == $REPO`); `PerformanceCampaignCompletion.writeManifest` stores the exact repo-relative comparison paths, validates canonical paths, exact input hashes, shared campaign lineage, and writes the sorted-key manifest atomically. |
| Manual pair evidence | `ManualMetricEvidencePair` contains `procedureVersion`, typed `pairOrders`, and baseline/candidate `ManualMetricEvidence`; each entry binds variant, commit, measurement-report hash, pair-artifact hash, host, timestamp, permissions, exact steps, samples, result, and evidence path. Both variants use the same ordered steps, permissions, evidencePath, and shared procedureVersion, with exactly the matching compositor/input files. The canonical sorted-key encoder/adapter emits each file; unknown fields, alternate whitespace, or key order reject before decoding/acceptance. Identity or procedure mismatches reject. |
| Adapter reality | E-foundation Task 3b defines compositor/process/manual/combined-frame protocols with honest `.unmeasured`/`revise` fallbacks. The profile-aware model/renderer fixture implementation covers both standard12 and dense1000 with tests; the offscreen renderer is real CanvasView/CGContext, while WindowServer compositor, process, combined-frame, and manual writer paths are currently unmeasured/schema-only. `CACurrentMediaTime` alone is not WindowServer measurement, `combinedFrame` is not a renderer-plus-compositor sum, and the F-owned authoritative caller must provide accepted external trace/process/manual sidecars through the unchanged E CLI/writer seams. |
| Metric budgets | `budgetLimit` is optional and canonical: 16.7 milliseconds for `combinedFrame`, 100 milliseconds for `responsiveness` and `inputToVisible`, nil for other metrics, and never an absolute RSS p95 for `memoryRSS`. Completion recomputes ratio median/p95 ≤1.10 and candidate p95 only for the three budgeted metrics. It also requires candidate renderer p95 plus compositor p95 ≤16.7 milliseconds and candidate `combinedFrame` p95 ≤16.7 milliseconds for each fixture profile; wrong, huge, missing, or unexpected budgets/units are rejected. |
| Comparison writer boundary | Public persisted entry is the exact `writeComparison(draft:baselineURL:candidateURL:pairExecutionURL:manualEvidenceDirectory:outputDirectory:configuration:eligibility:)`: it accepts a hash-free `PerformanceComparisonDraft` plus the required existing manual-evidence directory and pair-execution URL, reads exact measurement bytes from the URLs, computes/verifies the lowercase 64-hex report hashes and canonical artifact bytes, decodes, cross-checks the draft and artifact, and writes atomically only after internal measurement/configuration/eligibility preflight and decoded artifact/manual-evidence validation; no overload omits either directory or artifact. The draft is public `Sendable, Equatable` opaque with no public initializer or stored properties and excludes `reportKind`, `schemaVersion`, and both input-report hashes; the writer owns and injects `reportKind == .comparison`, `schemaVersion == 1`, and those hashes. The CLI requires `--manual-evidence-dir` and binds it directly to both seams. Deterministic runs require that directory to be empty. Internal `compare(baseline:candidate:configuration:eligibility:pairExecutionArtifact:manualEvidenceDirectory:pairExecutionArtifactSHA256:baselineMeasurementReportSHA256:candidateMeasurementReportSHA256:)` returns only that draft after validating manual evidence and the decoded artifact with its separate SHA, including recomputing/validating the canonical artifact SHA. Exact input measurement-byte/source-URL hash verification remains public-writer-owned; it is the deferred, non-writing calculation seam. Any hash, identity, fixture, provenance, pair-artifact, or eligibility mismatch produces no output. |
| Comparison semantics | Structurally valid measurement reports may preserve failed/unmeasured statuses for diagnosis, but each such measurement report structurally requires disposition `revise`, never `blocked` or `acceptedNoRegression`; authoritative comparison first verifies typed eligibility from the shell's roots/refs/foundation checks and rejects any failed/unmeasured required input before constructing or writing any comparison. The CLI consumes only `--fixture-profile standard12|dense1000`, `--baseline-report`, `--candidate-report`, `--pair-eligibility-file`, `--pair-execution-artifact`, `--manual-evidence-dir`, and `--output-dir`; the writer reads the pair artifact URL and supplies its decoded value plus separate SHA to internal compare, which also receives the manual directory, and persists measured comparisons only through the public writer. |
| Final Task3c trust fixes | The public comparison writer validates canonical sorted-key pair-artifact bytes, serializes the persisted comparison with the same canonical encoder, and writes those bytes atomically. Direct `Codable` decoding of the public request/result/partial types enforces exact key sets. A dirty measurement uses the selected lowercase 64-hex build content-manifest identity, while pair IDs and eligibility remain bound to the 40-hex run `sourceRef` commit; separately scoped dirty pairs may share the content-manifest hash when those source-ref commits differ. Before measurement, the CLI canonical-decodes and validates every existing regular, non-symlink legal partial after a whole-directory audit and per-slot lock; final load repeats the audit. A retry with a sidecar must match the persisted external values, statuses, and containing interval. Campaign completion requires both comparison artifacts and the manifest to share one physical performance root under the same repository root; when `PerformanceCLI.run` invokes campaign completion, its `outputDirectory` argument must resolve to that containing physical repository root, not the performance directory itself. Both profiles must match complete build hashes/lineage and complete measurement environments. A supplied trial sidecar interval must contain the actual in-process `startedAtUTC`/`endedAtUTC` interval and never replace those persisted result timestamps. Finalizer tests use the real CLI finalize operation and individually valid lineage fixtures before cross-profile assertions; `acceptedNoRegression` is reserved for fully measured, valid metric/memory/resilience evidence, otherwise disposition is `revise`. |
| Required prerequisites | F-final requires accepted A-harness real-guide lifecycle evidence from `pointer-a-harness-lifecycle-report.md` and `pointer-a-harness-phase-report.md`, where the real `FirstUseGuideController`/panel is injected through controller start/stop/restart, plus the canonical 420-point narrow-display evidence. A static guide/catalog test or stale narrow-display report cannot substitute for either prerequisite. |

## Swift publish transaction

The Swift `PerformanceCLI` finalizer uses the same physical performance root
but a distinct publish transaction namespace. Its pending profile is exactly
`$REPO/.codex/sdd/reports/quality-campaign/performance/.<fixture-profile>.pending-<transactionID>`,
where `<transactionID>` is a UUID copied into the schema-version-1 journal at
`$REPO/.codex/sdd/reports/quality-campaign/performance/.benchmark-quality.transaction.<fixture-profile>`.
The journal records transaction state and canonical staging, destination,
backup, and `hadExistingOutput` paths. Recovery validates the journal's
canonical absolute paths and transaction-matching pending suffix before
acting. Any surviving staged profile must be a physical, exact-topology
profile containing only the four allowed root directories/files, with typed
provenance, eligibility, measurements, pair artifact, and optional external
evidence decoded and binding-validated. The backup is exactly
`$REPO/.codex/sdd/reports/quality-campaign/performance/.benchmark-quality.backup.<fixture-profile>/<fixture-profile>`.
Before a new transaction, any existing backup container must be physical and
empty. Recovery preflights a journaled backup as a physical container holding
only its recorded output; when restore moves that output out, it validates the
container is empty before removing it. During recovery, installed-state
cleanup removes the journaled backup container only after that preflight shape
check, and any extra
or malformed entry rejects. The `prepared`, `backed-up`, and `installed` crash
windows respectively remove abandoned staging or restore the prior output,
install validated staging or restore the backup, and resolve the output from
recorded `hadExistingOutput` plus backup state before deleting journal and
backup remnants. The reconciliation retains tests for all three crash windows:
pre-prepared, post-backup, and post-install.

The partial store captures the partial directory's `lstat` `(st_dev, st_ino)`
identity around reservation and write, rechecking the same device/inode after
slot-lock acquisition and immediately before the atomic partial write. A
directory replacement, symlink, non-directory, or identity change rejects.
Stale-start recovery is itself restartable: a valid existing
capability-revocation marker resumes the operation, and a valid deterministic
`.revoked.<token>` quarantine resumes and cleans it. Each marker, quarantine
rename, and cleanup transition is durably synced. The two recovery-of-recovery
SIGKILL tests cover both restart points.
After validating quarantine, recovery atomically renames it to the deterministic
`.cleanup.<token>` tombstone and durably syncs that transition.
The cleanup directory name is the authoritative resumable state: it permits
only these token-scoped entries: `gate`, `ready`, `owner`, `owner.tmp`,
`capability`, and
`capability.revoked` entries with their expected physical node types, accepts
any subset after partial deletion including a missing revocation marker, then
deletes the remaining allowed entries and the empty tombstone, durably syncing
each file-removal transition and the final cleanup. A live
namespace, `.revoked.<token>` quarantine, and `.cleanup.<token>` tombstone may
not coexist; malformed names, node types, symlinks, or extra entries reject.
Two additional mid-cleanup SIGKILL tests resume from the tombstone after
partial file deletion, including a missing revocation marker: one after a
generic allowed-file removal and one after revocation-marker removal.

When an existing profile lock appears stale, contenders serialize through the
durable guard
`$REPO/.codex/sdd/reports/quality-campaign/performance/.benchmark-quality.recovery.<fixture-profile>`.
The guard records its owner PID and transaction plus the exact observed lock
SHA-256 and complete observed owner tuple (shell PID, transaction, child,
state, token, and child PGID). While holding the guard, recovery re-reads and
re-fingerprints the exact stale lock and requires the tuple to remain identical
and every recorded owner/process group to remain dead before any mutation. A
changed, replaced, or newly live lock aborts without mutation; a live guard
blocks. A dead guard is reclaimed only by validating it and atomically renaming
it to the unique quarantine
`.benchmark-quality.recovery.<fixture-profile>.reclaimed.<oldTransaction>.<oldPID>.<newTransaction>`,
then durably cleaning that quarantine. After stale recovery, the guard is
released and contenders return to normal lock acquisition, so simultaneous
contenders allow exactly one publisher to proceed. The stale-guard SIGKILL
crash test verifies the reclaimed guard path before recovery resumes.

For the shell lock, a recorded running owner is recoverable only after its
shell PID, child PID, and process group are dead and descendants are quiescent.
An unrecorded `starting` wrapper is the sole liveness exception: it may still
be alive only after recovery atomically revokes and quarantines its
transaction-specific capability namespace/token and guarantees that it fails
closed before owner publication, readiness-gate release, executable
invocation, or mutation.

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
  `BuildProvenance` semantics. F-owned orchestration supplies the validated
  build/run provenance and pair eligibility; the E quality script consumes and
  revalidates those inputs before partial writes. All documented invocations
  now carry the correct bootstrap constants or accepted foundation path.
  `BuildProvenance` now carries the exact build configuration, and authoritative
  run provenance requires the matching accepted-foundation artifact SHA.
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
  remains honest fallback or schema-only until the F-owned authoritative caller
  supplies accepted external sidecars through the unchanged E CLI/writer seams.

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
  Task 3b records current adapter fallbacks; the F-owned authoritative caller
  supplies accepted external trace/process/manual sidecars through the
  unchanged E CLI/writer seams. `CACurrentMediaTime` is not treated as
  WindowServer timing and combined-frame is not a sum.
- Replaced the old per-trial contract with strict `--operation trial`
  and `--operation finalize` operations: five local warmups, one scalar sample,
  global `sampleIndex == pairIndex`, exactly 30 resumable partial pairs,
  idempotent retries, conflict rejection, generic all-metric scalar aggregation
  with model-checksum agreement, sorted final arrays, and the pair artifact
  written last. Requests are constructed from flags with strict provenance/
  eligibility validation before partial writes; no separate request artifact or trial output
  directory exists. A single-profile script is looped by the campaign caller;
  the pre-F diagnostic path performs 60 trials plus finalize and stops. The
  diagnostic script has no authoritative mode; an F-owned caller gates and
  invokes the unchanged E trial/finalize CLI before supplying typed external
  sidecars to compare and writing the manifest.
- Corrected the public trial wire to a minimal typed `PerformanceTrialRequest`
  using `PerformanceVariant`, plus rich `PerformanceTrialResult` fields for
  source identity, provenance/eligibility hashes, `startedAtUTC`/`endedAtUTC`,
  executed warmups, all `PerformanceTrialMetricSample` values, and required
  nested model/renderer evidence; canonical provenance remains the owner of
  source/executable/bundle artifact hashes.

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
  `.unmeasured`/`revise` fallbacks until the F-owned authoritative caller
  supplies accepted external sidecars through the unchanged E CLI/writer
  seams.
- F launcher acceptance now mirrors Task3c's exact trial/finalize operations
  and 30-partial finalization order; it does not treat trial output as a
  complete measurement report,
  an incomplete manifest lacking hashes, or diagnostic `revise` output as
  promotable evidence.
- Updated Task3c finalization to accept one profile evidence root and derive
  `measurements/{baseline,candidate}.json` plus
  `pair-execution/pair-execution.json`; F remains the owner of clean/ref/
  ancestry/build/hash inputs. Physical path containment and atomic whole-profile
  publication are required.

## Remaining unknowns and explicit follow-up

- The exact Swift property/API names for the provenance and foundation value
  types remain implementation decisions inside E's owned diagnostics scope;
  the wire contracts, typed fields, and cross-report equality rules are fixed.
- The profile evidence root and derived measurement/pair-artifact paths are now
  fixed by the canonical contract; each variant still requires an immutable
  run envelope and the CLI must receive its `--run-provenance-file` path.
- Launch Services and WindowServer behavior remain host-dependent. F must
  record failures or unsupported observations as evidence gaps; it must not
  convert them into deterministic passes.
- Physical VoiceOver, display/Space, reconnect, denied-permission, and
  long-session evidence still require a capable host and direct manual use.

No commit was created by this reconciliation task. The coordinating agent
must run the document consistency checks and obtain the required worker,
reviewer, and adversarial gates before treating these plans as accepted.
