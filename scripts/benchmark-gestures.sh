#!/bin/bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
root_dir="$(cd -- "$script_dir/.." && pwd -P)"
executable="$root_dir/build/Pointer.app/Contents/MacOS/Pointer"
swift_bin="$(/usr/bin/xcrun --find swift 2>/dev/null || true)"

fail() {
    echo "benchmark-gestures.sh: $*" >&2
    exit 1
}

[[ "$(uname -s)" == "Darwin" ]] || fail "macOS is required"
[[ "$(uname -m)" == "arm64" ]] || fail "Apple silicon (arm64) is required"
[[ -x "$swift_bin" ]] || fail "swift is unavailable"

"$script_dir/build-app.sh" >/dev/null
[[ -x "$executable" ]] || fail "Release executable is missing: $executable"

report="$("$executable" --benchmark-gestures --format json)"

report_file="$(mktemp -t pointer-gesture-benchmark)"
trap 'rm -f -- "$report_file"' EXIT
printf '%s\n' "$report" > "$report_file"

if ! "$swift_bin" - "$report_file" <<'SWIFT'
import Foundation

struct BenchmarkResult: Decodable {
    let fixtureMarkCount: Int
    let samplesPerGesture: Int
    let buildConfiguration: String
    let trialCount: Int
    let warmupCount: Int
    let trialNanoseconds: [Double]
    let medianNanoseconds: Double
    let p95Nanoseconds: Double
    let madNanoseconds: Double
    let publicationsPerGesture: [Int]
    let modelChecksum: String
    let checksumIsStable: Bool
    let finalStateValid: Bool
    let rendererTimed: Bool
    let compositorTimed: Bool
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("benchmark-gestures.sh: \(message)\n".utf8))
    exit(1)
}

guard CommandLine.arguments.count == 2 else { fail("validator arguments are invalid") }
let reportURL = URL(fileURLWithPath: CommandLine.arguments[1])
let data: Data
do {
    data = try Data(contentsOf: reportURL)
} catch {
    fail("could not read benchmark JSON: \(error)")
}

let result: BenchmarkResult
do {
    result = try JSONDecoder().decode(BenchmarkResult.self, from: data)
} catch {
    fail("benchmark JSON does not match the model-only schema: \(error)")
}

guard let object = try? JSONSerialization.jsonObject(with: data),
      let dictionary = object as? [String: Any]
else {
    fail("benchmark JSON is not a top-level object")
}

let expectedKeys: Set<String> = [
    "buildConfiguration",
    "checksumIsStable",
    "compositorTimed",
    "finalStateValid",
    "fixtureMarkCount",
    "madNanoseconds",
    "medianNanoseconds",
    "modelChecksum",
    "p95Nanoseconds",
    "publicationsPerGesture",
    "rendererTimed",
    "samplesPerGesture",
    "trialCount",
    "trialNanoseconds",
    "warmupCount",
]
guard Set(dictionary.keys) == expectedKeys else {
    fail("benchmark JSON fields are not the exact model-only schema")
}

guard result.fixtureMarkCount == 12,
      result.samplesPerGesture == 240,
      result.buildConfiguration == "release",
      result.trialCount == 30,
      result.warmupCount == 5
else {
    fail("fixed fixture/trial configuration gate failed")
}

func isPositiveFinite(_ value: Double) -> Bool { value.isFinite && value > 0 }
func isNonNegativeFinite(_ value: Double) -> Bool { value.isFinite && value >= 0 }
guard result.trialNanoseconds.count == 30,
      result.trialNanoseconds.allSatisfy(isPositiveFinite),
      isPositiveFinite(result.medianNanoseconds),
      isPositiveFinite(result.p95Nanoseconds),
      isNonNegativeFinite(result.madNanoseconds),
      result.p95Nanoseconds >= result.medianNanoseconds
else {
    fail("benchmark timing statistics gate failed")
}

guard result.publicationsPerGesture == Array(repeating: 2, count: 30),
      !result.modelChecksum.isEmpty,
      result.modelChecksum == "882b4fb5d86096de",
      result.checksumIsStable,
      result.finalStateValid
else {
    fail("publication/checksum/final-state gate failed")
}

guard !result.rendererTimed,
      !result.compositorTimed,
      dictionary["reportKind"] == nil,
      dictionary["schemaVersion"] == nil,
      dictionary["fullSchemaVersion"] == nil
else {
    fail("model-only scope gate failed")
}
SWIFT
then
    fail "benchmark JSON validation failed"
fi

printf '%s\n' "$report"
