# Stable source-build validation

## Run identity

- Date: 2026-08-22
- Branch: `codex/stable-app`
- Commit: `f6d3b2b` (`ci: verify the source-built Pointer app`)
- Observed host: Apple M5 Pro, `arm64`
- macOS: 26.6.2 (`25G83`)
- Xcode: 26.6 (`17F113`)
- Active developer directory for the captured checks: `/Applications/Xcode.app/Contents/Developer`
- Displays reported by `system_profiler SPDisplaysDataType`: one online `32G2WG8`, 1920x1080 at 240 Hz; no second physical display was connected for this run

The deployment target, CI images, and this physical host are separate pieces
of evidence. The package deployment target is macOS 14. GitHub Actions uses
public Apple-silicon `macos-15` as the durable lane and `macos-14` as the
temporary compatibility lane while it remains public; the latter retires on
2026-11-02. This host's macOS 26.6.2 observation does not establish coverage
for every supported macOS release, display arrangement, privacy state, or
full-screen application.

## Automated checks

| Check | Status | Exact evidence |
| --- | --- | --- |
| Focused RED | [x] | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter GestureBenchmarkTests` initially failed to compile because `GestureBenchmark` was not in scope. |
| Focused GREEN | [x] | The same command after implementation passed `GestureBenchmarkTests` with 1 test and 0 failures. |
| Full Swift suite | [x] | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed 55 tests with 0 failures. |
| Release bundle verifier | [x] | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/verify.sh` passed tests, bundle build, plist lint, ad-hoc signature verification, arm64 verification, smoke assertions, and printed `verification passed`. |
| Release gesture benchmark | [x] | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/benchmark-gestures.sh` passed its literal gates and emitted the JSON baseline below. |
| Diff whitespace | [x] | `git diff --check` passed before the Task 7 commit and again before the report-only amend. |
| GitHub Actions | [ ] | Workflow is configured but was not observed on GitHub from this local run. |

### Release benchmark baseline

The benchmark used the real `PointerSession` gesture path in a Release app
bundle, five warmups, 30 measured trials, 12 fixture marks, and 240
continuation samples. Timing is model-path timing only; renderer, compositor,
AppKit event dispatch, launch, and multi-display performance were not timed.

- Median: 145208.5 ns
- p95: 176125 ns
- MAD: 2959 ns
- Publications per gesture: 30 values, all `2` (begin and commit only)
- Model checksum: `882b4fb5d86096de`
- `checksumIsStable`: `true`
- `finalStateValid`: `true`
- `rendererTimed`: `false`
- `compositorTimed`: `false`

The benchmark is a production source-build baseline. It is not numerically
compared with the disposable mark-rendering prototype benchmark because those
measure different systems and scopes.

## Clean-clone gate

Status: [x] passed on commit `f6d3b2b` before the report-only commit update.

The required local gate will clone the candidate branch into a scoped temporary
directory, set the already-installed Xcode developer directory in the shell,
then execute the README commands literally:

```sh
clean_clone="$(mktemp -d /tmp/pointer-task7-clean-clone.XXXXXX)"
git clone --branch codex/stable-app \
  "$(git rev-parse --show-toplevel)" "$clean_clone"
cd "$clean_clone"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
./scripts/run-app.sh
./scripts/verify.sh
```

Observed clone: `/tmp/pointer-task7-clean-clone.P3d08R`.

The literal `./scripts/run-app.sh` command produced and opened
`build/Pointer.app`; its captured output ended with `built .../build/Pointer.app`.
The literal `./scripts/verify.sh` command passed all 55 tests, bundle checks,
smoke assertions, and ended with `verification passed`. Captured logs were
`/tmp/pointer-task7-clean-run.log` and `/tmp/pointer-task7-clean-verify.log`.
No remote push was involved.

## Physical-host evidence

Only directly observed behavior is checked. An unchecked row is an explicit
gap, not an implied pass.

| Physical check | Status | Evidence or exact gap |
| --- | --- | --- |
| Launches with visible palette in standby | [x] | `open build/Pointer.app` returned; the Pointer process was observed; `/tmp/pointer-task7-runtime.png` shows the palette over the browser and the visible `Standby — overlays are click-through` state on the single connected display. |
| Annotation toggle and Escape standby | [ ] | Not directly exercised in this run. |
| Arrow, rectangle, ellipse, pen, eraser, emoji, spotlight, and select flows | [ ] | Not directly exercised through physical pointer input. Automated model/UI tests do not substitute for this row. |
| Selection, resize, delete, undo, clear, swept erase | [ ] | Not directly exercised as a physical interaction sequence. |
| Palette relocation | [ ] | Not directly exercised. |
| Multiple connected displays and per-display overlays | [ ] | Host exposed one online display only; no multi-display claim is made. |
| Spaces and native full-screen behavior | [ ] | Not directly exercised. |
| Display disconnect/reconnect | [ ] | Not directly exercised. |
| Alternate shortcut, relaunch, conflict, and fallback | [ ] | Not directly exercised; no shortcut conflict was induced. |
| Accessibility, Input Monitoring, and Screen Recording denied | [ ] | TCC-denied runtime cases were not directly exercised. |
| DRM, secure UI, lock screen, or WindowServer guarantees | [ ] | Explicitly outside the source-build guarantee; not tested. |

## CI choice

`.github/workflows/verify.yml` has two explicit jobs:

- `macos-15`: durable public Apple-silicon lane.
- `macos-14`: temporary public Apple-silicon compatibility lane, documented
  with the 2026-11-02 retirement deadline.

Each job checks out with `actions/checkout@v4`, asserts `uname -m` is exactly
`arm64`, and runs `./scripts/verify.sh`. No `macos-latest`,
`macos-15-arm64`, or `macos-14-arm64` label is used, and no machine-specific
developer path is configured in CI.

## Scope and remaining concerns

The source-built milestone remains in-memory and does not provide saved
canvases, screenshots/exports, text, rotation, Intel support, Developer ID
signing, notarization, installer/update/downloadable-release packaging, or
DRM/secure-UI guarantees. The primary checkout's README was not modified.
