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
        XCTAssertEqual(decoded.launch.coldMilliseconds.count, PerformanceFixtures.configuration.trialCount)
        XCTAssertEqual(decoded.allocations.bytesPerGesture.count, PerformanceFixtures.configuration.trialCount)
        XCTAssertEqual(decoded.redrawLayout.layoutPasses.count, PerformanceFixtures.configuration.trialCount)
        XCTAssertEqual(decoded.responsiveness.stallCount, 0)
        XCTAssertEqual(decoded.inputToVisible.missedSampleCount, 0)
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
            buildContractVersion: nonstandardConfiguration.buildContractVersion,
            acceptedFoundationArtifactSHA256: PerformanceFixtures.run.acceptedFoundationArtifactSHA256
        )
        let report = PerformanceFixtures.report(run: run)
        XCTAssertNoThrow(try report.validateStructure())
        XCTAssertThrowsError(try report.validateCompletion())
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
}
