# Pointer E/F specification reconciliation

Date: August 31, 2026

Status: Reconciled for implementation planning. This report records the
cross-document decisions applied to the six-month design, E performance plan,
and F integration plan. It is a specification artifact only; it does not
claim that E/F implementation or physical evidence exists.

## Decisions made

| Concern | Reconciled contract |
| --- | --- |
| Diagnostic report boundary | `Pointer --benchmark-gestures --format json` remains the model-only serialized `GestureBenchmark.Result`. `--quality-performance --format json` emits one typed `PerformanceMeasurementReport`; `--quality-compare --format json` emits one typed `PerformanceComparisonReport`. Scripts orchestrate the two full-quality commands. |
| Report typing | E defines `PerformanceReportKind` with `measurement` and `comparison` cases. Each report carries the matching typed `reportKind`; structural validation and tests reject missing or wrong kinds. |
| Source identity | A single measurement accepts exactly one `--source-commit-sha <40hex>` or `--content-manifest-sha256 <64hex>`. A clean tree uses the commit identity; a dirty tree uses the full content-manifest identity. Both, neither, malformed, symbolic, or stale identities are rejected. The authoritative paired comparison accepts clean commit identities only and requires explicit baseline/candidate roots, commit SHAs, foundation provenance, manual-evidence directory, and output directory. |
| Source-manifest scope | E and F use the same Git-tracked scope: `Package.swift`, `Sources/**`, `Tests/**`, `scripts/**`, `Bundle/Assets.xcassets/**`, bundle identity/Info.plist files, and the master plus six phase plan/design inputs. Sorted `<sha256>  <relative-path>` rows produce the aggregate SHA; generated reports/build products/signature metadata/mtimes/absolute paths/untracked files are excluded. |
| Baseline eligibility | Authoritative baseline and candidate use the same E schema/harness/fixture, typed harness/foundation/build-contract versions, F launcher/build foundation, and host. The baseline is pinned only after the F-foundation checkpoint; both refs are clean 40-hex commits, baseline is an ancestor of candidate, and both are descendants of the foundation checkpoint. Content-manifest measurements remain diagnostic-only. |
| Per-variant roots | F's build helper accepts `--output-root <root>` and emits exactly `<root>/Pointer.app`, `<root>/source-manifest.sha256`, `<root>/bundle-manifest.sha256`, and build-only `<root>/provenance.json` containing portable `BuildProvenance`, including exact `buildConfiguration` (`release` authoritative; `debug` bootstrap diagnostic), with no path or pair ancestry; E creates `build/baseline` and `build/candidate`, writes each `<root>/measurements/measurement.json` and `<root>/run-provenance.json`, passes the accepted foundation path to both post-acceptance builds, and consumes those exact paths for repeat/idempotence comparisons. |
| Foundation checkpoint | F tasks 1–3 produce tracked `.codex/sdd/reports/quality-campaign/foundation/accepted-foundation.json` with fixed identity/version/hash/acceptance fields. The worker, reviewer, and adversarial gates must accept it before E-execution. E and clean-clone receive it through explicit `--foundation-provenance`; loaders validate hashes and derive foundation/harness/build-contract versions without hidden environment state. |
| Provenance | F build roots contain portable typed `BuildProvenance` only (source/executable/bundle hashes, exact build configuration, foundation/version fields, optional accepted-artifact SHA, and no path or pair ancestry); E `benchmark-quality.sh` is the sole creator of per-variant `PerformanceRunProvenance` and `PerformancePairEligibility`, consuming two validated build artifacts plus roots/refs/foundation. An authoritative run requires nonnil 64-hex `acceptedFoundationArtifactSHA256` matching its embedded build and accepted artifact; bootstrap diagnostics may leave it nil. The app embeds validated build/run artifacts after syntax/hash checks, while the script proves Git cleanliness, ancestry, and checkout-to-binary correspondence. |
| Memory slope | E v1 `MemoryMeasurement` carries `postWarmupSlopeBytesPerSecond`, computed by ordinary least squares over post-warmup running RSS samples; structural validation requires finite values, and completion rejects growth above the exact `1e-9` B/s tolerance. |
| Resource boundary | Runtime ships only the executable, `Info.plist`, compiled `Contents/Resources/Assets.car`, and byte-identical `Contents/Resources/GuideAssetIdentity.json`. Raw PNG files and any `*.imageset` or `*.xcassets` file/directory anywhere under Resources fail the bundle contract. Source-input and bundle-output manifests are separate and both are compared across repeat builds and clean clone. |
| Composition injection | `PointerCompositionRoot.make(resourceBundle: Bundle = .main)` is the sole default selection point. It loads `GuideAssetIdentity.json` and passes that same explicit bundle to `GuideAssetCatalog`; the catalog never calls `Bundle.main`, uses a default bundle, or performs global lookup. |
| Phase order | `A-foundation → B-core → C → D → B-render-integration → A-harness → E-foundation (tasks 1–3) → F-foundation (tasks 1–3) → E-execution → F-final (tasks 4–7)`. E foundation defines contracts before F; paired execution waits for F; F final consumes reconciled E reports. |
| Clean clone | Canonical input cleanliness is captured before any source-root write, excluding generated reports/build products and the final evidence output; temporary evidence stays under `$fixture`. The script validates `checkpointCommitSHA` and foundation/current manifests, build provenance, then tests, directly invokes the built executable with `--smoke --format json`, and runs `verify.sh`; it atomically publishes final `CleanCloneIdentity.md` on success or failure, and an immediate rerun must remain reproducible. |
| Chrome friction | F reruns the authoritative `ChromeFrictionReport` against the final F candidate and records the full immutable E baseline hash. D's Chrome checkpoint is historical provenance only and is never silently relabeled as final evidence. |
| Pair eligibility | E defines typed `PerformancePairEligibility`/validated foundation provenance arguments. The CLI/script constructs eligibility only after root/ref/clean/head/ancestry/foundation checks and exact `pairsPerOrder == 15`/derived `totalPairs == 30`; the harness revalidates report/provenance equality and direct fabricated eligibility cannot bypass it. |
| Measurement identities | `PerformanceComparisonReport` carries full `baselineMeasurementIdentity` and `candidateMeasurementIdentity` values, plus equal persisted `baselineFixture`/`candidateFixture` values matching the measurement reports. Pair preflight requires exact equality for host model, macOS, Xcode, developerDirectory, power/display state, and buildConfiguration; source commits remain distinct and provenance-matched. Every metric has its canonical `PerformanceMetricUnit`, finite strictly positive baseline/candidate samples, and nonempty ratio/delta arrays of exactly `totalPairs` entries. It also carries lowercase 64-hex `baselineMeasurementReportSHA256` and `candidateMeasurementReportSHA256` values computed from and verified against the exact input report bytes before the comparison is written; F retains those input reports unchanged. For `memoryRSS`, comparison samples are strictly positive absolute RSS bytes; signed `finalWindowDeltaBytes` and `postWarmupSlopeBytesPerSecond` (B/s) remain measurement-report fields validated during pair preflight, not comparison sample units. |
| Metric budgets | `budgetLimit` is optional and canonical: 16.7 milliseconds for `combinedFrame`, 100 milliseconds for `responsiveness` and `inputToVisible`, nil for other metrics, and never an absolute RSS p95 for `memoryRSS`. Completion recomputes ratio median/p95 ≤1.10 and candidate p95 only for the three budgeted metrics. It also requires candidate renderer p95 plus compositor p95 ≤16.7 milliseconds and candidate `combinedFrame` p95 ≤16.7 milliseconds; wrong, huge, missing, or unexpected budgets/units are rejected. |
| Comparison writer boundary | Public persisted entry is the exact `writeComparison(draft:baselineURL:candidateURL:outputDirectory:configuration:eligibility:)`: it accepts a hash-free `PerformanceComparisonDraft`, reads exact measurement bytes from the URLs, computes/verifies the lowercase 64-hex report hashes, decodes, cross-checks the draft, injects the hashes into the final `PerformanceComparisonReport`, performs full preflight, and writes atomically only after validation. Internal `compare(baseline:candidate:configuration:eligibility:manualEvidenceDirectory:)` returns only that draft after Task 3 loads/validates manual evidence; it is the deferred, non-writing calculation seam and makes no hash-verification claim. Any hash, identity, fixture, provenance, or eligibility mismatch produces no output. |
| Comparison semantics | Structurally valid measurement reports may preserve failed/unmeasured statuses for diagnosis, but authoritative comparison first verifies typed eligibility from the shell's roots/refs/foundation checks and then rejects any failed/unmeasured required input before constructing or writing a comparison; the CLI consumes only `--baseline-report`, `--candidate-report`, `--pair-eligibility-file`, `--manual-evidence-dir`, and `--output-dir`, passes `--manual-evidence-dir` to internal `compare(...:manualEvidenceDirectory:)` for Task 3 loading/validation, and persists measured comparisons only through the public writer. |
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
  `compare(...:manualEvidenceDirectory:)`, with Task 3 manual-evidence loading
  and validation before draft production; the public report-plus-URL
  `writeComparison` injects hashes derived from exact input bytes before atomic
  persistence. Its injection and mismatch tests prove
  identity/fixture/provenance/eligibility failures leave no output.

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
- F's launcher/CompletionMatrix uses the exact report-plus-URL writer boundary;
  `--manual-evidence-dir` is passed to the internal draft seam for Task 3
  loading/validation, decoded comparison construction remains deferred and
  hash-free, and only the writer injects hashes and persists atomically.

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
