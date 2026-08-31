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

enum JSONScanError: Error {
    case invalid
}

struct JSONTopLevelObjectScanner {
    private var bytes: [UInt8]
    private var index = 0

    init(data: Data) {
        bytes = Array(data) + [0]
    }

    mutating func topLevelMemberNames() throws -> [String] {
        try expect(0x7b)
        skipWhitespace()
        if consume(0x7d) {
            skipWhitespace()
            try ensureEnd()
            return []
        }

        var names: [String] = []
        var seen = Set<String>()
        while true {
            guard bytes[index] == 0x22 else { throw JSONScanError.invalid }
            let name = try parseString()
            guard seen.insert(name).inserted else { throw JSONScanError.invalid }
            names.append(name)

            skipWhitespace()
            try expect(0x3a)
            try skipValue()
            skipWhitespace()
            if consume(0x2c) {
                skipWhitespace()
                continue
            }
            try expect(0x7d)
            skipWhitespace()
            try ensureEnd()
            return names
        }
    }

    private mutating func skipValue() throws {
        skipWhitespace()
        switch bytes[index] {
        case 0x22:
            _ = try parseString()
        case 0x7b:
            try skipObject()
        case 0x5b:
            try skipArray()
        case 0x74:
            try expectLiteral("true")
        case 0x66:
            try expectLiteral("false")
        case 0x6e:
            try expectLiteral("null")
        case 0x2d, 0x30...0x39:
            try skipNumber()
        default:
            throw JSONScanError.invalid
        }
    }

    private mutating func skipObject() throws {
        try expect(0x7b)
        skipWhitespace()
        if consume(0x7d) { return }
        while true {
            guard bytes[index] == 0x22 else { throw JSONScanError.invalid }
            _ = try parseString()
            skipWhitespace()
            try expect(0x3a)
            try skipValue()
            skipWhitespace()
            if consume(0x2c) {
                skipWhitespace()
                continue
            }
            try expect(0x7d)
            return
        }
    }

    private mutating func skipArray() throws {
        try expect(0x5b)
        skipWhitespace()
        if consume(0x5d) { return }
        while true {
            try skipValue()
            skipWhitespace()
            if consume(0x2c) {
                skipWhitespace()
                continue
            }
            try expect(0x5d)
            return
        }
    }

    private mutating func skipNumber() throws {
        if consume(0x2d) {}
        if consume(0x30) {
            if bytes[index] >= 0x30 && bytes[index] <= 0x39 {
                throw JSONScanError.invalid
            }
        } else {
            guard bytes[index] >= 0x31 && bytes[index] <= 0x39 else {
                throw JSONScanError.invalid
            }
            while bytes[index] >= 0x30 && bytes[index] <= 0x39 { index += 1 }
        }

        if consume(0x2e) {
            guard bytes[index] >= 0x30 && bytes[index] <= 0x39 else {
                throw JSONScanError.invalid
            }
            while bytes[index] >= 0x30 && bytes[index] <= 0x39 { index += 1 }
        }

        if bytes[index] == 0x65 || bytes[index] == 0x45 {
            index += 1
            if bytes[index] == 0x2b || bytes[index] == 0x2d { index += 1 }
            guard bytes[index] >= 0x30 && bytes[index] <= 0x39 else {
                throw JSONScanError.invalid
            }
            while bytes[index] >= 0x30 && bytes[index] <= 0x39 { index += 1 }
        }
    }

    private mutating func parseString() throws -> String {
        try expect(0x22)
        var value = ""
        while true {
            let byte = bytes[index]
            index += 1
            switch byte {
            case 0x22:
                return value
            case 0x5c:
                let escaped = bytes[index]
                index += 1
                switch escaped {
                case 0x22: value.append("\"")
                case 0x5c: value.append("\\")
                case 0x2f: value.append("/")
                case 0x62: value.append("\u{8}")
                case 0x66: value.append("\u{c}")
                case 0x6e: value.append("\n")
                case 0x72: value.append("\r")
                case 0x74: value.append("\t")
                case 0x75:
                    let high = try parseHexQuad()
                    var codePoint = high
                    if high >= 0xd800 && high <= 0xdbff {
                        guard index + 5 < bytes.count,
                              bytes[index] == 0x5c,
                              bytes[index + 1] == 0x75
                        else { throw JSONScanError.invalid }
                        index += 2
                        let low = try parseHexQuad()
                        guard low >= 0xdc00 && low <= 0xdfff else {
                            throw JSONScanError.invalid
                        }
                        codePoint = 0x10000 + ((high - 0xd800) << 10) + (low - 0xdc00)
                    } else if high >= 0xdc00 && high <= 0xdfff {
                        throw JSONScanError.invalid
                    }
                    guard let scalar = UnicodeScalar(codePoint) else {
                        throw JSONScanError.invalid
                    }
                    value.unicodeScalars.append(scalar)
                default:
                    throw JSONScanError.invalid
                }
            default:
                guard byte >= 0x20 else { throw JSONScanError.invalid }
                let start = index - 1
                while bytes[index] != 0x22 && bytes[index] != 0x5c {
                    guard bytes[index] >= 0x20 else { throw JSONScanError.invalid }
                    index += 1
                }
                guard let text = String(
                    data: Data(bytes[start..<index]),
                    encoding: .utf8
                ) else {
                    throw JSONScanError.invalid
                }
                value.append(text)
            }
        }
    }

    private mutating func parseHexQuad() throws -> UInt32 {
        guard index + 4 <= bytes.count else { throw JSONScanError.invalid }
        var value: UInt32 = 0
        for _ in 0..<4 {
            let byte = bytes[index]
            index += 1
            let digit: UInt32
            switch byte {
            case 0x30...0x39: digit = UInt32(byte - 0x30)
            case 0x41...0x46: digit = UInt32(byte - 0x41 + 10)
            case 0x61...0x66: digit = UInt32(byte - 0x61 + 10)
            default: throw JSONScanError.invalid
            }
            value = (value << 4) | digit
        }
        return value
    }

    private mutating func expectLiteral(_ literal: String) throws {
        for byte in literal.utf8 {
            guard bytes[index] == byte else { throw JSONScanError.invalid }
            index += 1
        }
    }

    private mutating func skipWhitespace() {
        while bytes[index] == 0x20 || bytes[index] == 0x09
            || bytes[index] == 0x0a || bytes[index] == 0x0d {
            index += 1
        }
    }

    private mutating func consume(_ byte: UInt8) -> Bool {
        guard bytes[index] == byte else { return false }
        index += 1
        return true
    }

    private mutating func expect(_ byte: UInt8) throws {
        guard consume(byte) else { throw JSONScanError.invalid }
    }

    private mutating func ensureEnd() throws {
        guard index == bytes.count - 1 else { throw JSONScanError.invalid }
    }
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

do {
    var duplicateScanner = JSONTopLevelObjectScanner(
        data: Data(#"{"warmupCount":5,"warm\u0075pCount":5}"#.utf8)
    )
    _ = try duplicateScanner.topLevelMemberNames()
    fail("strict JSON scanner accepted duplicate warmupCount")
} catch {
    // Expected: the escaped spelling resolves to the existing top-level name.
}

do {
    var validScanner = JSONTopLevelObjectScanner(
        data: Data(#"{"escaped\u004bey":"quote: \" and slash \\","nested":[{"value":true},null,["line\n"]]}"#.utf8)
    )
    guard (try validScanner.topLevelMemberNames()) == ["escapedKey", "nested"] else {
        fail("strict JSON scanner rejected valid escaped/nested JSON")
    }
} catch {
    fail("strict JSON scanner rejected valid escaped/nested JSON: \(error)")
}

let scannedKeys: [String]
do {
    var scanner = JSONTopLevelObjectScanner(data: data)
    scannedKeys = try scanner.topLevelMemberNames()
} catch {
    fail("benchmark JSON failed strict object scanning: \(error)")
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
guard scannedKeys.count == expectedKeys.count,
      Set(scannedKeys) == expectedKeys
else {
    fail("benchmark JSON fields failed strict duplicate/unknown-key validation")
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
func median(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    let middle = sorted.count / 2
    if sorted.count.isMultiple(of: 2) {
        return (sorted[middle - 1] + sorted[middle]) / 2
    }
    return sorted[middle]
}
func nearestRankP95(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    let rank = max(1, Int(ceil(0.95 * Double(sorted.count))))
    return sorted[rank - 1]
}
func mad(_ values: [Double]) -> Double {
    let center = median(values)
    return median(values.map { abs($0 - center) })
}
guard result.trialNanoseconds.count == 30,
      result.trialNanoseconds.allSatisfy(isPositiveFinite),
      isPositiveFinite(result.medianNanoseconds),
      isPositiveFinite(result.p95Nanoseconds),
      isNonNegativeFinite(result.madNanoseconds),
      result.p95Nanoseconds >= result.medianNanoseconds,
      result.medianNanoseconds == median(result.trialNanoseconds),
      result.p95Nanoseconds == nearestRankP95(result.trialNanoseconds),
      result.madNanoseconds == mad(result.trialNanoseconds)
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
