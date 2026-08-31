import Foundation
import XCTest
@testable import PointerAppKit

final class GestureBenchmarkTests: XCTestCase {
    func testDefaultGestureBenchmarkPublishesStableModelOnlyEvidence() throws {
        let result = GestureBenchmark.run()

        XCTAssertEqual(result.fixtureMarkCount, 12)
        XCTAssertEqual(result.samplesPerGesture, 240)
        XCTAssertEqual(result.warmupCount, 5)
        XCTAssertEqual(result.trialCount, 30)

        XCTAssertEqual(result.trialNanoseconds.count, 30)
        XCTAssertTrue(result.trialNanoseconds.allSatisfy(isPositiveFinite))
        XCTAssertTrue(isPositiveFinite(result.medianNanoseconds))
        XCTAssertTrue(isPositiveFinite(result.p95Nanoseconds))
        XCTAssertTrue(isNonNegativeFinite(result.madNanoseconds))
        XCTAssertEqual(result.medianNanoseconds, median(result.trialNanoseconds))
        XCTAssertEqual(result.p95Nanoseconds, nearestRankP95(result.trialNanoseconds))
        XCTAssertEqual(result.madNanoseconds, mad(result.trialNanoseconds))
        XCTAssertGreaterThanOrEqual(result.p95Nanoseconds, result.medianNanoseconds)

        XCTAssertEqual(result.publicationsPerGesture.count, 30)
        XCTAssertTrue(result.publicationsPerGesture.allSatisfy { $0 == 2 })
        XCTAssertFalse(result.modelChecksum.isEmpty)
        XCTAssertEqual(result.modelChecksum, "882b4fb5d86096de")
        XCTAssertTrue(result.checksumIsStable)
        XCTAssertTrue(result.finalStateValid)

        XCTAssertFalse(result.rendererTimed)
        XCTAssertFalse(result.compositorTimed)

        let encoded = try JSONEncoder().encode(result)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
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
        XCTAssertEqual(Set(object.keys), expectedKeys)
        XCTAssertNil(object["reportKind"])
        XCTAssertNil(object["fullSchemaVersion"])
        XCTAssertNil(object["schemaVersion"])
    }

    func testMADValidationAcceptsZeroAndRejectsNegativeOrNonFiniteValues() throws {
        XCTAssertTrue(try isValidMAD(json: #"{"madNanoseconds":0}"#))
        XCTAssertFalse(try isValidMAD(json: #"{"madNanoseconds":-0.001}"#))
        XCTAssertThrowsError(try isValidMAD(json: #"{"madNanoseconds":NaN}"#))
        XCTAssertThrowsError(try isValidMAD(json: #"{"madNanoseconds":Infinity}"#))
    }

    func testAggregateValidationRejectsTamperedMedianP95OrMAD() throws {
        let valid = #"{"trialNanoseconds":[1,2,3,4,5],"medianNanoseconds":3,"p95Nanoseconds":5,"madNanoseconds":1}"#
        let tamperedMedian = #"{"trialNanoseconds":[1,2,3,4,5],"medianNanoseconds":3.5,"p95Nanoseconds":5,"madNanoseconds":1}"#
        let tamperedP95 = #"{"trialNanoseconds":[1,2,3,4,5],"medianNanoseconds":3,"p95Nanoseconds":4,"madNanoseconds":1}"#
        let tamperedMAD = #"{"trialNanoseconds":[1,2,3,4,5],"medianNanoseconds":3,"p95Nanoseconds":5,"madNanoseconds":2}"#

        XCTAssertTrue(try isValidAggregates(json: valid))
        XCTAssertFalse(try isValidAggregates(json: tamperedMedian))
        XCTAssertFalse(try isValidAggregates(json: tamperedP95))
        XCTAssertFalse(try isValidAggregates(json: tamperedMAD))
    }

    private struct MADFixture: Decodable {
        let madNanoseconds: Double
    }

    private struct AggregateFixture: Decodable {
        let trialNanoseconds: [Double]
        let medianNanoseconds: Double
        let p95Nanoseconds: Double
        let madNanoseconds: Double
    }

    private func isValidMAD(json: String) throws -> Bool {
        let fixture = try JSONDecoder().decode(MADFixture.self, from: Data(json.utf8))
        return isNonNegativeFinite(fixture.madNanoseconds)
    }

    private func isValidAggregates(json: String) throws -> Bool {
        let fixture = try JSONDecoder().decode(
            AggregateFixture.self,
            from: Data(json.utf8)
        )
        guard !fixture.trialNanoseconds.isEmpty,
              fixture.trialNanoseconds.allSatisfy(isPositiveFinite),
              isPositiveFinite(fixture.medianNanoseconds),
              isPositiveFinite(fixture.p95Nanoseconds),
              isNonNegativeFinite(fixture.madNanoseconds),
              fixture.p95Nanoseconds >= fixture.medianNanoseconds
        else {
            return false
        }
        return fixture.medianNanoseconds == median(fixture.trialNanoseconds)
            && fixture.p95Nanoseconds == nearestRankP95(fixture.trialNanoseconds)
            && fixture.madNanoseconds == mad(fixture.trialNanoseconds)
    }

    private func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private func nearestRankP95(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let rank = max(1, Int(ceil(0.95 * Double(sorted.count))))
        return sorted[rank - 1]
    }

    private func mad(_ values: [Double]) -> Double {
        let center = median(values)
        return median(values.map { abs($0 - center) })
    }

    private func isNonNegativeFinite(_ value: Double) -> Bool {
        value.isFinite && value >= 0
    }

    private func isPositiveFinite(_ value: Double) -> Bool {
        value.isFinite && value > 0
    }
}
