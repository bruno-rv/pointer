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
        XCTAssertTrue(isPositiveFinite(result.madNanoseconds))
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

    private struct MADFixture: Decodable {
        let madNanoseconds: Double
    }

    private func isValidMAD(json: String) throws -> Bool {
        let fixture = try JSONDecoder().decode(MADFixture.self, from: Data(json.utf8))
        return fixture.madNanoseconds.isFinite && fixture.madNanoseconds >= 0
    }

    private func isPositiveFinite(_ value: Double) -> Bool {
        value.isFinite && value > 0
    }
}
