import Foundation
import XCTest
@testable import PointerAppKit

final class PerformanceHarnessTests: XCTestCase {
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
        XCTAssertEqual(decoded.compositor.status, .measured)
        XCTAssertEqual(decoded.combinedFrame.status, .measured)
        XCTAssertEqual(decoded.launch.coldMilliseconds, [120, 125, 123])
        XCTAssertEqual(decoded.allocations.bytesPerGesture, [1024, 1152, 1088])
        XCTAssertEqual(decoded.redrawLayout.layoutPasses, [1, 1, 1])
        XCTAssertEqual(decoded.responsiveness.stallCount, 0)
        XCTAssertEqual(decoded.inputToVisible.missedSampleCount, 0)
        XCTAssertEqual(decoded.memory.samples.map(\.phase), [.running, .running, .stopping, .stopped, .restarted])
        XCTAssertEqual(decoded.memory.aggregates.count, 1)
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

    func testIdentityRequiresOneLowercaseImmutableIdentityAndCompatibleTreeStatus() throws {
        let both = MeasurementIdentity(sourceCommitSHA: PerformanceFixtures.commit, contentManifestSHA256: PerformanceFixtures.sourceManifest, hostModel: "Mac", macOSVersion: "14", xcodeVersion: "16", developerDirectory: "/Applications/Xcode.app/Contents/Developer", powerState: "ac", displayState: "one", buildConfiguration: "release")
        XCTAssertThrowsError(try PerformanceFixtures.report(identity: both).validateStructure())

        let neither = MeasurementIdentity(sourceCommitSHA: nil, contentManifestSHA256: nil, hostModel: "Mac", macOSVersion: "14", xcodeVersion: "16", developerDirectory: "/Applications/Xcode.app/Contents/Developer", powerState: "ac", displayState: "one", buildConfiguration: "release")
        XCTAssertThrowsError(try PerformanceFixtures.report(identity: neither).validateStructure())

        let uppercase = MeasurementIdentity(sourceCommitSHA: String(repeating: "A", count: 40), contentManifestSHA256: nil, hostModel: "Mac", macOSVersion: "14", xcodeVersion: "16", developerDirectory: "/Applications/Xcode.app/Contents/Developer", powerState: "ac", displayState: "one", buildConfiguration: "release")
        XCTAssertThrowsError(try PerformanceFixtures.report(identity: uppercase).validateStructure())

        let dirtyIdentity = MeasurementIdentity(sourceCommitSHA: nil, contentManifestSHA256: PerformanceFixtures.sourceManifest, hostModel: "Mac", macOSVersion: "14", xcodeVersion: "16", developerDirectory: "/Applications/Xcode.app/Contents/Developer", powerState: "ac", displayState: "one", buildConfiguration: "release")
        let dirtyBuild = BuildProvenance(sourceTreeStatus: .dirty, sourceIdentity: SourceIdentity(kind: .contentManifestSHA256, value: PerformanceFixtures.sourceManifest), sourceManifestSHA256: PerformanceFixtures.sourceManifest, executableSHA256: PerformanceFixtures.executable, bundleManifestSHA256: PerformanceFixtures.bundle, recordedAtUTC: PerformanceFixtures.recordedAtUTC, foundation: PerformanceFixtures.foundation, harnessVersion: PerformanceFixtures.configuration.harnessVersion, buildContractVersion: PerformanceFixtures.configuration.buildContractVersion, acceptedFoundationArtifactSHA256: nil)
        let dirtyRun = PerformanceRunProvenance(variant: "candidate", outputRoot: "build/candidate", sourceRef: PerformanceFixtures.sourceManifest, build: dirtyBuild, host: PerformanceFixtures.host, recordedAtUTC: PerformanceFixtures.recordedAtUTC, configuration: PerformanceFixtures.configuration, foundationProvenancePath: PerformanceFixtures.run.foundationProvenancePath, foundation: PerformanceFixtures.foundation, harnessVersion: PerformanceFixtures.configuration.harnessVersion, buildContractVersion: PerformanceFixtures.configuration.buildContractVersion)
        let dirtyReport = PerformanceFixtures.report(identity: dirtyIdentity, build: dirtyBuild, run: dirtyRun)
        XCTAssertNoThrow(try dirtyReport.validateStructure())

        let dirtyBuildWithMismatchedManifest = BuildProvenance(sourceTreeStatus: .dirty, sourceIdentity: SourceIdentity(kind: .contentManifestSHA256, value: PerformanceFixtures.sourceManifest), sourceManifestSHA256: PerformanceFixtures.bundle, executableSHA256: PerformanceFixtures.executable, bundleManifestSHA256: PerformanceFixtures.bundle, recordedAtUTC: PerformanceFixtures.recordedAtUTC, foundation: PerformanceFixtures.foundation, harnessVersion: PerformanceFixtures.configuration.harnessVersion, buildContractVersion: PerformanceFixtures.configuration.buildContractVersion, acceptedFoundationArtifactSHA256: nil)
        let dirtyRunWithMismatchedManifest = PerformanceRunProvenance(variant: "candidate", outputRoot: "build/candidate", sourceRef: PerformanceFixtures.sourceManifest, build: dirtyBuildWithMismatchedManifest, host: PerformanceFixtures.host, recordedAtUTC: PerformanceFixtures.recordedAtUTC, configuration: PerformanceFixtures.configuration, foundationProvenancePath: PerformanceFixtures.run.foundationProvenancePath, foundation: PerformanceFixtures.foundation, harnessVersion: PerformanceFixtures.configuration.harnessVersion, buildContractVersion: PerformanceFixtures.configuration.buildContractVersion)
        XCTAssertThrowsError(try PerformanceFixtures.report(identity: dirtyIdentity, build: dirtyBuildWithMismatchedManifest, run: dirtyRunWithMismatchedManifest).validateStructure())

        let dirtyWithCommit = PerformanceFixtures.report(build: dirtyBuild, run: dirtyRun)
        XCTAssertThrowsError(try dirtyWithCommit.validateStructure())
    }

    func testProvenanceIdentityAndVersionMismatchesAreRejected() throws {
        var mismatchedBuild = PerformanceFixtures.build
        mismatchedBuild = BuildProvenance(sourceTreeStatus: .clean, sourceIdentity: SourceIdentity(kind: .sourceCommitSHA, value: String(repeating: "e", count: 40)), sourceManifestSHA256: mismatchedBuild.sourceManifestSHA256, executableSHA256: mismatchedBuild.executableSHA256, bundleManifestSHA256: mismatchedBuild.bundleManifestSHA256, recordedAtUTC: mismatchedBuild.recordedAtUTC, foundation: mismatchedBuild.foundation, harnessVersion: mismatchedBuild.harnessVersion, buildContractVersion: mismatchedBuild.buildContractVersion, acceptedFoundationArtifactSHA256: nil)
        XCTAssertThrowsError(try PerformanceFixtures.report(build: mismatchedBuild).validateStructure())

        let mismatchedRun = PerformanceRunProvenance(variant: PerformanceFixtures.run.variant, outputRoot: PerformanceFixtures.run.outputRoot, sourceRef: PerformanceFixtures.run.sourceRef, build: PerformanceFixtures.run.build, host: PerformanceFixtures.run.host, recordedAtUTC: PerformanceFixtures.run.recordedAtUTC, configuration: PerformanceFixtures.run.configuration, foundationProvenancePath: PerformanceFixtures.run.foundationProvenancePath, foundation: FoundationIdentity(identity: "other", version: "v1"), harnessVersion: PerformanceFixtures.run.harnessVersion, buildContractVersion: PerformanceFixtures.run.buildContractVersion)
        XCTAssertThrowsError(try PerformanceFixtures.report(run: mismatchedRun).validateStructure())

        let mismatchedConfiguration = PerformanceConfiguration(fixtureMarkCount: 12, samplesPerGesture: 240, warmupCount: 5, trialCount: 30, pairsPerOrder: 14, bootstrapSeed: 48271, bootstrapResamples: 10_000, memoryWindowSeconds: 600, memorySampleIntervalSeconds: 5, harnessVersion: "other-harness", foundationIdentity: PerformanceFixtures.foundation, buildContractVersion: PerformanceFixtures.configuration.buildContractVersion)
        let run = PerformanceRunProvenance(variant: "candidate", outputRoot: "build/candidate", sourceRef: PerformanceFixtures.commit, build: PerformanceFixtures.build, host: PerformanceFixtures.host, recordedAtUTC: PerformanceFixtures.recordedAtUTC, configuration: mismatchedConfiguration, foundationProvenancePath: PerformanceFixtures.run.foundationProvenancePath, foundation: PerformanceFixtures.foundation, harnessVersion: mismatchedConfiguration.harnessVersion, buildContractVersion: mismatchedConfiguration.buildContractVersion)
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

        let coherent = MemoryMeasurement(status: .measured, windowSeconds: 600, sampleIntervalSeconds: 5, samples: samples, aggregates: PerformanceFixtures.memory.aggregates, peakRSSBytes: PerformanceFixtures.memory.peakRSSBytes, finalWindowDeltaBytes: PerformanceFixtures.memory.finalWindowDeltaBytes, finalWindowDeltaPercent: PerformanceFixtures.memory.finalWindowDeltaPercent, matchedBaselineSeries: PerformanceFixtures.memory.matchedBaselineSeries, matchedBaselineValues: PerformanceFixtures.memory.matchedBaselineValues, peakLiveResourceCounts: highResources, endLiveResourceCounts: PerformanceFixtures.resources)
        XCTAssertNoThrow(try PerformanceFixtures.report(memory: coherent).validateStructure())
    }

    func testFailedAndUnmeasuredReportsRemainStructurallyValidButCannotComplete() throws {
        let failed = PerformanceFixtures.withStatuses(PerformanceFixtures.report(), status: .failed)
        XCTAssertNoThrow(try failed.validateStructure())
        XCTAssertThrowsError(try failed.validateCompletion())

        let unmeasured = PerformanceFixtures.withStatuses(PerformanceFixtures.report(), status: .unmeasured)
        XCTAssertNoThrow(try unmeasured.validateStructure())
        XCTAssertThrowsError(try unmeasured.validateCompletion())
    }

    func testValidMeasuredReportPassesCompletionValidation() throws {
        let report = PerformanceFixtures.report()
        XCTAssertNoThrow(try report.validateStructure())
        XCTAssertNoThrow(try report.validateCompletion())
    }

    func testNonstandardConfigurationCanBeDiagnosticButCannotComplete() throws {
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
            buildContractVersion: nonstandardConfiguration.buildContractVersion
        )
        let report = PerformanceFixtures.report(run: run)
        XCTAssertNoThrow(try report.validateStructure())
        XCTAssertThrowsError(try report.validateCompletion())
    }
}
