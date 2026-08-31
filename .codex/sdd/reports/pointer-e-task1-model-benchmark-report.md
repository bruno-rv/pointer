# E Task 1: model benchmark evidence

## Scope

This task hardens the fixed `GestureBenchmark.Result` contract and its Release
gate. The benchmark remains model-only: it exercises the production
`PointerSession` gesture path, but does not measure AppKit rendering,
WindowServer composition, launch, allocations, or memory.

No production source was changed. The focused test now runs the default
benchmark configuration and checks the complete serialized shape. The Release
script now decodes the JSON with Foundation and validates typed fields,
top-level key identity, array lengths and values, positive finite trial/median/
p95 timings, non-negative finite MAD, publication boundaries, checksum/final
state, and model-only exclusions.

## Observed Release result

Command:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/benchmark-gestures.sh
```

Result: passed.

| Contract | Observed value |
| --- | --- |
| Fixture marks | 12 |
| Continuation samples | 240 |
| Warmups | 5 |
| Measured trials | 30 |
| Median | 139812.5 ns |
| p95 | 149417 ns |
| MAD | 1229 ns |
| Publications per gesture | 30 entries, each `2` |
| Model checksum | `882b4fb5d86096de` |
| Checksum stable | `true` |
| Final state valid | `true` |
| Renderer timed | `false` |
| Compositor timed | `false` |

The validator also confirmed the exact 15-key `GestureBenchmark.Result`
schema. `reportKind`, `schemaVersion`, and `fullSchemaVersion` are absent;
full-quality reports remain separate `--quality-performance` and
`--quality-compare` products.

The MAD validator accepts an exact zero (absolute deviation can legitimately
be zero), rejects negative values, and rejects non-finite JSON input. The
focused regression fixture covers all four cases.

## Verification

- TDD RED: a temporary `trialCount == 29` assertion failed with the observed
  value `30`; it was restored to the required literal before GREEN.
- Focused GREEN:
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter GestureBenchmarkTests`
  — 2 tests, 0 failures.
- Full suite:
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
  — 341 tests, 0 failures.
- Build:
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`
  — passed.
- Shell syntax and whitespace:
  `bash -n scripts/benchmark-gestures.sh` and `git diff --check` — passed.

## F handoff

The current script invokes the existing `scripts/build-app.sh` contract with
no foundation metadata arguments. F's accepted build contract will add the
bootstrap/post-acceptance foundation arguments and compiled resource path;
F should update the orchestrated invocation when that contract lands. This
task intentionally does not edit F-owned build or launcher files.
