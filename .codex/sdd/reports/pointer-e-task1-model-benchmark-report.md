# E Task 1: model benchmark evidence

## Scope

This task hardens the fixed `GestureBenchmark.Result` contract and its Release
gate. The benchmark remains model-only: it exercises the production
`PointerSession` gesture path, but does not measure AppKit rendering,
WindowServer composition, launch, allocations, or memory.

No production source was changed. The focused test now runs the default
benchmark configuration and checks the complete serialized shape. The Release
script now decodes the JSON with Foundation and validates typed fields,
top-level key identity, duplicate-key rejection, array lengths and values,
positive finite trial/median/p95 timings, non-negative finite MAD, exact
median/nearest-rank p95/MAD recomputation, publication boundaries,
checksum/final state, and model-only exclusions.

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
| Median | 113375 ns |
| p95 | 123750 ns |
| MAD | 562.5 ns |
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

Both XCTest and the Release validator recompute aggregates from the 30 trial
samples using the benchmark's exact median, nearest-rank p95, and MAD
algorithms. Literal tampered-median, tampered-p95, and tampered-MAD fixtures
are rejected. The Release validator scans the raw top-level object before
Foundation decoding, rejects duplicate names including escaped-equivalent
`warmupCount`, and self-checks escaped strings plus nested arrays/objects.

## Verification

- TDD RED: a temporary `trialCount == 29` assertion failed with the observed
  value `30`; it was restored to the required literal before GREEN.
- TDD RED: aggregate assertions initially referenced missing recomputation and
  tamper-validation helpers; the compile failure was resolved by adding the
  independent literal algorithms and fixtures.
- Focused GREEN:
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter GestureBenchmarkTests`
  — 3 tests, 0 failures.
- Full suite:
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
  — 342 tests, 0 failures.
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
