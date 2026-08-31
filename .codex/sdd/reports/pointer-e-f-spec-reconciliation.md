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
| Per-variant roots | F's build helper accepts `--output-root <root>` and emits exactly `<root>/Pointer.app`, `<root>/source-manifest.sha256`, `<root>/bundle-manifest.sha256`, and `<root>/provenance.json`; E creates `build/baseline` and `build/candidate` and consumes those exact paths for repeat/idempotence comparisons. |
| Foundation checkpoint | F tasks 1–3 produce tracked `.codex/sdd/reports/quality-campaign/foundation/accepted-foundation.json` with fixed identity/version/hash/acceptance fields. The worker, reviewer, and adversarial gates must accept it before E-execution. E and clean-clone receive it through explicit `--foundation-provenance`; loaders validate hashes and derive foundation/harness/build-contract versions without hidden environment state. |
| Provenance | The script creates and validates a typed artifact with observed clean/dirty status, identity kind/value, full source-manifest SHA, executable SHA, bundle-manifest SHA, UTC timestamp, foundation identity/version, harness version, and build-contract version; it passes `--provenance-file`. The app embeds the artifact after syntax/hash checks, while the script proves Git cleanliness, ancestry, and checkout-to-binary correspondence. |
| Resource boundary | Runtime ships only the executable, `Info.plist`, compiled `Contents/Resources/Assets.car`, and byte-identical `Contents/Resources/GuideAssetIdentity.json`. Raw PNG files and any `*.imageset` or `*.xcassets` file/directory anywhere under Resources fail the bundle contract. Source-input and bundle-output manifests are separate and both are compared across repeat builds and clean clone. |
| Composition injection | `PointerCompositionRoot.make(resourceBundle: Bundle = .main)` is the sole default selection point. It loads `GuideAssetIdentity.json` and passes that same explicit bundle to `GuideAssetCatalog`; the catalog never calls `Bundle.main`, uses a default bundle, or performs global lookup. |
| Phase order | `A-foundation → B-core → C → D → B-render-integration → A-harness → E-foundation (tasks 1–3) → F-foundation (tasks 1–3) → E-execution → F-final (tasks 4–7)`. E foundation defines contracts before F; paired execution waits for F; F final consumes reconciled E reports. |
| Clean clone | Clean status, committed source identity, current source-manifest SHA, `checkpointCommitSHA`, foundation-checkpoint source-manifest SHA matched to the accepted artifact, timestamp, scoped checkout, exact commands/results, executable/bundle hashes, foundation versions, and cleanup outcome are observed and written in order to final `CleanCloneIdentity.md` at execution time. The invocation passes an explicit `--foundation-provenance` path; earlier evidence cannot satisfy or relabel the current run. |
| Chrome friction | F reruns the authoritative `ChromeFrictionReport` against the final F candidate and records the full immutable E baseline hash. D's Chrome checkpoint is historical provenance only and is never silently relabeled as final evidence. |
| Pair eligibility | E defines typed `PerformancePairEligibility`/validated foundation provenance arguments. The CLI/script constructs eligibility only after root/ref/clean/head/ancestry/foundation checks; the harness revalidates report/provenance equality and direct fabricated eligibility cannot bypass it. |
| Comparison semantics | Structurally valid measurement reports may preserve failed/unmeasured statuses for diagnosis, but authoritative comparison first verifies clean commit roots, exact heads, baseline ancestry, foundation ancestry, provenance, and then rejects any failed/unmeasured required input before constructing or writing a comparison; persisted comparison reports contain measured comparisons only. |
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
  and cannot be bypassed by a direct fabricated harness call.

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
  manifest output paths by the explicit build output root.

## Remaining unknowns and explicit follow-up

- The exact Swift property/API names for the provenance and foundation value
  types remain implementation decisions inside E's owned diagnostics scope;
  the wire contracts, typed fields, and cross-report equality rules are fixed.
- The exact output directory for runtime provenance files remains an
  implementation detail, but each variant must have an immutable artifact and
  the CLI must receive its `--provenance-file` path.
- Launch Services and WindowServer behavior remain host-dependent. F must
  record failures or unsupported observations as evidence gaps; it must not
  convert them into deterministic passes.
- Physical VoiceOver, display/Space, reconnect, denied-permission, and
  long-session evidence still require a capable host and direct manual use.

No commit was created by this reconciliation task. The coordinating agent
must run the document consistency checks and obtain the required worker,
reviewer, and adversarial gates before treating these plans as accepted.
