import Foundation
import AppKit
import CoreGraphics
import XCTest
import PointerCore
@testable import PointerAppKit

final class PerformanceHarnessTests: XCTestCase {
    private static let canonicalRenderPlanIdentity = [
        "state=display=performance-render-display|mode=standby|canvasTool=select|sessionTool=arrow|toolStyle=rgba=1000000,0,0,1000000;stroke=4000000;opacity=1000000|emoji=👉|spotlight=150000,500000|selection=none|selectedDisplay=none|activeGesture=0|cursor=clickThrough",
        "committed=id=00000000-0000-0000-0000-000000000001,geometry=arrow:50000,80000:150000,170000,style=rgba=1000000,0,0,1000000;stroke=4000000;opacity=1000000;id=00000000-0000-0000-0000-000000000002,geometry=rectangle:270000,80000,120000,100000,style=rgba=1000000,0,0,1000000;stroke=4000000;opacity=1000000;id=00000000-0000-0000-0000-000000000003,geometry=ellipse:490000,80000,120000,100000,style=rgba=1000000,0,0,1000000;stroke=4000000;opacity=1000000;id=00000000-0000-0000-0000-000000000004,geometry=arrow:710000,80000:810000,170000,style=rgba=1000000,0,0,1000000;stroke=4000000;opacity=1000000;id=00000000-0000-0000-0000-000000000005,geometry=rectangle:50000,320000,120000,100000,style=rgba=1000000,0,0,1000000;stroke=4000000;opacity=1000000;id=00000000-0000-0000-0000-000000000006,geometry=ellipse:270000,320000,120000,100000,style=rgba=1000000,0,0,1000000;stroke=4000000;opacity=1000000;id=00000000-0000-0000-0000-000000000007,geometry=arrow:490000,320000:590000,410000,style=rgba=1000000,0,0,1000000;stroke=4000000;opacity=1000000;id=00000000-0000-0000-0000-000000000008,geometry=rectangle:710000,320000,120000,100000,style=rgba=1000000,0,0,1000000;stroke=4000000;opacity=1000000;id=00000000-0000-0000-0000-000000000009,geometry=ellipse:50000,560000,120000,100000,style=rgba=1000000,0,0,1000000;stroke=4000000;opacity=1000000;id=00000000-0000-0000-0000-000000000010,geometry=arrow:270000,560000:370000,650000,style=rgba=1000000,0,0,1000000;stroke=4000000;opacity=1000000;id=00000000-0000-0000-0000-000000000011,geometry=rectangle:490000,560000,120000,100000,style=rgba=1000000,0,0,1000000;stroke=4000000;opacity=1000000;id=00000000-0000-0000-0000-000000000012,geometry=ellipse:710000,560000,120000,100000,style=rgba=1000000,0,0,1000000;stroke=4000000;opacity=1000000",
        "draft=none",
        "handles=selection=none,0|hover=none,0|resize=0,|delete=0",
    ].joined(separator: "|")
    private static let canonicalMinimumPositiveHits = [2, 4, 4, 2, 4, 4, 2, 4, 4, 2, 4, 4]
    private static let canonicalNegativeRegionCount = 27
    private static let denseMinimumPositiveHits = Array(repeating: 1, count: 1_000)
    private static let denseNegativeRegionCount = 9
    private static let denseStratumCount = 16

    func testPerformanceMeasurementReportRoundTripsEveryRequiredMeasurementObject() throws {
        let report = PerformanceFixtures.report()
        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(PerformanceMeasurementReport.self, from: data)

        XCTAssertEqual(decoded, report)
        XCTAssertEqual(decoded.reportKind, .measurement)
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.identity.sourceCommitSHA, PerformanceFixtures.commit)
        XCTAssertNil(decoded.identity.contentManifestSHA256)
        XCTAssertEqual(decoded.host, PerformanceFixtures.host)
        XCTAssertEqual(decoded.fixture, PerformanceFixtures.fixture)
        XCTAssertEqual(decoded.model.status, .measured)
        XCTAssertEqual(decoded.renderer.status, .measured)
        XCTAssertEqual(decoded.renderer.frameMilliseconds.count, PerformanceFixtures.configuration.trialCount)
        XCTAssertEqual(decoded.compositor.status, .measured)
        XCTAssertEqual(decoded.combinedFrame.status, .measured)
        XCTAssertEqual(decoded.launch.coldMilliseconds.count, PerformanceFixtures.configuration.trialCount)
        XCTAssertEqual(decoded.allocations.bytesPerGesture.count, PerformanceFixtures.configuration.trialCount)
        XCTAssertEqual(decoded.redrawLayout.layoutPasses.count, PerformanceFixtures.configuration.trialCount)
        XCTAssertEqual(decoded.redrawLayout.sampleMilliseconds.count, PerformanceFixtures.configuration.trialCount)
        XCTAssertEqual(decoded.responsiveness.stallCount, 0)
        XCTAssertEqual(decoded.responsiveness.responseMilliseconds.count, PerformanceFixtures.configuration.trialCount)
        XCTAssertEqual(decoded.inputToVisible.missedSampleCount, 0)
        XCTAssertEqual(decoded.inputToVisible.sampleMilliseconds.count, PerformanceFixtures.configuration.trialCount)
        XCTAssertEqual(decoded.memory.samples.count, 124)
        XCTAssertEqual(decoded.memory.samples.prefix(121).allSatisfy { $0.phase == .running }, true)
        XCTAssertEqual(decoded.memory.samples.suffix(3).map(\.phase), [.stopping, .stopped, .restarted])
        XCTAssertEqual(decoded.memory.aggregates.count, 11)
        XCTAssertEqual(decoded.resilience.cases.count, 1)
        XCTAssertEqual(decoded.disposition, .acceptedNoRegression)
        try decoded.validateStructure()
    }

    func testPerformanceReportKindIsTypedAndWrongOrMissingKindsAreRejected() throws {
        let report = PerformanceFixtures.report()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(report)) as? [String: Any])
        object.removeValue(forKey: "reportKind")
        let missingData = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try JSONDecoder().decode(PerformanceMeasurementReport.self, from: missingData))

        let wrong = PerformanceFixtures.report(reportKind: .comparison)
        XCTAssertThrowsError(try wrong.validateStructure())

        object["reportKind"] = "not-a-report"
        let unknownData = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try JSONDecoder().decode(PerformanceMeasurementReport.self, from: unknownData))
    }

    func testBuildAndRunProvenanceAreDistinctAndPortable() throws {
        let report = PerformanceFixtures.report()
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(report)) as? [String: Any]
        let build = try XCTUnwrap(encoded?["buildProvenance"] as? [String: Any])
        let run = try XCTUnwrap(encoded?["runProvenance"] as? [String: Any])
        XCTAssertNil(build["path"])
        XCTAssertNil(build["outputRoot"])
        XCTAssertNil(build["baselineRoot"])
        XCTAssertEqual(run["outputRoot"] as? String, "build/candidate")
        XCTAssertEqual(run["foundationProvenancePath"] as? String, PerformanceFixtures.run.foundationProvenancePath)
        XCTAssertEqual(report.buildProvenance, PerformanceFixtures.build)
        XCTAssertEqual(report.runProvenance.build, report.buildProvenance)
        try report.validateStructure()
    }

    func testPerformanceReportRoundTripsTypedProvenanceAndFoundationVersions() throws {
        let report = PerformanceFixtures.report()
        let decoded = try JSONDecoder().decode(
            PerformanceMeasurementReport.self,
            from: JSONEncoder().encode(report)
        )
        XCTAssertEqual(decoded.harnessVersion, PerformanceFixtures.configuration.harnessVersion)
        XCTAssertEqual(decoded.foundationIdentity, PerformanceFixtures.foundation)
        XCTAssertEqual(decoded.buildContractVersion, PerformanceFixtures.configuration.buildContractVersion)
        XCTAssertEqual(decoded.buildProvenance.foundation, PerformanceFixtures.foundation)
        XCTAssertEqual(decoded.runProvenance.configuration.pairsPerOrder, 15)
        XCTAssertEqual(decoded.runProvenance.configuration.totalPairs, 30)
        XCTAssertEqual(decoded.runProvenance.harnessVersion, decoded.harnessVersion)
    }

    func testCanonicalFixtureProfilesExposeExactIDsVersionsAndConfigurations() throws {
        XCTAssertEqual(PerformanceFixtureProfile.standard12.markCount, 12)
        XCTAssertEqual(PerformanceFixtureProfile.dense1000.markCount, 1_000)
        XCTAssertEqual(PerformanceFixtureProfile.standard12.identifier, "pointer-standard-12-marks")
        XCTAssertEqual(PerformanceFixtureProfile.dense1000.identifier, "pointer-dense-1000-marks")
        XCTAssertEqual(PerformanceFixtureProfile.standard12.version, "pointer-fixture-standard12/v1")
        XCTAssertEqual(PerformanceFixtureProfile.dense1000.version, "pointer-fixture-dense1000/v1")
        XCTAssertEqual(PerformanceConfiguration.standard.fixtureProfile, .standard12)
        XCTAssertEqual(PerformanceConfiguration.standard.fixtureVersion, PerformanceFixtureProfile.standard12.version)
        XCTAssertEqual(PerformanceConfiguration.standard12, PerformanceConfiguration.standard)
        XCTAssertEqual(PerformanceConfiguration.dense1000.fixtureProfile, .dense1000)
        XCTAssertEqual(PerformanceConfiguration.dense1000.fixtureMarkCount, 1_000)
        XCTAssertEqual(PerformanceConfiguration.dense1000.fixtureVersion, PerformanceFixtureProfile.dense1000.version)
    }

    func testFixtureProfileIsBoundToItsConfigurationAndRejectsCrossProfileSpoofing() throws {
        XCTAssertNoThrow(try PerformanceFixtures.report().validateStructure())

        let spoofedFixture = FixtureIdentity(
            identifier: PerformanceFixtureProfile.dense1000.identifier,
            fixtureProfile: .dense1000,
            fixtureVersion: PerformanceFixtureProfile.dense1000.version,
            markCount: 12,
            continuationSamples: PerformanceFixtures.fixture.continuationSamples,
            warmupCount: PerformanceFixtures.fixture.warmupCount,
            trialCount: PerformanceFixtures.fixture.trialCount,
            seed: PerformanceFixtures.fixture.seed
        )
        XCTAssertThrowsError(try PerformanceFixtures.report(fixture: spoofedFixture).validateStructure())

        let legacyFixture = FixtureIdentity(
            identifier: "pointer-dense-12-marks",
            fixtureProfile: .standard12,
            fixtureVersion: PerformanceFixtureProfile.standard12.version,
            markCount: 12,
            continuationSamples: PerformanceFixtures.fixture.continuationSamples,
            warmupCount: PerformanceFixtures.fixture.warmupCount,
            trialCount: PerformanceFixtures.fixture.trialCount,
            seed: PerformanceFixtures.fixture.seed
        )
        XCTAssertThrowsError(try PerformanceFixtures.report(fixture: legacyFixture).validateStructure())

        let denseConfiguration = PerformanceConfiguration.dense1000
        let denseRun = PerformanceRunProvenance(
            variant: "candidate",
            outputRoot: "build/dense-candidate",
            sourceRef: PerformanceFixtures.commit,
            build: PerformanceFixtures.build,
            host: PerformanceFixtures.host,
            recordedAtUTC: PerformanceFixtures.recordedAtUTC,
            configuration: denseConfiguration,
            foundationProvenancePath: PerformanceFixtures.run.foundationProvenancePath,
            foundation: PerformanceFixtures.foundation,
            harnessVersion: denseConfiguration.harnessVersion,
            buildContractVersion: denseConfiguration.buildContractVersion,
            acceptedFoundationArtifactSHA256: PerformanceFixtures.foundationArtifact
        )
        XCTAssertThrowsError(try PerformanceFixtures.report(run: denseRun).validateStructure())

        let denseFixture = FixtureIdentity(
            identifier: PerformanceFixtureProfile.dense1000.identifier,
            fixtureProfile: .dense1000,
            fixtureVersion: PerformanceFixtureProfile.dense1000.version,
            markCount: 1_000,
            continuationSamples: denseConfiguration.samplesPerGesture,
            warmupCount: denseConfiguration.warmupCount,
            trialCount: denseConfiguration.trialCount,
            seed: PerformanceFixtures.fixture.seed
        )
        let validDenseReport = PerformanceFixtures.report(run: denseRun, fixture: denseFixture)
        XCTAssertNoThrow(try validDenseReport.validateStructure())
        XCTAssertNoThrow(try validDenseReport.validateCompletion())
    }

    func testOneReportCarriesExactlyOneFixtureProfileWithoutConcatenatedArrays() throws {
        let report = PerformanceFixtures.report()
        XCTAssertEqual(report.fixture.fixtureProfile, .standard12)
        XCTAssertEqual(report.fixture.markCount, 12)
        XCTAssertEqual(report.model.trialNanoseconds.count, report.fixture.trialCount)
        XCTAssertEqual(report.renderer.frameMilliseconds.count, report.fixture.trialCount)
        XCTAssertEqual(report.memory.samples.filter { $0.phase == .running }.count, 121)
        XCTAssertNoThrow(try report.validateCompletion())
    }

    func testIdentityRequiresOneLowercaseImmutableIdentityAndCompatibleTreeStatus() throws {
        let both = MeasurementIdentity(sourceCommitSHA: PerformanceFixtures.commit, contentManifestSHA256: PerformanceFixtures.sourceManifest, hostModel: "Mac", macOSVersion: "14", xcodeVersion: "16", developerDirectory: "/Applications/Xcode.app/Contents/Developer", powerState: "ac", displayState: "one", buildConfiguration: "release")
        XCTAssertThrowsError(try PerformanceFixtures.report(identity: both).validateStructure())

        let neither = MeasurementIdentity(sourceCommitSHA: nil, contentManifestSHA256: nil, hostModel: "Mac", macOSVersion: "14", xcodeVersion: "16", developerDirectory: "/Applications/Xcode.app/Contents/Developer", powerState: "ac", displayState: "one", buildConfiguration: "release")
        XCTAssertThrowsError(try PerformanceFixtures.report(identity: neither).validateStructure())

        let uppercase = MeasurementIdentity(sourceCommitSHA: String(repeating: "A", count: 40), contentManifestSHA256: nil, hostModel: "Mac", macOSVersion: "14", xcodeVersion: "16", developerDirectory: "/Applications/Xcode.app/Contents/Developer", powerState: "ac", displayState: "one", buildConfiguration: "release")
        XCTAssertThrowsError(try PerformanceFixtures.report(identity: uppercase).validateStructure())

        let dirtyIdentity = MeasurementIdentity(sourceCommitSHA: nil, contentManifestSHA256: PerformanceFixtures.sourceManifest, hostModel: "Mac", macOSVersion: "14", xcodeVersion: "16", developerDirectory: "/Applications/Xcode.app/Contents/Developer", powerState: "ac", displayState: "one", buildConfiguration: "release")
        let dirtyBuild = BuildProvenance(sourceTreeStatus: .dirty, sourceIdentity: SourceIdentity(kind: .contentManifestSHA256, value: PerformanceFixtures.sourceManifest), sourceManifestSHA256: PerformanceFixtures.sourceManifest, executableSHA256: PerformanceFixtures.executable, bundleManifestSHA256: PerformanceFixtures.bundle, buildConfiguration: "release", recordedAtUTC: PerformanceFixtures.recordedAtUTC, foundation: PerformanceFixtures.foundation, harnessVersion: PerformanceFixtures.configuration.harnessVersion, buildContractVersion: PerformanceFixtures.configuration.buildContractVersion, acceptedFoundationArtifactSHA256: nil)
        let dirtyRun = PerformanceRunProvenance(variant: "candidate", outputRoot: "build/candidate", sourceRef: PerformanceFixtures.sourceManifest, build: dirtyBuild, host: PerformanceFixtures.host, recordedAtUTC: PerformanceFixtures.recordedAtUTC, configuration: PerformanceFixtures.configuration, foundationProvenancePath: PerformanceFixtures.run.foundationProvenancePath, foundation: PerformanceFixtures.foundation, harnessVersion: PerformanceFixtures.configuration.harnessVersion, buildContractVersion: PerformanceFixtures.configuration.buildContractVersion, acceptedFoundationArtifactSHA256: nil)
        let dirtyReport = PerformanceFixtures.report(identity: dirtyIdentity, build: dirtyBuild, run: dirtyRun)
        XCTAssertNoThrow(try dirtyReport.validateStructure())

        let dirtyBuildWithMismatchedManifest = BuildProvenance(sourceTreeStatus: .dirty, sourceIdentity: SourceIdentity(kind: .contentManifestSHA256, value: PerformanceFixtures.sourceManifest), sourceManifestSHA256: PerformanceFixtures.bundle, executableSHA256: PerformanceFixtures.executable, bundleManifestSHA256: PerformanceFixtures.bundle, buildConfiguration: "release", recordedAtUTC: PerformanceFixtures.recordedAtUTC, foundation: PerformanceFixtures.foundation, harnessVersion: PerformanceFixtures.configuration.harnessVersion, buildContractVersion: PerformanceFixtures.configuration.buildContractVersion, acceptedFoundationArtifactSHA256: nil)
        let dirtyRunWithMismatchedManifest = PerformanceRunProvenance(variant: "candidate", outputRoot: "build/candidate", sourceRef: PerformanceFixtures.sourceManifest, build: dirtyBuildWithMismatchedManifest, host: PerformanceFixtures.host, recordedAtUTC: PerformanceFixtures.recordedAtUTC, configuration: PerformanceFixtures.configuration, foundationProvenancePath: PerformanceFixtures.run.foundationProvenancePath, foundation: PerformanceFixtures.foundation, harnessVersion: PerformanceFixtures.configuration.harnessVersion, buildContractVersion: PerformanceFixtures.configuration.buildContractVersion, acceptedFoundationArtifactSHA256: nil)
        XCTAssertThrowsError(try PerformanceFixtures.report(identity: dirtyIdentity, build: dirtyBuildWithMismatchedManifest, run: dirtyRunWithMismatchedManifest).validateStructure())

        let dirtyWithCommit = PerformanceFixtures.report(build: dirtyBuild, run: dirtyRun)
        XCTAssertThrowsError(try dirtyWithCommit.validateStructure())
    }

    func testProvenanceIdentityAndVersionMismatchesAreRejected() throws {
        var mismatchedBuild = PerformanceFixtures.build
        mismatchedBuild = BuildProvenance(sourceTreeStatus: .clean, sourceIdentity: SourceIdentity(kind: .sourceCommitSHA, value: String(repeating: "e", count: 40)), sourceManifestSHA256: mismatchedBuild.sourceManifestSHA256, executableSHA256: mismatchedBuild.executableSHA256, bundleManifestSHA256: mismatchedBuild.bundleManifestSHA256, buildConfiguration: mismatchedBuild.buildConfiguration, recordedAtUTC: mismatchedBuild.recordedAtUTC, foundation: mismatchedBuild.foundation, harnessVersion: mismatchedBuild.harnessVersion, buildContractVersion: mismatchedBuild.buildContractVersion, acceptedFoundationArtifactSHA256: mismatchedBuild.acceptedFoundationArtifactSHA256)
        XCTAssertThrowsError(try PerformanceFixtures.report(build: mismatchedBuild).validateStructure())

        let mismatchedRun = PerformanceRunProvenance(variant: PerformanceFixtures.run.variant, outputRoot: PerformanceFixtures.run.outputRoot, sourceRef: PerformanceFixtures.run.sourceRef, build: PerformanceFixtures.run.build, host: PerformanceFixtures.run.host, recordedAtUTC: PerformanceFixtures.run.recordedAtUTC, configuration: PerformanceFixtures.run.configuration, foundationProvenancePath: PerformanceFixtures.run.foundationProvenancePath, foundation: FoundationIdentity(identity: "other", version: "v1"), harnessVersion: PerformanceFixtures.run.harnessVersion, buildContractVersion: PerformanceFixtures.run.buildContractVersion, acceptedFoundationArtifactSHA256: PerformanceFixtures.run.acceptedFoundationArtifactSHA256)
        XCTAssertThrowsError(try PerformanceFixtures.report(run: mismatchedRun).validateStructure())

        let mismatchedConfiguration = PerformanceConfiguration(fixtureMarkCount: 12, samplesPerGesture: 240, warmupCount: 5, trialCount: 30, pairsPerOrder: 14, bootstrapSeed: 48271, bootstrapResamples: 10_000, memoryWindowSeconds: 600, memorySampleIntervalSeconds: 5, harnessVersion: "other-harness", foundationIdentity: PerformanceFixtures.foundation, buildContractVersion: PerformanceFixtures.configuration.buildContractVersion)
        let run = PerformanceRunProvenance(variant: "candidate", outputRoot: "build/candidate", sourceRef: PerformanceFixtures.commit, build: PerformanceFixtures.build, host: PerformanceFixtures.host, recordedAtUTC: PerformanceFixtures.recordedAtUTC, configuration: mismatchedConfiguration, foundationProvenancePath: PerformanceFixtures.run.foundationProvenancePath, foundation: PerformanceFixtures.foundation, harnessVersion: mismatchedConfiguration.harnessVersion, buildContractVersion: mismatchedConfiguration.buildContractVersion, acceptedFoundationArtifactSHA256: PerformanceFixtures.run.acceptedFoundationArtifactSHA256)
        XCTAssertThrowsError(try PerformanceFixtures.report(run: run).validateStructure())
    }

    func testNonFiniteAndNegativeNumericValuesAreRejected() throws {
        let nanModel = ModelMeasurement(status: .measured, trialNanoseconds: [Double.nan], medianNanoseconds: 1, p95Nanoseconds: 1, madNanoseconds: 0, publicationCount: 2, modelChecksum: "checksum", finalStateValid: true)
        XCTAssertThrowsError(try PerformanceFixtures.report(model: nanModel).validateStructure())

        let infiniteInput = InputToVisibleMeasurement(status: .measured, sampleCount: 1, p95Milliseconds: .infinity, missedSampleCount: 0)
        XCTAssertThrowsError(try PerformanceFixtures.report(inputToVisible: infiniteInput).validateStructure())

        let negativeResources = ResourceCounts(overlays: -1, timers: 0, handlers: 0, windows: 0, observers: 0)
        let badSample = MemorySample(elapsedSeconds: 0, rssBytes: 100, phase: .running, resources: negativeResources)
        var samples = PerformanceFixtures.memory.samples
        samples[0] = badSample
        let memory = MemoryMeasurement(status: .measured, windowSeconds: 600, sampleIntervalSeconds: 5, samples: samples, aggregates: PerformanceFixtures.memory.aggregates, peakRSSBytes: PerformanceFixtures.memory.peakRSSBytes, finalWindowDeltaBytes: 0, finalWindowDeltaPercent: 0, matchedBaselineSeries: PerformanceFixtures.memory.matchedBaselineSeries, matchedBaselineValues: PerformanceFixtures.memory.matchedBaselineValues, peakLiveResourceCounts: PerformanceFixtures.resources, endLiveResourceCounts: PerformanceFixtures.resources)
        XCTAssertThrowsError(try PerformanceFixtures.report(memory: memory).validateStructure())
    }

    func testMemoryRequiresContractPhasesCheckpointsAndCoherentAggregates() throws {
        var missingPhaseSamples = PerformanceFixtures.memory.samples
        missingPhaseSamples.removeLast()
        let missingPhase = PerformanceMeasurementReport(
            reportKind: .measurement, schemaVersion: 1, harnessVersion: PerformanceFixtures.configuration.harnessVersion, foundationIdentity: PerformanceFixtures.foundation, buildContractVersion: PerformanceFixtures.configuration.buildContractVersion, buildProvenance: PerformanceFixtures.build, runProvenance: PerformanceFixtures.run, identity: PerformanceFixtures.identity, host: PerformanceFixtures.host, fixture: PerformanceFixtures.fixture, model: PerformanceFixtures.model, renderer: PerformanceFixtures.renderer, compositor: PerformanceFixtures.compositor, combinedFrame: PerformanceFixtures.combinedFrame, launch: PerformanceFixtures.launch, allocations: PerformanceFixtures.allocations, redrawLayout: PerformanceFixtures.redrawLayout, responsiveness: PerformanceFixtures.responsiveness, inputToVisible: PerformanceFixtures.inputToVisible, memory: MemoryMeasurement(status: .measured, windowSeconds: 600, sampleIntervalSeconds: 5, samples: missingPhaseSamples, aggregates: PerformanceFixtures.memory.aggregates, peakRSSBytes: PerformanceFixtures.memory.peakRSSBytes, finalWindowDeltaBytes: PerformanceFixtures.memory.finalWindowDeltaBytes, finalWindowDeltaPercent: PerformanceFixtures.memory.finalWindowDeltaPercent, matchedBaselineSeries: PerformanceFixtures.memory.matchedBaselineSeries, matchedBaselineValues: PerformanceFixtures.memory.matchedBaselineValues, peakLiveResourceCounts: PerformanceFixtures.resources, endLiveResourceCounts: PerformanceFixtures.resources), resilience: PerformanceFixtures.resilience, disposition: .acceptedNoRegression)
        XCTAssertThrowsError(try missingPhase.validateStructure())

        var badAggregates = PerformanceFixtures.memory.aggregates
        badAggregates[0] = MemoryAggregate(intervalIndex: 0, sampleCount: 1, meanRSSBytes: 100_000_500, peakRSSBytes: 100_001_000)
        let aggregateReport = PerformanceFixtures.report(memory: MemoryMeasurement(status: .measured, windowSeconds: 600, sampleIntervalSeconds: 5, samples: PerformanceFixtures.memory.samples, aggregates: badAggregates, peakRSSBytes: PerformanceFixtures.memory.peakRSSBytes, finalWindowDeltaBytes: PerformanceFixtures.memory.finalWindowDeltaBytes, finalWindowDeltaPercent: PerformanceFixtures.memory.finalWindowDeltaPercent, matchedBaselineSeries: PerformanceFixtures.memory.matchedBaselineSeries, matchedBaselineValues: PerformanceFixtures.memory.matchedBaselineValues, peakLiveResourceCounts: PerformanceFixtures.resources, endLiveResourceCounts: PerformanceFixtures.resources))
        XCTAssertThrowsError(try aggregateReport.validateStructure())

        let wrongDuration = PerformanceFixtures.report(memory: MemoryMeasurement(status: .measured, windowSeconds: 120, sampleIntervalSeconds: 5, samples: PerformanceFixtures.memory.samples, aggregates: PerformanceFixtures.memory.aggregates, peakRSSBytes: PerformanceFixtures.memory.peakRSSBytes, finalWindowDeltaBytes: PerformanceFixtures.memory.finalWindowDeltaBytes, finalWindowDeltaPercent: PerformanceFixtures.memory.finalWindowDeltaPercent, matchedBaselineSeries: PerformanceFixtures.memory.matchedBaselineSeries, matchedBaselineValues: PerformanceFixtures.memory.matchedBaselineValues, peakLiveResourceCounts: PerformanceFixtures.resources, endLiveResourceCounts: PerformanceFixtures.resources))
        XCTAssertThrowsError(try wrongDuration.validateStructure())

        let wrongInterval = PerformanceFixtures.report(memory: MemoryMeasurement(status: .measured, windowSeconds: 600, sampleIntervalSeconds: 10, samples: PerformanceFixtures.memory.samples, aggregates: PerformanceFixtures.memory.aggregates, peakRSSBytes: PerformanceFixtures.memory.peakRSSBytes, finalWindowDeltaBytes: PerformanceFixtures.memory.finalWindowDeltaBytes, finalWindowDeltaPercent: PerformanceFixtures.memory.finalWindowDeltaPercent, matchedBaselineSeries: PerformanceFixtures.memory.matchedBaselineSeries, matchedBaselineValues: PerformanceFixtures.memory.matchedBaselineValues, peakLiveResourceCounts: PerformanceFixtures.resources, endLiveResourceCounts: PerformanceFixtures.resources))
        XCTAssertThrowsError(try wrongInterval.validateStructure())
    }

    func testMemoryResourceCheckpointsMatchSampledMaximumAndFinalSample() throws {
        let highResources = ResourceCounts(overlays: 2, timers: 3, handlers: 4, windows: 5, observers: 6)
        var samples = PerformanceFixtures.memory.samples
        samples[1] = MemorySample(elapsedSeconds: 5, rssBytes: 100_001_000, phase: .running, resources: highResources)

        let underreportedPeak = MemoryMeasurement(status: .measured, windowSeconds: 600, sampleIntervalSeconds: 5, samples: samples, aggregates: PerformanceFixtures.memory.aggregates, peakRSSBytes: PerformanceFixtures.memory.peakRSSBytes, finalWindowDeltaBytes: PerformanceFixtures.memory.finalWindowDeltaBytes, finalWindowDeltaPercent: PerformanceFixtures.memory.finalWindowDeltaPercent, matchedBaselineSeries: PerformanceFixtures.memory.matchedBaselineSeries, matchedBaselineValues: PerformanceFixtures.memory.matchedBaselineValues, peakLiveResourceCounts: PerformanceFixtures.resources, endLiveResourceCounts: PerformanceFixtures.resources)
        XCTAssertThrowsError(try PerformanceFixtures.report(memory: underreportedPeak).validateStructure())

        let fabricatedEnd = MemoryMeasurement(status: .measured, windowSeconds: 600, sampleIntervalSeconds: 5, samples: samples, aggregates: PerformanceFixtures.memory.aggregates, peakRSSBytes: PerformanceFixtures.memory.peakRSSBytes, finalWindowDeltaBytes: PerformanceFixtures.memory.finalWindowDeltaBytes, finalWindowDeltaPercent: PerformanceFixtures.memory.finalWindowDeltaPercent, matchedBaselineSeries: PerformanceFixtures.memory.matchedBaselineSeries, matchedBaselineValues: PerformanceFixtures.memory.matchedBaselineValues, peakLiveResourceCounts: highResources, endLiveResourceCounts: PerformanceFixtures.zeroResources)
        XCTAssertThrowsError(try PerformanceFixtures.report(memory: fabricatedEnd).validateStructure())

        var coherentAggregates = PerformanceFixtures.memory.aggregates
        coherentAggregates[0] = MemoryAggregate(intervalIndex: 0, sampleCount: 11, meanRSSBytes: 100_000_091, peakRSSBytes: 100_001_000)
        let coherent = MemoryMeasurement(status: .measured, windowSeconds: 600, sampleIntervalSeconds: 5, samples: samples, aggregates: coherentAggregates, peakRSSBytes: 100_001_000, finalWindowDeltaBytes: PerformanceFixtures.memory.finalWindowDeltaBytes, finalWindowDeltaPercent: PerformanceFixtures.memory.finalWindowDeltaPercent, matchedBaselineSeries: PerformanceFixtures.memory.matchedBaselineSeries, matchedBaselineValues: PerformanceFixtures.memory.matchedBaselineValues, peakLiveResourceCounts: highResources, endLiveResourceCounts: PerformanceFixtures.resources)
        XCTAssertNoThrow(try PerformanceFixtures.report(memory: coherent).validateStructure())
    }

    func testMemoryDerivesRSSAndWindowDeltaFromCandidateAndMatchedBaseline() throws {
        var growingSamples = PerformanceFixtures.memorySamples
        growingSamples[120] = MemorySample(elapsedSeconds: 600, rssBytes: 100_001_000, phase: .running, resources: PerformanceFixtures.resources)
        var growingAggregates = PerformanceFixtures.memory.aggregates
        growingAggregates[10] = MemoryAggregate(intervalIndex: 10, sampleCount: 11, meanRSSBytes: 100_000_091, peakRSSBytes: 100_001_000)
        let growing = PerformanceFixtures.makeMemory(samples: growingSamples, aggregates: growingAggregates, peakRSSBytes: 100_001_000, finalWindowDeltaBytes: 1_000, finalWindowDeltaPercent: 0.001)
        XCTAssertNoThrow(try PerformanceFixtures.report(memory: growing).validateStructure())
        XCTAssertThrowsError(try PerformanceFixtures.report(memory: growing).validateCompletion())

        var fakeZeroBaseline = PerformanceFixtures.memory.matchedBaselineValues
        fakeZeroBaseline[120] = 0
        let zeroBaseline = PerformanceFixtures.makeMemory(matchedBaselineValues: fakeZeroBaseline)
        XCTAssertThrowsError(try PerformanceFixtures.report(memory: zeroBaseline).validateStructure())

        let fakeDelta = PerformanceFixtures.makeMemory(finalWindowDeltaBytes: 1, finalWindowDeltaPercent: 0)
        XCTAssertThrowsError(try PerformanceFixtures.report(memory: fakeDelta).validateStructure())

        var shortenedSeries = PerformanceFixtures.memory.matchedBaselineSeries
        shortenedSeries.removeLast()
        let misalignedBaseline = PerformanceFixtures.makeMemory(matchedBaselineSeries: shortenedSeries)
        XCTAssertThrowsError(try PerformanceFixtures.report(memory: misalignedBaseline).validateStructure())
    }

    func testMeasuredEvidenceCountsMustMatchTheFixtureConfiguration() throws {
        let oneTrialModel = ModelMeasurement(status: .measured, trialNanoseconds: [2_000_000], medianNanoseconds: 2_000_000, p95Nanoseconds: 2_000_000, madNanoseconds: 0, publicationCount: 2, modelChecksum: PerformanceFixtures.model.modelChecksum, finalStateValid: true)
        XCTAssertThrowsError(try PerformanceFixtures.report(model: oneTrialModel).validateStructure())

        let oneFrame = FrameMeasurement(status: .measured, sampleCount: 1, p95Milliseconds: 1, frameCount: 1, missedFrameCount: 0, instrumentationStatus: "fixture")
        XCTAssertThrowsError(try PerformanceFixtures.report(renderer: oneFrame).validateStructure())

        let failedCompositor = FrameMeasurement(status: .failed, sampleCount: 0, p95Milliseconds: 0, frameCount: 0, missedFrameCount: 0, instrumentationStatus: "failed")
        XCTAssertThrowsError(try PerformanceFixtures.report(renderer: oneFrame, compositor: failedCompositor).validateStructure())
    }

    func testRawTimingArraysDriveCountsAndP95ValuesForEveryMeasuredMetric() throws {
        let valid = PerformanceFixtures.report()
        XCTAssertNoThrow(try valid.validateStructure())

        let slowOutlier = FrameMeasurement(
            status: .measured,
            sampleCount: 30,
            p95Milliseconds: 1,
            frameMilliseconds: Array(repeating: 1, count: 29) + [17],
            frameCount: 30,
            missedFrameCount: 1,
            instrumentationStatus: "fixture"
        )
        XCTAssertLessThan(slowOutlier.p95Milliseconds, 16.7)
        XCTAssertNoThrow(try PerformanceFixtures.report(renderer: slowOutlier).validateStructure())

        let underreportedOutlier = FrameMeasurement(
            status: .measured,
            sampleCount: 30,
            p95Milliseconds: 1,
            frameMilliseconds: slowOutlier.frameMilliseconds,
            frameCount: 30,
            missedFrameCount: 0,
            instrumentationStatus: "fixture"
        )
        XCTAssertThrowsError(try PerformanceFixtures.report(renderer: underreportedOutlier).validateStructure())

        let badFrameP95 = FrameMeasurement(status: .measured, sampleCount: 30, p95Milliseconds: 2, frameMilliseconds: Array(repeating: 3.0, count: 30), frameCount: 30, missedFrameCount: 0, instrumentationStatus: "fixture")
        XCTAssertThrowsError(try PerformanceFixtures.report(renderer: badFrameP95).validateStructure())

        let badRedrawP95 = RedrawLayoutMeasurement(status: .measured, redrawsPerSample: Array(repeating: 1, count: 30), layoutPasses: Array(repeating: 1, count: 30), p95Milliseconds: 1, sampleMilliseconds: Array(repeating: 2.0, count: 30))
        XCTAssertThrowsError(try PerformanceFixtures.report(redrawLayout: badRedrawP95).validateStructure())

        let badResponsivenessP95 = ResponsivenessMeasurement(status: .measured, stallCount: 0, maximumMainThreadStallMilliseconds: 20, p95ResponseMilliseconds: 8, responseMilliseconds: Array(repeating: 10.0, count: 30))
        XCTAssertThrowsError(try PerformanceFixtures.report(responsiveness: badResponsivenessP95).validateStructure())

        let badInputP95 = InputToVisibleMeasurement(status: .measured, sampleCount: 30, p95Milliseconds: 20, missedSampleCount: 0, sampleMilliseconds: Array(repeating: 25.0, count: 30))
        XCTAssertThrowsError(try PerformanceFixtures.report(inputToVisible: badInputP95).validateStructure())

        let shortRawFrame = FrameMeasurement(status: .measured, sampleCount: 30, p95Milliseconds: 3, frameMilliseconds: [3.0], frameCount: 30, missedFrameCount: 0, instrumentationStatus: "fixture")
        XCTAssertThrowsError(try PerformanceFixtures.report(renderer: shortRawFrame).validateStructure())
    }

    func testMeasuredFrameMissedCountMatchesSlowRawSamples() throws {
        let slowSamples = Array(repeating: 3.0, count: 29) + [20.0]
        let underreported = FrameMeasurement(status: .measured, sampleCount: 30, p95Milliseconds: 3, frameMilliseconds: slowSamples, frameCount: 30, missedFrameCount: 0, instrumentationStatus: "fixture")
        XCTAssertThrowsError(try PerformanceFixtures.report(renderer: underreported).validateStructure())

        let fastP95WithOutlier = FrameMeasurement(status: .measured, sampleCount: 30, p95Milliseconds: 20, frameMilliseconds: slowSamples, frameCount: 30, missedFrameCount: 1, instrumentationStatus: "fixture")
        XCTAssertThrowsError(try PerformanceFixtures.report(renderer: fastP95WithOutlier).validateStructure())

        let coherent = FrameMeasurement(status: .measured, sampleCount: 30, p95Milliseconds: 3, frameMilliseconds: slowSamples, frameCount: 30, missedFrameCount: 1, instrumentationStatus: "fixture")
        XCTAssertNoThrow(try PerformanceFixtures.report(renderer: coherent).validateStructure())
    }

    func testRawTimingArraysRejectNonFiniteValuesAndDiagnosticPayloadsStayEmpty() throws {
        let nonFiniteFrame = FrameMeasurement(status: .measured, sampleCount: 30, p95Milliseconds: 3, frameMilliseconds: Array(repeating: 2.0, count: 29) + [.infinity], frameCount: 30, missedFrameCount: 0, instrumentationStatus: "fixture")
        XCTAssertThrowsError(try PerformanceFixtures.report(renderer: nonFiniteFrame).validateStructure())

        let failed = PerformanceFixtures.withStatuses(PerformanceFixtures.report(), status: .failed)
        XCTAssertTrue(failed.renderer.frameMilliseconds.isEmpty)
        XCTAssertTrue(failed.redrawLayout.sampleMilliseconds.isEmpty)
        XCTAssertTrue(failed.responsiveness.responseMilliseconds.isEmpty)
        XCTAssertTrue(failed.inputToVisible.sampleMilliseconds.isEmpty)
        XCTAssertNoThrow(try failed.validateStructure())

        let unmeasured = PerformanceFixtures.withStatuses(PerformanceFixtures.report(), status: .unmeasured)
        XCTAssertTrue(unmeasured.renderer.frameMilliseconds.isEmpty)
        XCTAssertTrue(unmeasured.redrawLayout.sampleMilliseconds.isEmpty)
        XCTAssertTrue(unmeasured.responsiveness.responseMilliseconds.isEmpty)
        XCTAssertTrue(unmeasured.inputToVisible.sampleMilliseconds.isEmpty)
        XCTAssertNoThrow(try unmeasured.validateStructure())
    }

    func testMemoryLifecycleRequiresFullCadenceAndHonestCheckpoints() throws {
        var missingRunningSample = PerformanceFixtures.memorySamples
        missingRunningSample.remove(at: 10)
        XCTAssertThrowsError(try PerformanceFixtures.report(memory: PerformanceFixtures.makeMemory(samples: missingRunningSample)).validateStructure())

        var nonZeroStoppedSample = PerformanceFixtures.memorySamples
        nonZeroStoppedSample[122] = MemorySample(elapsedSeconds: 610, rssBytes: 100_000_000, phase: .stopped, resources: PerformanceFixtures.resources)
        XCTAssertThrowsError(try PerformanceFixtures.report(memory: PerformanceFixtures.makeMemory(samples: nonZeroStoppedSample)).validateStructure())

        var nonZeroStoppingSample = PerformanceFixtures.memorySamples
        nonZeroStoppingSample[121] = MemorySample(elapsedSeconds: 605, rssBytes: 100_000_000, phase: .stopping, resources: PerformanceFixtures.resources)
        XCTAssertThrowsError(try PerformanceFixtures.report(memory: PerformanceFixtures.makeMemory(samples: nonZeroStoppingSample)).validateStructure())

        var zeroRestart = PerformanceFixtures.memorySamples
        zeroRestart[123] = MemorySample(elapsedSeconds: 615, rssBytes: 100_000_000, phase: .restarted, resources: PerformanceFixtures.zeroResources)
        XCTAssertThrowsError(try PerformanceFixtures.report(memory: PerformanceFixtures.makeMemory(samples: zeroRestart, endLiveResourceCounts: PerformanceFixtures.zeroResources)).validateStructure())

        let highRestartResources = ResourceCounts(overlays: 2, timers: 2, handlers: 2, windows: 2, observers: 2)
        var overgrownRestart = PerformanceFixtures.memorySamples
        overgrownRestart[123] = MemorySample(elapsedSeconds: 615, rssBytes: 100_000_000, phase: .restarted, resources: highRestartResources)
        XCTAssertThrowsError(try PerformanceFixtures.report(memory: PerformanceFixtures.makeMemory(samples: overgrownRestart, peakLiveResourceCounts: highRestartResources, endLiveResourceCounts: highRestartResources)).validateStructure())
    }

    func testPostWarmupLeastSquaresTrendRejectsGrowThenDropEvenWhenFinalRSSFalls() throws {
        var samples = PerformanceFixtures.memorySamples
        for index in 5..<120 {
            samples[index] = MemorySample(elapsedSeconds: Double(index * 5), rssBytes: 100_000_000 + Int64(index * 1_000), phase: .running, resources: PerformanceFixtures.resources)
        }
        samples[120] = MemorySample(elapsedSeconds: 600, rssBytes: 100_000_500, phase: .running, resources: PerformanceFixtures.resources)

        let runningRSS = samples.prefix(121).map(\.rssBytes)
        let aggregates = (0..<11).map { index in
            let values = runningRSS[(index * 11)..<((index + 1) * 11)]
            return MemoryAggregate(intervalIndex: index, sampleCount: values.count, meanRSSBytes: Int64((values.reduce(0.0) { $0 + Double($1) } / Double(values.count)).rounded()), peakRSSBytes: values.max()!)
        }
        let slope = PerformanceFixtures.leastSquaresSlope(for: samples)
        let memory = PerformanceFixtures.makeMemory(samples: samples, aggregates: aggregates, peakRSSBytes: runningRSS.max()!, finalWindowDeltaBytes: 500, finalWindowDeltaPercent: 0.0005, postWarmupSlopeBytesPerSecond: slope)
        let report = PerformanceFixtures.report(memory: memory)
        XCTAssertNoThrow(try report.validateStructure())
        XCTAssertThrowsError(try report.validateCompletion())
    }

    func testPostWarmupSlopeUsesDocumentedNoiseTolerance() throws {
        let withinNoise = PerformanceFixtures.report(memory: PerformanceFixtures.makeMemory(postWarmupSlopeBytesPerSecond: 5e-10))
        XCTAssertNoThrow(try withinNoise.validateStructure())
        XCTAssertNoThrow(try withinNoise.validateCompletion())

        let aboveNoise = PerformanceFixtures.report(memory: PerformanceFixtures.makeMemory(postWarmupSlopeBytesPerSecond: 2e-9))
        XCTAssertThrowsError(try aboveNoise.validateCompletion())
    }

    func testDiagnosticMemoryRejectsNonFiniteSlopeEvenWithoutSamples() throws {
        let nanMemory = PerformanceFixtures.makeMemory(samples: [], postWarmupSlopeBytesPerSecond: .nan, status: .failed)
        XCTAssertThrowsError(try PerformanceFixtures.report(memory: nanMemory).validateStructure())

        let infiniteMemory = PerformanceFixtures.makeMemory(samples: [], postWarmupSlopeBytesPerSecond: .infinity, status: .unmeasured)
        XCTAssertThrowsError(try PerformanceFixtures.report(memory: infiniteMemory).validateStructure())
    }

    func testFailedAndUnmeasuredReportsRemainStructurallyValidButCannotComplete() throws {
        let failed = PerformanceFixtures.withStatuses(PerformanceFixtures.report(), status: .failed)
        XCTAssertEqual(failed.disposition, .revise)
        XCTAssertNoThrow(try failed.validateStructure())
        XCTAssertThrowsError(try failed.validateCompletion())

        let unmeasured = PerformanceFixtures.withStatuses(PerformanceFixtures.report(), status: .unmeasured)
        XCTAssertEqual(unmeasured.disposition, .revise)
        XCTAssertNoThrow(try unmeasured.validateStructure())
        XCTAssertThrowsError(try unmeasured.validateCompletion())

        for invalidDisposition in [Disposition.acceptedNoRegression, .blocked] {
            let failedReport = PerformanceFixtures.withStatuses(PerformanceFixtures.report(), status: .failed, disposition: invalidDisposition)
            XCTAssertThrowsError(try failedReport.validateStructure())
            let unmeasuredReport = PerformanceFixtures.withStatuses(PerformanceFixtures.report(), status: .unmeasured, disposition: invalidDisposition)
            XCTAssertThrowsError(try unmeasuredReport.validateStructure())
        }
    }

    func testValidMeasuredReportPassesCompletionValidation() throws {
        let report = PerformanceFixtures.report()
        XCTAssertNoThrow(try report.validateStructure())
        XCTAssertNoThrow(try report.validateCompletion())
    }

    func testNoncanonicalConfigurationIsRejectedBeforeCompletion() throws {
        let nonstandardConfiguration = PerformanceConfiguration(
            fixtureMarkCount: 12,
            samplesPerGesture: 240,
            warmupCount: 5,
            trialCount: 30,
            pairsPerOrder: 14,
            bootstrapSeed: 48271,
            bootstrapResamples: 10_000,
            memoryWindowSeconds: 600,
            memorySampleIntervalSeconds: 5,
            harnessVersion: PerformanceFixtures.configuration.harnessVersion,
            foundationIdentity: PerformanceFixtures.foundation,
            buildContractVersion: PerformanceFixtures.configuration.buildContractVersion
        )
        let run = PerformanceRunProvenance(
            variant: PerformanceFixtures.run.variant,
            outputRoot: PerformanceFixtures.run.outputRoot,
            sourceRef: PerformanceFixtures.run.sourceRef,
            build: PerformanceFixtures.build,
            host: PerformanceFixtures.host,
            recordedAtUTC: PerformanceFixtures.recordedAtUTC,
            configuration: nonstandardConfiguration,
            foundationProvenancePath: PerformanceFixtures.run.foundationProvenancePath,
            foundation: PerformanceFixtures.foundation,
            harnessVersion: nonstandardConfiguration.harnessVersion,
            buildContractVersion: nonstandardConfiguration.buildContractVersion,
            acceptedFoundationArtifactSHA256: PerformanceFixtures.run.acceptedFoundationArtifactSHA256
        )
        let report = PerformanceFixtures.report(run: run)
        XCTAssertThrowsError(try report.validateStructure())
    }

    func testBootstrapOrDebugBuildCanBeDiagnosticButCannotComplete() throws {
        let debugBuild = BuildProvenance(
            sourceTreeStatus: .clean,
            sourceIdentity: SourceIdentity(kind: .sourceCommitSHA, value: PerformanceFixtures.commit),
            sourceManifestSHA256: PerformanceFixtures.sourceManifest,
            executableSHA256: PerformanceFixtures.executable,
            bundleManifestSHA256: PerformanceFixtures.bundle,
            buildConfiguration: "debug",
            recordedAtUTC: PerformanceFixtures.recordedAtUTC,
            foundation: PerformanceFixtures.foundation,
            harnessVersion: PerformanceFixtures.configuration.harnessVersion,
            buildContractVersion: PerformanceFixtures.configuration.buildContractVersion,
            acceptedFoundationArtifactSHA256: nil
        )
        let debugIdentity = MeasurementIdentity(sourceCommitSHA: PerformanceFixtures.commit, contentManifestSHA256: nil, hostModel: "MacBookPro18,3", macOSVersion: "14.6.1", xcodeVersion: "16.0", developerDirectory: "/Applications/Xcode.app/Contents/Developer", powerState: "ac", displayState: "one-display", buildConfiguration: "debug")
        let debugRun = PerformanceRunProvenance(variant: "bootstrap", outputRoot: "build/bootstrap", sourceRef: PerformanceFixtures.commit, build: debugBuild, host: PerformanceFixtures.host, recordedAtUTC: PerformanceFixtures.recordedAtUTC, configuration: PerformanceFixtures.configuration, foundationProvenancePath: PerformanceFixtures.run.foundationProvenancePath, foundation: PerformanceFixtures.foundation, harnessVersion: PerformanceFixtures.configuration.harnessVersion, buildContractVersion: PerformanceFixtures.configuration.buildContractVersion, acceptedFoundationArtifactSHA256: nil)
        let report = PerformanceFixtures.report(identity: debugIdentity, build: debugBuild, run: debugRun)
        XCTAssertNoThrow(try report.validateStructure())
        XCTAssertThrowsError(try report.validateCompletion())
    }

    func testAuthoritativeRunRequiresAcceptedFoundationArtifactSHA() throws {
        let diagnosticBuild = BuildProvenance(
            sourceTreeStatus: .clean,
            sourceIdentity: SourceIdentity(kind: .sourceCommitSHA, value: PerformanceFixtures.commit),
            sourceManifestSHA256: PerformanceFixtures.sourceManifest,
            executableSHA256: PerformanceFixtures.executable,
            bundleManifestSHA256: PerformanceFixtures.bundle,
            buildConfiguration: "release",
            recordedAtUTC: PerformanceFixtures.recordedAtUTC,
            foundation: PerformanceFixtures.foundation,
            harnessVersion: PerformanceFixtures.configuration.harnessVersion,
            buildContractVersion: PerformanceFixtures.configuration.buildContractVersion,
            acceptedFoundationArtifactSHA256: nil
        )
        let diagnosticRun = PerformanceRunProvenance(
            variant: "candidate",
            outputRoot: "build/candidate",
            sourceRef: PerformanceFixtures.commit,
            build: diagnosticBuild,
            host: PerformanceFixtures.host,
            recordedAtUTC: PerformanceFixtures.recordedAtUTC,
            configuration: PerformanceFixtures.configuration,
            foundationProvenancePath: PerformanceFixtures.run.foundationProvenancePath,
            foundation: PerformanceFixtures.foundation,
            harnessVersion: PerformanceFixtures.configuration.harnessVersion,
            buildContractVersion: PerformanceFixtures.configuration.buildContractVersion,
            acceptedFoundationArtifactSHA256: nil
        )
        let diagnosticReport = PerformanceFixtures.report(build: diagnosticBuild, run: diagnosticRun)
        XCTAssertNoThrow(try diagnosticReport.validateStructure())
        XCTAssertThrowsError(try diagnosticReport.validateCompletion())

        let acceptedReport = PerformanceFixtures.report()
        XCTAssertEqual(acceptedReport.buildProvenance.acceptedFoundationArtifactSHA256?.count, 64)
        XCTAssertEqual(acceptedReport.runProvenance.acceptedFoundationArtifactSHA256, acceptedReport.buildProvenance.acceptedFoundationArtifactSHA256)
        XCTAssertNoThrow(try acceptedReport.validateCompletion())
    }

    @MainActor
    func testInjectedAdaptersProduceMeasuredReportWithPropagatedProvenance() throws {
        let adapters = PerformanceHarness.AdapterBundle(
            model: FixtureModelAdapter(),
            renderer: FixtureRendererAdapter(measurement: PerformanceFixtures.renderer),
            compositor: FixtureRendererAdapter(measurement: PerformanceFixtures.compositor),
            combinedFrame: FixtureRendererAdapter(measurement: PerformanceFixtures.combinedFrame),
            launch: FixtureLaunchAdapter(measurement: PerformanceFixtures.launch),
            allocations: FixtureAllocationAdapter(measurement: PerformanceFixtures.allocations),
            redrawLayout: FixtureRedrawLayoutAdapter(measurement: PerformanceFixtures.redrawLayout),
            responsiveness: FixtureResponsivenessAdapter(measurement: PerformanceFixtures.responsiveness),
            inputToVisible: FixtureInputToVisibleAdapter(measurement: PerformanceFixtures.inputToVisible),
            memory: FixtureMemoryAdapter(measurement: PerformanceFixtures.memory),
            resilience: FixtureResilienceAdapter(measurement: PerformanceFixtures.resilience)
        )

        let report = try PerformanceHarness.run(
            configuration: PerformanceFixtures.configuration,
            buildProvenance: PerformanceFixtures.build,
            runProvenance: PerformanceFixtures.run,
            adapters: adapters
        )

        XCTAssertEqual(report.reportKind, .measurement)
        XCTAssertEqual(report.harnessVersion, PerformanceFixtures.configuration.harnessVersion)
        XCTAssertEqual(report.foundationIdentity, PerformanceFixtures.foundation)
        XCTAssertEqual(report.buildContractVersion, PerformanceFixtures.configuration.buildContractVersion)
        XCTAssertEqual(report.buildProvenance, PerformanceFixtures.build)
        XCTAssertEqual(report.runProvenance, PerformanceFixtures.run)
        XCTAssertEqual(report.identity.sourceCommitSHA, PerformanceFixtures.commit)
        XCTAssertEqual(report.fixture.markCount, PerformanceFixtures.configuration.fixtureMarkCount)
        XCTAssertEqual(report.model, PerformanceFixtures.model)
        XCTAssertEqual(report.renderer.frameMilliseconds.count, PerformanceFixtures.configuration.trialCount)
        XCTAssertEqual(report.compositor.frameMilliseconds.count, PerformanceFixtures.configuration.trialCount)
        XCTAssertEqual(report.combinedFrame.frameMilliseconds.count, PerformanceFixtures.configuration.trialCount)
        XCTAssertEqual(report.redrawLayout.sampleMilliseconds.count, PerformanceFixtures.configuration.trialCount)
        XCTAssertEqual(report.responsiveness.responseMilliseconds.count, PerformanceFixtures.configuration.trialCount)
        XCTAssertEqual(report.inputToVisible.sampleMilliseconds.count, PerformanceFixtures.configuration.trialCount)
        XCTAssertEqual(report.redrawLayout.p95Milliseconds, 1.5)
        XCTAssertEqual(report.responsiveness.p95ResponseMilliseconds, 10)
        XCTAssertEqual(report.inputToVisible.p95Milliseconds, 25)
        XCTAssertEqual(report.memory.samples.count, 124)
        XCTAssertEqual(report.memory.samples.prefix(121).map(\.phase), Array(repeating: .running, count: 121))
        XCTAssertEqual(report.disposition, .acceptedNoRegression)
        try report.validateStructure()
    }

    @MainActor
    func testUnavailableAdaptersRemainUnmeasuredAndNeverFabricateZerosAsMeasured() throws {
        let report = try PerformanceHarness.run(
            configuration: PerformanceFixtures.configuration,
            buildProvenance: PerformanceFixtures.build,
            runProvenance: PerformanceFixtures.run
        )

        XCTAssertEqual(report.disposition, .revise)
        XCTAssertEqual(report.compositor.status, .unmeasured)
        XCTAssertEqual(report.compositor.sampleCount, 0)
        XCTAssertEqual(report.compositor.frameCount, 0)
        XCTAssertEqual(report.memory.status, .unmeasured)
        XCTAssertTrue(report.memory.samples.isEmpty)
        XCTAssertTrue(report.launch.coldMilliseconds.isEmpty)
        XCTAssertTrue(report.launch.warmMilliseconds.isEmpty)
        XCTAssertFalse(report.compositor.instrumentationStatus.isEmpty)
        XCTAssertFalse(report.memory.postWarmupSlopeBytesPerSecond.isNaN)
        try report.validateStructure()
        XCTAssertThrowsError(try report.validateCompletion())
    }

    @MainActor
    func testModelEvidenceFailsWhenChecksumStateOrPublicationsAreNotExact() {
        let expectedTrials = PerformanceFixtures.configuration.trialCount
        XCTAssertEqual(
            PerformanceHarness.modelStatus(
                checksumIsStable: false,
                finalStateValid: true,
                publicationsPerGesture: Array(repeating: 2, count: expectedTrials),
                expectedTrialCount: expectedTrials
            ),
            .failed
        )
        XCTAssertEqual(
            PerformanceHarness.modelStatus(
                checksumIsStable: true,
                finalStateValid: false,
                publicationsPerGesture: Array(repeating: 2, count: expectedTrials),
                expectedTrialCount: expectedTrials
            ),
            .failed
        )
        XCTAssertEqual(
            PerformanceHarness.modelStatus(
                checksumIsStable: true,
                finalStateValid: true,
                publicationsPerGesture: Array(repeating: 2, count: expectedTrials - 1),
                expectedTrialCount: expectedTrials
            ),
            .failed
        )
        XCTAssertEqual(
            PerformanceHarness.modelStatus(
                checksumIsStable: true,
                finalStateValid: true,
                publicationsPerGesture: Array(repeating: 1, count: expectedTrials),
                expectedTrialCount: expectedTrials
            ),
            .failed
        )
        XCTAssertEqual(
            PerformanceHarness.modelStatus(
                checksumIsStable: true,
                finalStateValid: true,
                publicationsPerGesture: Array(repeating: 2, count: expectedTrials),
                expectedTrialCount: expectedTrials
            ),
            .measured
        )
    }

    @MainActor
    func testRealModelAdapterPublishesOnlyStableCompleteBenchmarkEvidence() {
        let measurement = PerformanceHarness.measureModel(configuration: .standard)

        XCTAssertEqual(measurement.status, .measured)
        XCTAssertEqual(measurement.trialNanoseconds.count, PerformanceConfiguration.standard.trialCount)
        XCTAssertEqual(measurement.publicationCount, 2)
        XCTAssertTrue(measurement.finalStateValid)
        XCTAssertFalse(measurement.modelChecksum.isEmpty)
    }

    @MainActor
    func testFailedInjectedAdapterPreservesFailureDisposition() throws {
        let failedRenderer = FrameMeasurement(
            status: .failed,
            sampleCount: 0,
            p95Milliseconds: 0,
            frameCount: 0,
            missedFrameCount: 0,
            instrumentationStatus: "offscreen-canvasview-failed"
        )
        let adapters = PerformanceHarness.AdapterBundle(
            model: FixtureModelAdapter(),
            renderer: FixtureRendererAdapter(measurement: failedRenderer),
            compositor: FixtureRendererAdapter(measurement: PerformanceFixtures.compositor),
            combinedFrame: FixtureRendererAdapter(measurement: PerformanceFixtures.combinedFrame),
            launch: FixtureLaunchAdapter(measurement: PerformanceFixtures.launch),
            allocations: FixtureAllocationAdapter(measurement: PerformanceFixtures.allocations),
            redrawLayout: FixtureRedrawLayoutAdapter(measurement: PerformanceFixtures.redrawLayout),
            responsiveness: FixtureResponsivenessAdapter(measurement: PerformanceFixtures.responsiveness),
            inputToVisible: FixtureInputToVisibleAdapter(measurement: PerformanceFixtures.inputToVisible),
            memory: FixtureMemoryAdapter(measurement: PerformanceFixtures.memory),
            resilience: FixtureResilienceAdapter(measurement: PerformanceFixtures.resilience)
        )

        let report = try PerformanceHarness.run(
            configuration: PerformanceFixtures.configuration,
            buildProvenance: PerformanceFixtures.build,
            runProvenance: PerformanceFixtures.run,
            adapters: adapters
        )

        XCTAssertEqual(report.renderer.status, .failed)
        XCTAssertEqual(report.disposition, .revise)
        XCTAssertThrowsError(try report.validateCompletion())
    }

    @MainActor
    func testRunRejectsConfigurationMismatchBeforeMeasuring() {
        let mismatched = PerformanceConfiguration(
            fixtureMarkCount: 12,
            samplesPerGesture: 240,
            warmupCount: 5,
            trialCount: 29,
            pairsPerOrder: 15,
            bootstrapSeed: 48271,
            bootstrapResamples: 10_000,
            memoryWindowSeconds: 600,
            memorySampleIntervalSeconds: 5,
            harnessVersion: PerformanceFixtures.configuration.harnessVersion,
            foundationIdentity: PerformanceFixtures.foundation,
            buildContractVersion: PerformanceFixtures.configuration.buildContractVersion
        )

        XCTAssertThrowsError(try PerformanceHarness.run(
            configuration: mismatched,
            buildProvenance: PerformanceFixtures.build,
            runProvenance: PerformanceFixtures.run
        ))
    }

    @MainActor
    func testPublicRunRejectsNonstandardConfigurationBeforeUsingFixedAdapters() {
        let nonstandard = PerformanceConfiguration(
            fixtureMarkCount: 12,
            samplesPerGesture: 240,
            warmupCount: 5,
            trialCount: 29,
            pairsPerOrder: 15,
            bootstrapSeed: 48271,
            bootstrapResamples: 10_000,
            memoryWindowSeconds: 600,
            memorySampleIntervalSeconds: 5,
            harnessVersion: PerformanceFixtures.configuration.harnessVersion,
            foundationIdentity: PerformanceFixtures.foundation,
            buildContractVersion: PerformanceFixtures.configuration.buildContractVersion
        )
        let nonstandardRun = PerformanceRunProvenance(
            variant: PerformanceFixtures.run.variant,
            outputRoot: PerformanceFixtures.run.outputRoot,
            sourceRef: PerformanceFixtures.run.sourceRef,
            build: PerformanceFixtures.build,
            host: PerformanceFixtures.host,
            recordedAtUTC: PerformanceFixtures.recordedAtUTC,
            configuration: nonstandard,
            foundationProvenancePath: PerformanceFixtures.run.foundationProvenancePath,
            foundation: PerformanceFixtures.foundation,
            harnessVersion: nonstandard.harnessVersion,
            buildContractVersion: nonstandard.buildContractVersion,
            acceptedFoundationArtifactSHA256: PerformanceFixtures.run.acceptedFoundationArtifactSHA256
        )

        XCTAssertThrowsError(try PerformanceHarness.run(
            configuration: nonstandard,
            buildProvenance: PerformanceFixtures.build,
            runProvenance: nonstandardRun
        ))
    }

    @MainActor
    func testOffscreenRendererUsesRealCanvasViewPathWithoutInteractiveComposition() {
        let measurement = PerformanceHarness.measureRenderer(configuration: PerformanceFixtures.configuration)

        XCTAssertNotEqual(measurement.instrumentationStatus, "synthetic")
        XCTAssertFalse(measurement.instrumentationStatus.contains("global"))
        if measurement.status == .measured {
            XCTAssertEqual(measurement.sampleCount, PerformanceFixtures.configuration.trialCount)
            XCTAssertEqual(measurement.frameCount, PerformanceFixtures.configuration.trialCount)
            XCTAssertEqual(measurement.frameMilliseconds.count, PerformanceFixtures.configuration.trialCount)
            XCTAssertEqual(measurement.missedFrameCount, measurement.frameMilliseconds.filter { $0 > 16.7 }.count)
            XCTAssertGreaterThan(measurement.p95Milliseconds, 0)
        } else {
            XCTAssertEqual(measurement.status, .unmeasured)
            XCTAssertEqual(measurement.sampleCount, 0)
        }
    }

    func testOffscreenRendererUsesExplicitSRGBRGBA8BitmapContract() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/PointerAppKit/Diagnostics/PerformanceHarness.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("CGColorSpace(name: CGColorSpace.sRGB)"))
        XCTAssertFalse(source.contains("CGColorSpaceCreateDeviceRGB"))
        XCTAssertTrue(source.contains("bitsPerComponent: 8"))
        XCTAssertTrue(source.contains("bytesPerRow: 512 * 4"))
    }

    @MainActor
    func testRendererSemanticOracleRejectsInvalidMarkCardinalityAsFailed() {
        let snapshot = RendererSemanticSnapshot(
            committedMarkCount: 11,
            hasActiveDraft: false,
            nonTransparentPixelCount: 1_000,
            occupiedQuadrantCount: 4,
            pixelChecksum: 1,
            boundsWidth: 512,
            boundsHeight: 512
        )

        XCTAssertEqual(
            OffscreenCanvasRendererAdapter.semanticStatus(
                snapshot
            ),
            .failed
        )
    }

    @MainActor
    func testRendererSemanticOracleRejectsEmptyNoOpPixelsAsFailed() {
        let snapshot = RendererSemanticSnapshot(
            committedMarkCount: PerformanceConfiguration.standard.fixtureMarkCount,
            hasActiveDraft: false,
            nonTransparentPixelCount: 0,
            occupiedQuadrantCount: 0,
            pixelChecksum: 0,
            boundsWidth: 512,
            boundsHeight: 512
        )

        XCTAssertEqual(
            OffscreenCanvasRendererAdapter.semanticStatus(
                snapshot
            ),
            .failed
        )
    }

    @MainActor
    func testRendererSemanticOracleRejectsFourDotWrongGeometryPixels() {
        let snapshot = RendererSemanticSnapshot(
            renderPlanIdentity: Self.canonicalRenderPlanIdentity,
            committedMarkCount: PerformanceConfiguration.standard.fixtureMarkCount,
            hasActiveDraft: false,
            positiveMarkOccupancy: Array(repeating: 1, count: 12),
            positiveMarkColorMatches: Array(repeating: 1, count: 12),
            negativeRegionOccupied: Array(repeating: false, count: Self.canonicalNegativeRegionCount),
            nonTransparentPixelCount: 4,
            occupiedQuadrantCount: 4,
            pixelChecksum: 2,
            boundsWidth: 512,
            boundsHeight: 512
        )

        XCTAssertEqual(
            OffscreenCanvasRendererAdapter.semanticStatus(
                snapshot
            ),
            .failed
        )
    }

    @MainActor
    func testRendererSemanticOracleRejectsCanonicalPlanWithWrongStyle() {
        let wrongStyleIdentity = Self.canonicalRenderPlanIdentity.replacingOccurrences(
            of: "rgba=1000000,0,0,1000000",
            with: "rgba=0,1000000,0,1000000"
        )
        let snapshot = RendererSemanticSnapshot(
            renderPlanIdentity: wrongStyleIdentity,
            committedMarkCount: PerformanceConfiguration.standard.fixtureMarkCount,
            hasActiveDraft: false,
            positiveMarkOccupancy: Self.canonicalMinimumPositiveHits,
            positiveMarkColorMatches: Self.canonicalMinimumPositiveHits,
            negativeRegionOccupied: Array(repeating: false, count: Self.canonicalNegativeRegionCount),
            nonTransparentPixelCount: 1_000,
            occupiedQuadrantCount: 4,
            pixelChecksum: 2,
            boundsWidth: 512,
            boundsHeight: 512
        )

        XCTAssertEqual(
            OffscreenCanvasRendererAdapter.semanticStatus(snapshot),
            .failed
        )
    }

    @MainActor
    func testRendererSemanticOracleRejectsCanonicalPlanWithWrongOpacity() {
        let wrongOpacityIdentity = Self.canonicalRenderPlanIdentity.replacingOccurrences(
            of: "opacity=1000000",
            with: "opacity=500000"
        )
        let snapshot = RendererSemanticSnapshot(
            renderPlanIdentity: wrongOpacityIdentity,
            committedMarkCount: PerformanceConfiguration.standard.fixtureMarkCount,
            hasActiveDraft: false,
            positiveMarkOccupancy: Self.canonicalMinimumPositiveHits,
            positiveMarkColorMatches: Self.canonicalMinimumPositiveHits,
            negativeRegionOccupied: Array(repeating: false, count: Self.canonicalNegativeRegionCount),
            nonTransparentPixelCount: 1_000,
            occupiedQuadrantCount: 4,
            pixelChecksum: 2,
            boundsWidth: 512,
            boundsHeight: 512
        )

        XCTAssertEqual(
            OffscreenCanvasRendererAdapter.semanticStatus(snapshot),
            .failed
        )
    }

    @MainActor
    func testRendererSemanticOracleAcceptsCanonicalNonEmptyOutput() {
        let snapshot = RendererSemanticSnapshot(
            renderPlanIdentity: Self.canonicalRenderPlanIdentity,
            committedMarkCount: PerformanceConfiguration.standard.fixtureMarkCount,
            hasActiveDraft: false,
            positiveMarkOccupancy: Self.canonicalMinimumPositiveHits,
            positiveMarkColorMatches: Self.canonicalMinimumPositiveHits,
            negativeRegionOccupied: Array(repeating: false, count: Self.canonicalNegativeRegionCount),
            nonTransparentPixelCount: 12,
            occupiedQuadrantCount: 4,
            pixelChecksum: 1,
            boundsWidth: 512,
            boundsHeight: 512
        )

        XCTAssertEqual(
            OffscreenCanvasRendererAdapter.semanticStatus(
                snapshot
            ),
            .measured
        )
    }

    @MainActor
    func testRendererSemanticOracleRejectsMissingPerMarkOccupancy() {
        let snapshot = RendererSemanticSnapshot(
            renderPlanIdentity: Self.canonicalRenderPlanIdentity,
            committedMarkCount: PerformanceConfiguration.standard.fixtureMarkCount,
            hasActiveDraft: false,
            positiveMarkOccupancy: Array(Self.canonicalMinimumPositiveHits.dropLast()) + [0],
            positiveMarkColorMatches: Self.canonicalMinimumPositiveHits,
            negativeRegionOccupied: Array(repeating: false, count: Self.canonicalNegativeRegionCount),
            nonTransparentPixelCount: 12,
            occupiedQuadrantCount: 4,
            pixelChecksum: 2,
            boundsWidth: 512,
            boundsHeight: 512
        )

        XCTAssertEqual(
            OffscreenCanvasRendererAdapter.semanticStatus(snapshot),
            .failed
        )
    }

    @MainActor
    func testRendererSemanticOracleRejectsWrongSemanticPlan() {
        let snapshot = RendererSemanticSnapshot(
            renderPlanIdentity: "pointer-render-plan/wrong",
            committedMarkCount: PerformanceConfiguration.standard.fixtureMarkCount,
            hasActiveDraft: false,
            positiveMarkOccupancy: Self.canonicalMinimumPositiveHits,
            positiveMarkColorMatches: Self.canonicalMinimumPositiveHits,
            negativeRegionOccupied: Array(repeating: false, count: Self.canonicalNegativeRegionCount),
            nonTransparentPixelCount: 12,
            occupiedQuadrantCount: 4,
            pixelChecksum: 2,
            boundsWidth: 512,
            boundsHeight: 512
        )

        XCTAssertEqual(
            OffscreenCanvasRendererAdapter.semanticStatus(snapshot),
            .failed
        )
    }

    @MainActor
    func testRendererSemanticOracleRejectsUnexpectedNegativeRegionPixels() {
        let snapshot = RendererSemanticSnapshot(
            renderPlanIdentity: Self.canonicalRenderPlanIdentity,
            committedMarkCount: PerformanceConfiguration.standard.fixtureMarkCount,
            hasActiveDraft: false,
            positiveMarkOccupancy: Self.canonicalMinimumPositiveHits,
            positiveMarkColorMatches: Self.canonicalMinimumPositiveHits,
            negativeRegionOccupied: Array(repeating: false, count: Self.canonicalNegativeRegionCount).enumerated().map { $0.offset == 4 },
            nonTransparentPixelCount: 13,
            occupiedQuadrantCount: 4,
            pixelChecksum: 2,
            boundsWidth: 512,
            boundsHeight: 512
        )

        XCTAssertEqual(
            OffscreenCanvasRendererAdapter.semanticStatus(snapshot),
            .failed
        )
    }

    @MainActor
    func testRendererSemanticOracleAllowsPortableRasterizerEdgeDrift() {
        let snapshot = RendererSemanticSnapshot(
            renderPlanIdentity: Self.canonicalRenderPlanIdentity,
            committedMarkCount: PerformanceConfiguration.standard.fixtureMarkCount,
            hasActiveDraft: false,
            positiveMarkOccupancy: Self.canonicalMinimumPositiveHits,
            positiveMarkColorMatches: Self.canonicalMinimumPositiveHits,
            negativeRegionOccupied: Array(repeating: false, count: Self.canonicalNegativeRegionCount),
            nonTransparentPixelCount: 12,
            occupiedQuadrantCount: 4,
            pixelChecksum: 0xfeed,
            boundsWidth: 512,
            boundsHeight: 512
        )

        XCTAssertEqual(
            OffscreenCanvasRendererAdapter.semanticStatus(snapshot),
            .measured
        )
    }

    @MainActor
    func testRendererSemanticOracleRejectsSameHostRasterInstability() {
        let before = RendererSemanticSnapshot(
            renderPlanIdentity: Self.canonicalRenderPlanIdentity,
            committedMarkCount: PerformanceConfiguration.standard.fixtureMarkCount,
            hasActiveDraft: false,
            positiveMarkOccupancy: Self.canonicalMinimumPositiveHits,
            positiveMarkColorMatches: Self.canonicalMinimumPositiveHits,
            negativeRegionOccupied: Array(repeating: false, count: Self.canonicalNegativeRegionCount),
            nonTransparentPixelCount: 12,
            occupiedQuadrantCount: 4,
            pixelChecksum: 1,
            boundsWidth: 512,
            boundsHeight: 512
        )
        let after = RendererSemanticSnapshot(
            renderPlanIdentity: Self.canonicalRenderPlanIdentity,
            committedMarkCount: PerformanceConfiguration.standard.fixtureMarkCount,
            hasActiveDraft: false,
            positiveMarkOccupancy: Self.canonicalMinimumPositiveHits,
            positiveMarkColorMatches: Self.canonicalMinimumPositiveHits,
            negativeRegionOccupied: Array(repeating: false, count: Self.canonicalNegativeRegionCount),
            nonTransparentPixelCount: 12,
            occupiedQuadrantCount: 4,
            pixelChecksum: 2,
            boundsWidth: 512,
            boundsHeight: 512
        )

        XCTAssertEqual(
            OffscreenCanvasRendererAdapter.semanticRasterStatus(
                before: before,
                after: after
            ),
            .failed
        )
    }

    func testRendererTimingStartsAfterBitmapPreparation() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/PointerAppKit/Diagnostics/PerformanceHarness.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let loopStart = try XCTUnwrap(
            source.range(
                of: "for _ in 0..<configuration.trialCount",
                options: .backwards
            )
        )
        let loopEnd = try XCTUnwrap(source.range(of: "guard samples.allSatisfy", range: loopStart.upperBound..<source.endIndex))
        let timedLoop = String(source[loopStart.lowerBound..<loopEnd.lowerBound])
        let preparation = try XCTUnwrap(timedLoop.range(of: "prepareBitmap()"))
        let timerStart = try XCTUnwrap(timedLoop.range(of: "let start = CACurrentMediaTime()"))

        XCTAssertLessThan(preparation.lowerBound, timerStart.lowerBound)
        XCTAssertFalse(timedLoop.contains("context.clear(frame)"))
        XCTAssertTrue(timedLoop.contains("renderIntoBitmap()"))
    }

    @MainActor
    func testDenseModelRejectsWrongAppendedMark() {
        let expectedPoints = (0...240).map { index in
            NormalizedPoint(
                x: 0.1 + Double(index) * 0.0005,
                y: 0.2 + (index.isMultiple(of: 2) ? 0 : 0.005)
            )
        }
        let valid = Mark(geometry: .freehand(expectedPoints), style: .default)
        let wrongTool = Mark(
            geometry: .rectangle(
                NormalizedRect(x: 0.1, y: 0.2, width: 0.12, height: 0.12)
            ),
            style: .default
        )
        var wrongPoints = expectedPoints
        wrongPoints[120] = NormalizedPoint(x: 0.9, y: 0.9)
        let wrongGeometry = Mark(geometry: .freehand(wrongPoints), style: .default)
        let wrongStyle = Mark(
            geometry: .freehand(expectedPoints),
            style: MarkStyle(color: .red, strokeWidth: 2, opacity: 1)
        )

        XCTAssertTrue(GestureBenchmarkInstrumentationAdapter.denseFreehandIsValid(valid, sampleCount: 240))
        XCTAssertFalse(GestureBenchmarkInstrumentationAdapter.denseFreehandIsValid(wrongTool, sampleCount: 240))
        XCTAssertFalse(GestureBenchmarkInstrumentationAdapter.denseFreehandIsValid(wrongGeometry, sampleCount: 240))
        XCTAssertFalse(GestureBenchmarkInstrumentationAdapter.denseFreehandIsValid(wrongStyle, sampleCount: 240))
    }

    func testDenseModelTimingEndsImmediatelyAfterCommit() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/PointerAppKit/Diagnostics/PerformanceHarness.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let functionStart = try XCTUnwrap(source.range(of: "private static func denseMeasurement"))
        let functionEnd = try XCTUnwrap(source.range(of: "private static func checksum", range: functionStart.upperBound..<source.endIndex))
        let function = String(source[functionStart.lowerBound..<functionEnd.lowerBound])
        let commit = try XCTUnwrap(function.range(of: "let committed = session.commitGesture()"))
        let end = try XCTUnwrap(function.range(of: "let end = CACurrentMediaTime()"))
        let publicationCheck = try XCTUnwrap(function.range(of: "if committed.boundaryEvent == .committed"))
        let commitToEnd = String(function[commit.upperBound..<end.lowerBound])

        XCTAssertLessThan(commit.lowerBound, end.lowerBound)
        XCTAssertLessThan(end.lowerBound, publicationCheck.lowerBound)
        XCTAssertFalse(commitToEnd.contains("session.canvas(for:"))
        XCTAssertFalse(commitToEnd.contains("undo"))
        XCTAssertFalse(commitToEnd.contains("checksum(for:"))
    }

    @MainActor
    func testCanonicalProfilesMeasureSeparateStandardAndDenseEvidence() {
        let standardModel = PerformanceHarness.measureModel(configuration: .standard12)
        let denseModel = PerformanceHarness.measureModel(configuration: .dense1000)
        XCTAssertEqual(standardModel.status, .measured)
        XCTAssertEqual(denseModel.status, .measured)
        XCTAssertEqual(standardModel.trialNanoseconds.count, PerformanceConfiguration.standard12.trialCount)
        XCTAssertEqual(denseModel.trialNanoseconds.count, PerformanceConfiguration.dense1000.trialCount)
        XCTAssertNotEqual(standardModel.modelChecksum, denseModel.modelChecksum)
        XCTAssertEqual(standardModel.publicationCount, 2)
        XCTAssertEqual(denseModel.publicationCount, 2)
        XCTAssertTrue(standardModel.finalStateValid)
        XCTAssertTrue(denseModel.finalStateValid)

        let standardRenderer = PerformanceHarness.measureRenderer(configuration: .standard12)
        let denseRenderer = PerformanceHarness.measureRenderer(configuration: .dense1000)
        XCTAssertEqual(standardRenderer.status, .measured)
        XCTAssertEqual(denseRenderer.status, .measured)
        XCTAssertTrue(standardRenderer.instrumentationStatus.contains("standard12"))
        XCTAssertTrue(denseRenderer.instrumentationStatus.contains("dense1000"))
    }

    @MainActor
    func testPublicRunRejectsUnrecognizedFixtureProfile() {
        let arbitrary = PerformanceConfiguration(
            fixtureMarkCount: 999,
            samplesPerGesture: 240,
            warmupCount: 5,
            trialCount: 30,
            pairsPerOrder: 15,
            bootstrapSeed: 48271,
            bootstrapResamples: 10_000,
            memoryWindowSeconds: 600,
            memorySampleIntervalSeconds: 5,
            harnessVersion: PerformanceFixtures.configuration.harnessVersion,
            foundationIdentity: PerformanceFixtures.foundation,
            buildContractVersion: PerformanceFixtures.configuration.buildContractVersion
        )
        XCTAssertNil(PerformanceHarness.fixtureProfile(for: arbitrary))
        XCTAssertThrowsError(try PerformanceHarness.run(
            configuration: arbitrary,
            buildProvenance: PerformanceFixtures.build,
            runProvenance: PerformanceFixtures.run
        ))
    }

    @MainActor
    func testDenseSemanticOracleRejectsWrongPlanEvenWithPlausiblePixels() {
        let snapshot = RendererSemanticSnapshot(
            profile: .dense1000,
            renderPlanIdentity: "dense1000|wrong-plan",
            committedMarkCount: 1_000,
            hasActiveDraft: false,
            positiveMarkOccupancy: Self.denseMinimumPositiveHits,
            positiveMarkColorMatches: Self.denseMinimumPositiveHits,
            negativeRegionOccupied: Array(repeating: false, count: Self.denseNegativeRegionCount),
            occupiedStrata: Array(repeating: true, count: Self.denseStratumCount),
            nonTransparentPixelCount: 10_000,
            occupiedQuadrantCount: 4,
            pixelChecksum: 1,
            boundsWidth: 512,
            boundsHeight: 512
        )

        XCTAssertEqual(OffscreenCanvasRendererAdapter.semanticStatus(snapshot), .failed)
    }

    @MainActor
    func testDenseSemanticOracleRejectsSameHostChecksumInstability() {
        let before = RendererSemanticSnapshot(
            profile: .dense1000,
            renderPlanIdentity: "dense1000|planDigest=cd81b9529b3682d5",
            committedMarkCount: 1_000,
            hasActiveDraft: false,
            positiveMarkOccupancy: Self.denseMinimumPositiveHits,
            positiveMarkColorMatches: Self.denseMinimumPositiveHits,
            negativeRegionOccupied: Array(repeating: false, count: Self.denseNegativeRegionCount),
            occupiedStrata: Array(repeating: true, count: Self.denseStratumCount),
            nonTransparentPixelCount: 10_000,
            occupiedQuadrantCount: 4,
            pixelChecksum: 1,
            boundsWidth: 512,
            boundsHeight: 512
        )
        let after = RendererSemanticSnapshot(
            profile: .dense1000,
            renderPlanIdentity: "dense1000|planDigest=cd81b9529b3682d5",
            committedMarkCount: 1_000,
            hasActiveDraft: false,
            positiveMarkOccupancy: Self.denseMinimumPositiveHits,
            positiveMarkColorMatches: Self.denseMinimumPositiveHits,
            negativeRegionOccupied: Array(repeating: false, count: Self.denseNegativeRegionCount),
            occupiedStrata: Array(repeating: true, count: Self.denseStratumCount),
            nonTransparentPixelCount: 10_001,
            occupiedQuadrantCount: 4,
            pixelChecksum: 2,
            boundsWidth: 512,
            boundsHeight: 512
        )

        XCTAssertEqual(
            OffscreenCanvasRendererAdapter.semanticRasterStatus(before: before, after: after),
            .failed
        )
    }

    @MainActor
    func testDenseSemanticOracleRejectsOmittedLateMarks() {
        var occupancy = Self.denseMinimumPositiveHits
        var colorMatches = Self.denseMinimumPositiveHits
        occupancy[999] = 0
        colorMatches[999] = 0
        let snapshot = RendererSemanticSnapshot(
            profile: .dense1000,
            renderPlanIdentity: "dense1000|planDigest=cd81b9529b3682d5",
            committedMarkCount: 1_000,
            hasActiveDraft: false,
            positiveMarkOccupancy: occupancy,
            positiveMarkColorMatches: colorMatches,
            negativeRegionOccupied: Array(repeating: false, count: Self.denseNegativeRegionCount),
            occupiedStrata: Array(repeating: true, count: Self.denseStratumCount),
            nonTransparentPixelCount: 10_000,
            occupiedQuadrantCount: 4,
            pixelChecksum: 1,
            boundsWidth: 512,
            boundsHeight: 512
        )

        XCTAssertEqual(OffscreenCanvasRendererAdapter.semanticStatus(snapshot), .failed)
    }

    @MainActor
    func testDenseSemanticOracleRejectsOmittedWholeStratum() {
        let snapshot = RendererSemanticSnapshot(
            profile: .dense1000,
            renderPlanIdentity: "dense1000|planDigest=cd81b9529b3682d5",
            committedMarkCount: 1_000,
            hasActiveDraft: false,
            positiveMarkOccupancy: Self.denseMinimumPositiveHits,
            positiveMarkColorMatches: Self.denseMinimumPositiveHits,
            negativeRegionOccupied: Array(repeating: false, count: Self.denseNegativeRegionCount),
            occupiedStrata: Array(repeating: true, count: Self.denseStratumCount).enumerated().map { $0.offset == 15 ? false : $0.element },
            nonTransparentPixelCount: 10_000,
            occupiedQuadrantCount: 4,
            pixelChecksum: 1,
            boundsWidth: 512,
            boundsHeight: 512
        )

        XCTAssertEqual(OffscreenCanvasRendererAdapter.semanticStatus(snapshot), .failed)
    }

    @MainActor
    func testDenseSemanticOracleRejectsLateMarkMissingFromCanonicalBitmap() throws {
        let (view, context, bitmap) = try makeDenseBitmap()
        defer { bitmap.deallocate() }

        context.clear(
            CGRect(
                x: 0.92 * 512,
                y: (1 - 0.93) * 512,
                width: 0.08 * 512,
                height: 0.08 * 512
            )
        )
        let snapshot = OffscreenCanvasRendererAdapter.semanticSnapshot(
            view: view,
            profile: .dense1000,
            bitmap: bitmap,
            width: 512,
            height: 512
        )

        XCTAssertEqual(snapshot.committedMarkCount, 1_000)
        XCTAssertEqual(OffscreenCanvasRendererAdapter.semanticStatus(snapshot), .failed)
    }

    @MainActor
    func testDenseSemanticOracleRejectsWholeStratumMissingFromCanonicalBitmap() throws {
        let (view, context, bitmap) = try makeDenseBitmap()
        defer { bitmap.deallocate() }

        context.clear(
            CGRect(
                x: 0.75 * 512,
                y: 0,
                width: 0.25 * 512,
                height: 0.25 * 512
            )
        )
        let snapshot = OffscreenCanvasRendererAdapter.semanticSnapshot(
            view: view,
            profile: .dense1000,
            bitmap: bitmap,
            width: 512,
            height: 512
        )

        XCTAssertEqual(snapshot.committedMarkCount, 1_000)
        XCTAssertEqual(OffscreenCanvasRendererAdapter.semanticStatus(snapshot), .failed)
    }

    @MainActor
    private func makeDenseBitmap() throws -> (CanvasView, CGContext, UnsafeMutableRawPointer) {
        _ = NSApplication.shared
        let display = DisplayUUID(rawValue: "performance-dense-test-display")
        let frame = NSRect(x: 0, y: 0, width: 512, height: 512)
        let session = OffscreenCanvasRendererAdapter.fixtureSession(
            display: display,
            profile: .dense1000
        )
        let view = CanvasView(frame: frame, display: display, session: session, tool: .select)
        let bitmapByteCount = 512 * 512 * 4
        let bitmap = UnsafeMutableRawPointer.allocate(
            byteCount: bitmapByteCount,
            alignment: MemoryLayout<UInt8>.alignment
        )
        bitmap.initializeMemory(as: UInt8.self, repeating: 0, count: bitmapByteCount)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            bitmap.deallocate()
            throw NSError(domain: "PerformanceHarnessTests", code: 1)
        }
        guard let context = CGContext(
            data: bitmap,
            width: 512,
            height: 512,
            bitsPerComponent: 8,
            bytesPerRow: 512 * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            bitmap.deallocate()
            throw NSError(domain: "PerformanceHarnessTests", code: 2)
        }
        context.clear(frame)
        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        view.draw(frame)
        NSGraphicsContext.restoreGraphicsState()
        return (view, context, bitmap)
    }
}

@MainActor
private struct FixtureModelAdapter: ModelInstrumentationAdapter {
    func measureModel(configuration: PerformanceConfiguration) -> ModelMeasurement { PerformanceFixtures.model }
}

@MainActor
private struct FixtureRendererAdapter: RendererInstrumentationAdapter, CompositorInstrumentationAdapter, CombinedFrameInstrumentationAdapter {
    let measurement: FrameMeasurement

    func measureRenderer(configuration: PerformanceConfiguration) -> FrameMeasurement { measurement }
    func measureCompositor(configuration: PerformanceConfiguration) -> FrameMeasurement { measurement }
    func measureCombinedFrame(configuration: PerformanceConfiguration) -> FrameMeasurement { measurement }
}

@MainActor
private struct FixtureLaunchAdapter: LaunchInstrumentationAdapter {
    let measurement: LaunchMeasurement

    func measureLaunch(configuration: PerformanceConfiguration) -> LaunchMeasurement { measurement }
}

@MainActor
private struct FixtureAllocationAdapter: AllocationInstrumentationAdapter {
    let measurement: AllocationMeasurement

    func measureAllocations(configuration: PerformanceConfiguration) -> AllocationMeasurement { measurement }
}

@MainActor
private struct FixtureRedrawLayoutAdapter: RedrawLayoutInstrumentationAdapter {
    let measurement: RedrawLayoutMeasurement

    func measureRedrawLayout(configuration: PerformanceConfiguration) -> RedrawLayoutMeasurement { measurement }
}

@MainActor
private struct FixtureResponsivenessAdapter: ResponsivenessInstrumentationAdapter {
    let measurement: ResponsivenessMeasurement

    func measureResponsiveness(configuration: PerformanceConfiguration) -> ResponsivenessMeasurement { measurement }
}

@MainActor
private struct FixtureInputToVisibleAdapter: InputToVisibleInstrumentationAdapter {
    let measurement: InputToVisibleMeasurement

    func measureInputToVisible(configuration: PerformanceConfiguration) -> InputToVisibleMeasurement { measurement }
}

@MainActor
private struct FixtureMemoryAdapter: MemoryInstrumentationAdapter {
    let measurement: MemoryMeasurement

    func measureMemory(configuration: PerformanceConfiguration) -> MemoryMeasurement { measurement }
}

@MainActor
private struct FixtureResilienceAdapter: ResilienceInstrumentationAdapter {
    let measurement: ResilienceMeasurement

    func measureResilience(configuration: PerformanceConfiguration) -> ResilienceMeasurement { measurement }
}
