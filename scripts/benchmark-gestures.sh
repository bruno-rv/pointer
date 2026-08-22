#!/bin/bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
root_dir="$(cd -- "$script_dir/.." && pwd -P)"
executable="$root_dir/build/Pointer.app/Contents/MacOS/Pointer"

fail() {
    echo "benchmark-gestures.sh: $*" >&2
    exit 1
}

[[ "$(uname -s)" == "Darwin" ]] || fail "macOS is required"
[[ "$(uname -m)" == "arm64" ]] || fail "Apple silicon (arm64) is required"

"$script_dir/build-app.sh" >/dev/null
[[ -x "$executable" ]] || fail "Release executable is missing: $executable"

report="$("$executable" --benchmark-gestures --format json)"
expected_publications="[2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2]"

[[ "$report" == *'"fixtureMarkCount":12'* ]] || fail "fixture mark count gate failed"
[[ "$report" == *'"samplesPerGesture":240'* ]] || fail "sample count gate failed"
[[ "$report" == *'"buildConfiguration":"release"'* ]] || fail "Release configuration gate failed"
[[ "$report" == *'"trialCount":30'* ]] || fail "trial count gate failed"
[[ "$report" == *'"warmupCount":5'* ]] || fail "warmup count gate failed"
[[ "$report" == *'"publicationsPerGesture":'"$expected_publications"* ]] || \
    fail "publication boundary gate failed"
[[ "$report" == *'"modelChecksum":"882b4fb5d86096de"'* ]] || \
    fail "model checksum gate failed"
[[ "$report" == *'"checksumIsStable":true'* ]] || fail "checksum stability gate failed"
[[ "$report" == *'"finalStateValid":true'* ]] || fail "final state gate failed"
[[ "$report" == *'"rendererTimed":false'* ]] || fail "renderer scope gate failed"
[[ "$report" == *'"compositorTimed":false'* ]] || fail "compositor scope gate failed"

printf '%s\n' "$report"
