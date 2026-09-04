# Pointer performance campaign

This directory (`.codex/sdd/reports/quality-campaign/performance/<profile>`) is
the evidence root for one fixture profile at a time. The
benchmark-quality.sh orchestrator is deliberately narrow: an invocation
accepts exactly one standard12 or dense1000 profile, keeps baseline and
candidate build roots separate, and never concatenates their samples. This
pre-F implementation is diagnostic-only: it finalizes measurement evidence and
never invokes compare or publishes a completion manifest.

## Orchestrator contract

The script requires:

- distinct, lowercase 40-hex --baseline-commit-sha and
  --candidate-commit-sha values;
- built, executable Pointer.app binaries under the exact physical roots
  `<repo>/build/<fixture-profile>/baseline` and
  `<repo>/build/<fixture-profile>/candidate` (or explicit executable paths
  within those roots);
- explicitly supplied, non-empty, already validated baseline/candidate run
  provenance files and the profile-scoped pair eligibility file; and
- an output directory exactly at
  `<repo>/.codex/sdd/reports/quality-campaign/performance/<fixture-profile>`.
  The build roots and output directory must derive from the same repository
  root; legacy `evidence/<profile>` destinations are rejected before any
  directory is created.
The validated pair eligibility input is always the profile-scoped
`<profile-evidence>/comparisons/pair-eligibility.json`; campaign-root aliases
are rejected.
The pre-F script rejects `--foundation-provenance` and
`--manual-evidence-dir`; those belong to the later authoritative gate.

For test or harness injection, --runner <executable> receives the selected
Pointer executable as its first argument and the exact CLI arguments after it.
Without --runner, the script executes each built Pointer binary directly. The
runner is an execution seam, not a way to bypass provenance or eligibility
requirements. Baseline trials always route through the physical baseline
executable, candidate trials always route through the physical candidate
executable, and finalization routes through the candidate executable.

Destination validation walks to the nearest existing physical ancestor and
rejects symlinked ancestors or aliases before creating any missing parent
directory. The derived pair-execution partial directory follows the same
physical-path check, so a symlink cannot redirect CLI-owned partials or staged
evidence outside the selected build/evidence roots.

Each invocation takes an exclusive profile lock before recovery or staging.
The lock is an exact seven-line record (`version`, shell `pid`, transaction,
child PID, child state, child token, and child process group); every read and
atomic write validates all field names, values, and state-dependent child
tuple combinations. A live owner fails without touching the existing journal,
pending tree, or evidence. A dead owner is treated as stale, allowing journal
recovery and lock takeover. The lock is removed by a normal or signal-handled
exit, while a killed process leaves it for the next invocation's stale-owner
check.
Stale-lock recovery has a separate profile-scoped recovery guard. Its durable
owner record includes the guard PID, transaction, exact stale-lock fingerprint,
and owner/child tuple. A contender must atomically acquire that guard, then
re-read and byte/fingerprint-compare the lock before removing anything; a
changed or newly live lock aborts recovery without mutation. A live guard
blocks other contenders. A dead guard is reclaimed only by atomically moving
it to a unique `.reclaimed.*` quarantine and validating it before cleanup.
The guard is released before normal lock creation, so concurrent stale
contenders have exactly one recovery winner and a loser cannot remove or
overwrite the winner's lock.
Each running CLI invocation is a tracked child in the lock. TERM and INT are
forwarded to its private process group and waited until the group is quiescent
before cleanup; stale takeover is refused while either the recorded shell
owner or its active child/process group is alive. Child startup records a
durable `starting` tuple before spawn, allocates a transaction- and
token-specific control namespace, and requires the wrapper to become its own
process-group leader (separate from the benchmark shell). The wrapper verifies
the live lock transaction/state and an unrevoked capability immediately before
publishing its owner/ready record and again before executing after the gate
release. A stale `starting` owner atomically revokes and moves that token
namespace; any delayed wrapper therefore fails closed without an owner record,
executable, or late mutation. If an owner record exists, its group is killed
and waited before recovery. Recovery then renames the revoked namespace to a
deterministic `.cleanup.<token>` tombstone and syncs that rename before
deleting its gate, owner, capability, and revocation files. The tombstone is
resumable after a crash at any cleanup step; simultaneous, malformed, or
unexpected recovery namespaces fail closed. Every atomic child-state lock
rename is followed by a durable sync of the lock file and containing
directory. The test harness uses separate readiness/completion FIFOs so child
diagnostics cannot be mistaken for synchronization.

For global pair indices 0...14, the script invokes one baseline trial followed
immediately by its candidate trial with --pair-order baselineFirst. For
indices 15...29, it invokes candidate then baseline with
--pair-order candidateFirst. Every trial carries the selected profile, the
variant, global pair index, source commit, run provenance, and the CLI-owned
partial path
build/<fixture-profile>/pair-execution/partial/<pairIndex>.json, derived by the
CLI from the selected profile's partial directory.
Trials do not receive an output directory or a request sidecar; the CLI owns
the canonical partial contents.

After all 60 trial calls, the script invokes exactly one
quality-performance --format json --operation finalize operation with the
partial directory, both run-provenance files, pair eligibility, and one staged
selected-profile evidence directory. Finalization
must produce:

    <profile-evidence>/measurements/{baseline,candidate}.json
    <profile-evidence>/pair-execution/pair-execution.json

The script stops after this diagnostic finalizer. It does not invoke
--quality-compare or write a campaign completion manifest before F's
authoritative gate.

The partial directory is never cleared by the shell. Re-running the same
command forwards the same canonical paths to the CLI's idempotent partial
store, which owns retry/conflict semantics. The shell does not fabricate JSON
sidecars or reinterpret partial contents.

The release-proof test records the script's exact finalizer argv, replaces the
fake partials with 30 canonical typed partial artifacts, recreates the
script-derived pending output with its three-file preseed, and replays that
argv through `PerformanceCLI.run`. It verifies the real reports and pair
artifact are produced at the recorded path and that no internal pending
directory remains. The fake runner continues to cover shell ordering and
argv forwarding; it is not the evidence for Swift finalization.

The transaction journal is written in the profile evidence parent before the
pending tree is created. It records the pending and backup paths and whether a
destination existed, so an interrupted pre-finalization run can discard
incomplete pending state while preserving the old destination.

The complete diagnostic profile directory is staged outside the requested
evidence path with immutable copies of `provenance/{baseline,candidate}.json`
and `comparisons/pair-eligibility.json`, then atomically renamed into place only
after all finalizer output exists. The only allowed diagnostic root entries are
`provenance`, `comparisons` (eligibility only), `measurements`, and
`pair-execution`; manual evidence is not accepted here. The staged tree must
contain exactly those four physical directories and exactly six regular,
non-symlink, well-formed JSON files: the two provenance files, the eligibility
file, the two measurement reports, and `pair-execution/pair-execution.json`.
Any extra, missing, symlinked, non-regular, or invalid JSON entry
stops the run before publication. Canonical serialization is owned by the real
`PerformanceCLI` finalizer and is covered by the release-proof integration
test; this shell gate only checks the staged tree's physical shape and JSON
well-formedness. Successful pre-publish hooks are followed by a complete staged
revalidation, and successful post-rename hooks are followed by a complete
installed-tree revalidation before commit. If the destination
already contains byte-identical evidence, the run is an idempotent no-op;
otherwise it refuses to overwrite existing evidence. A failed trial or
finalizer therefore cannot publish new or partial evidence, and existing
evidence remains byte-identical. Paths are passed as argv arrays; the script
does not use `eval`, does not create foundation/build sidecars, and does not
claim executable hash correspondence. A durable profile-scoped transaction
journal records the prepared, backed-up, and installed states before and after
each publication rename. If the process is killed after backup or installation,
the next invocation restores the previous evidence deterministically (or
removes an incomplete first install), then removes the pending tree, backup,
journal, and journal temporary file before running new trials.

## Current evidence boundary

Task3b's compositor, process, combined-frame, and manual adapters currently
report honest unmeasured values when the host cannot provide authoritative
instrumentation. A structurally valid measurement report with a required
failed or unmeasured metric retains that diagnostic status but has disposition
revise; it is not converted to blocked, acceptedNoRegression, zero, or a
fabricated timing. The later comparison path rejects failed or unmeasured
required inputs before constructing or persisting an authoritative comparison;
this script does not reach that path.

Consequently, a green deterministic model/renderer run is not physical
completion evidence. Do not add guessed WindowServer, process, memory, input,
or compositor sidecars to make a report pass.

## Live execution prerequisites

Authoritative execution and compare remain intentionally rejected until
F-foundation has accepted all three tasks and produced the tracked foundation
artifact. Before promoting this diagnostic evidence, F must provide:

1. launcher branches for --quality-performance and --quality-compare;
2. the profile-specific Release build contract and portable provenance.json;
3. clean, ancestry-checked baseline and candidate source refs;
4. accepted foundation provenance passed to both builds;
5. typed per-variant run provenance and pair eligibility accepted by the CLI;
6. real physical/manual evidence for required OS-level metrics, with
   unsupported metrics remaining unmeasured and the disposition remaining
   revise; and
7. the explicit F-owned executable/build/hash and lineage checks. This script
   deliberately does not perform those checks or claim them.

The two profiles are run as separate invocations. A campaign completion
manifest belongs to the later post-F execution gate and must link exactly one
accepted comparison for each profile; this Task3c script does not claim that
manifest or claim performance completion.
