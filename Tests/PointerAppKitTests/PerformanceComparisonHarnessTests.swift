import Foundation
import XCTest
@testable import PointerAppKit

@MainActor
final class PerformanceComparisonHarnessTests: XCTestCase {
    func testComparisonRoundTripsEntireReportAndValidatesCompletion() throws {
        let report = PerformanceFixtures.comparison()
        try report.validateStructure()
        try report.validateCompletion()

        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(PerformanceComparisonReport.self, from: data)

        XCTAssertEqual(decoded, report)
        XCTAssertEqual(decoded.reportKind, .comparison)
        XCTAssertEqual(decoded.metrics.count, PerformanceMetricID.allCases.count)
        XCTAssertEqual(decoded.pairEligibility, PerformanceFixtures.eligibility)
        XCTAssertEqual(decoded.baselineFixture, PerformanceFixtures.fixture)
        XCTAssertEqual(decoded.candidateFixture, PerformanceFixtures.fixture)
        XCTAssertEqual(decoded.baselineMeasurementIdentity, PerformanceFixtures.baselineIdentity)
        XCTAssertEqual(decoded.candidateMeasurementIdentity, PerformanceFixtures.identity)
        XCTAssertEqual(decoded.baselineRunProvenance, PerformanceFixtures.baselineRun)
        XCTAssertEqual(decoded.candidateRunProvenance, PerformanceFixtures.run)
    }

    func testComparisonRejectsWrongOrMissingKind() throws {
        let wrongKind = PerformanceFixtures.comparison(reportKind: .measurement)
        XCTAssertThrowsError(try wrongKind.validateStructure())

        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(PerformanceFixtures.comparison())) as! [String: Any]
        object.removeValue(forKey: "reportKind")
        let missingKindData = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try JSONDecoder().decode(PerformanceComparisonReport.self, from: missingKindData))
    }

    func testComparisonRejectsDuplicateOrMissingMetricIDs() throws {
        var duplicate = PerformanceFixtures.comparison().metrics
        duplicate[1] = duplicate[0]
        XCTAssertThrowsError(try PerformanceFixtures.comparison(metrics: duplicate).validateStructure())

        var missing = PerformanceFixtures.comparison().metrics
        missing.removeLast()
        XCTAssertThrowsError(try PerformanceFixtures.comparison(metrics: missing).validateStructure())
    }

    func testComparisonRejectsHostFixtureVersionAndProvenanceMismatches() throws {
        let mismatchedHost = HostIdentity(machineIdentifier: "other-machine", processArchitecture: "arm64", connectedDisplayUUIDs: ["fixture-display"])
        let hostBuild = PerformanceFixtures.baselineBuild
        let hostRun = PerformanceRunProvenance(variant: "baseline", outputRoot: "build/baseline", sourceRef: PerformanceFixtures.baselineCommit, build: hostBuild, host: mismatchedHost, recordedAtUTC: PerformanceFixtures.recordedAtUTC, configuration: PerformanceFixtures.configuration, foundationProvenancePath: PerformanceFixtures.baselineRun.foundationProvenancePath, foundation: PerformanceFixtures.foundation, harnessVersion: PerformanceFixtures.configuration.harnessVersion, buildContractVersion: PerformanceFixtures.configuration.buildContractVersion, acceptedFoundationArtifactSHA256: PerformanceFixtures.foundationArtifact)
        XCTAssertThrowsError(try PerformanceFixtures.comparison(baselineRun: hostRun).validateStructure())

        let mismatchedConfig = PerformanceConfiguration(fixtureMarkCount: 13, samplesPerGesture: 240, warmupCount: 5, trialCount: 30, pairsPerOrder: 15, bootstrapSeed: 48271, bootstrapResamples: 10_000, memoryWindowSeconds: 600, memorySampleIntervalSeconds: 5, harnessVersion: PerformanceFixtures.configuration.harnessVersion, foundationIdentity: PerformanceFixtures.foundation, buildContractVersion: PerformanceFixtures.configuration.buildContractVersion)
        let configRun = PerformanceRunProvenance(variant: "baseline", outputRoot: "build/baseline", sourceRef: PerformanceFixtures.baselineCommit, build: hostBuild, host: PerformanceFixtures.host, recordedAtUTC: PerformanceFixtures.recordedAtUTC, configuration: mismatchedConfig, foundationProvenancePath: PerformanceFixtures.baselineRun.foundationProvenancePath, foundation: PerformanceFixtures.foundation, harnessVersion: PerformanceFixtures.configuration.harnessVersion, buildContractVersion: PerformanceFixtures.configuration.buildContractVersion, acceptedFoundationArtifactSHA256: PerformanceFixtures.foundationArtifact)
        XCTAssertThrowsError(try PerformanceFixtures.comparison(baselineRun: configRun).validateStructure())

        let mismatchedEligibility = PerformancePairEligibility(baselineRoot: "build/other", candidateRoot: PerformanceFixtures.eligibility.candidateRoot, baselineCommitSHA: PerformanceFixtures.eligibility.baselineCommitSHA, candidateCommitSHA: PerformanceFixtures.eligibility.candidateCommitSHA, foundationProvenance: PerformanceFixtures.eligibility.foundationProvenance)
        XCTAssertThrowsError(try PerformanceComparisonHarness.preflight(baseline: PerformanceFixtures.baseline, candidate: PerformanceFixtures.candidate, configuration: PerformanceFixtures.configuration, eligibility: mismatchedEligibility))

        let swappedBaseline = PerformanceRunProvenance(variant: "candidate", outputRoot: PerformanceFixtures.baselineRun.outputRoot, sourceRef: PerformanceFixtures.baselineRun.sourceRef, build: PerformanceFixtures.baselineRun.build, host: PerformanceFixtures.baselineRun.host, recordedAtUTC: PerformanceFixtures.baselineRun.recordedAtUTC, configuration: PerformanceFixtures.baselineRun.configuration, foundationProvenancePath: PerformanceFixtures.baselineRun.foundationProvenancePath, foundation: PerformanceFixtures.baselineRun.foundation, harnessVersion: PerformanceFixtures.baselineRun.harnessVersion, buildContractVersion: PerformanceFixtures.baselineRun.buildContractVersion, acceptedFoundationArtifactSHA256: PerformanceFixtures.baselineRun.acceptedFoundationArtifactSHA256)
        XCTAssertThrowsError(try PerformanceFixtures.comparison(baselineRun: swappedBaseline).validateStructure())

        let swappedCandidate = PerformanceRunProvenance(variant: "baseline", outputRoot: PerformanceFixtures.run.outputRoot, sourceRef: PerformanceFixtures.run.sourceRef, build: PerformanceFixtures.run.build, host: PerformanceFixtures.run.host, recordedAtUTC: PerformanceFixtures.run.recordedAtUTC, configuration: PerformanceFixtures.run.configuration, foundationProvenancePath: PerformanceFixtures.run.foundationProvenancePath, foundation: PerformanceFixtures.run.foundation, harnessVersion: PerformanceFixtures.run.harnessVersion, buildContractVersion: PerformanceFixtures.run.buildContractVersion, acceptedFoundationArtifactSHA256: PerformanceFixtures.run.acceptedFoundationArtifactSHA256)
        XCTAssertThrowsError(try PerformanceFixtures.comparison(candidateRun: swappedCandidate).validateStructure())
    }

    func testPreflightRejectsContentManifestLineageBeforeWriting() throws {
        let dirtyIdentity = MeasurementIdentity(sourceCommitSHA: nil, contentManifestSHA256: PerformanceFixtures.sourceManifest, hostModel: PerformanceFixtures.identity.hostModel, macOSVersion: PerformanceFixtures.identity.macOSVersion, xcodeVersion: PerformanceFixtures.identity.xcodeVersion, developerDirectory: PerformanceFixtures.identity.developerDirectory, powerState: PerformanceFixtures.identity.powerState, displayState: PerformanceFixtures.identity.displayState, buildConfiguration: "release")
        let dirtyBuild = BuildProvenance(sourceTreeStatus: .dirty, sourceIdentity: SourceIdentity(kind: .contentManifestSHA256, value: PerformanceFixtures.sourceManifest), sourceManifestSHA256: PerformanceFixtures.sourceManifest, executableSHA256: PerformanceFixtures.executable, bundleManifestSHA256: PerformanceFixtures.bundle, buildConfiguration: "release", recordedAtUTC: PerformanceFixtures.recordedAtUTC, foundation: PerformanceFixtures.foundation, harnessVersion: PerformanceFixtures.configuration.harnessVersion, buildContractVersion: PerformanceFixtures.configuration.buildContractVersion, acceptedFoundationArtifactSHA256: PerformanceFixtures.foundationArtifact)
        let dirtyRun = PerformanceRunProvenance(variant: "candidate", outputRoot: "build/candidate", sourceRef: PerformanceFixtures.sourceManifest, build: dirtyBuild, host: PerformanceFixtures.host, recordedAtUTC: PerformanceFixtures.recordedAtUTC, configuration: PerformanceFixtures.configuration, foundationProvenancePath: PerformanceFixtures.run.foundationProvenancePath, foundation: PerformanceFixtures.foundation, harnessVersion: PerformanceFixtures.configuration.harnessVersion, buildContractVersion: PerformanceFixtures.configuration.buildContractVersion, acceptedFoundationArtifactSHA256: PerformanceFixtures.foundationArtifact)
        let dirty = PerformanceFixtures.report(identity: dirtyIdentity, build: dirtyBuild, run: dirtyRun)

        XCTAssertThrowsError(try PerformanceComparisonHarness.preflight(baseline: dirty, candidate: PerformanceFixtures.candidate, configuration: PerformanceFixtures.configuration, eligibility: PerformanceFixtures.eligibility))
    }

    func testPreflightRejectsFailedAndUnmeasuredInputs() throws {
        for status in [MeasurementStatus.failed, .unmeasured] {
            let report = PerformanceFixtures.withStatuses(PerformanceFixtures.baseline, status: status)
            XCTAssertThrowsError(try PerformanceComparisonHarness.preflight(baseline: report, candidate: PerformanceFixtures.candidate, configuration: PerformanceFixtures.configuration, eligibility: PerformanceFixtures.eligibility))
        }
    }

    func testComparisonRejectsInvalidArraysRatiosAndBootstrap() throws {
        var shortSamples = PerformanceFixtures.comparison().metrics
        shortSamples[0] = MetricComparison(metricID: shortSamples[0].metricID, evidenceClass: shortSamples[0].evidenceClass, unit: shortSamples[0].unit, baselineID: shortSamples[0].baselineID, candidateID: shortSamples[0].candidateID, baselineSamples: [1], candidateSamples: [], ratios: [], deltas: [], budgetLimit: shortSamples[0].budgetLimit, bootstrapInterval: shortSamples[0].bootstrapInterval, manualEvidence: nil, disposition: .acceptedNoRegression)
        XCTAssertThrowsError(try PerformanceFixtures.comparison(metrics: shortSamples).validateStructure())

        var wrongRatio = PerformanceFixtures.comparison().metrics
        wrongRatio[0] = MetricComparison(metricID: wrongRatio[0].metricID, evidenceClass: wrongRatio[0].evidenceClass, unit: wrongRatio[0].unit, baselineID: wrongRatio[0].baselineID, candidateID: wrongRatio[0].candidateID, baselineSamples: wrongRatio[0].baselineSamples, candidateSamples: wrongRatio[0].candidateSamples, ratios: Array(repeating: 1, count: 30), deltas: wrongRatio[0].deltas, budgetLimit: wrongRatio[0].budgetLimit, bootstrapInterval: wrongRatio[0].bootstrapInterval, manualEvidence: nil, disposition: .acceptedNoRegression)
        XCTAssertThrowsError(try PerformanceFixtures.comparison(metrics: wrongRatio).validateStructure())

        var badBootstrap = PerformanceFixtures.comparison().metrics
        badBootstrap[0] = MetricComparison(metricID: badBootstrap[0].metricID, evidenceClass: badBootstrap[0].evidenceClass, unit: badBootstrap[0].unit, baselineID: badBootstrap[0].baselineID, candidateID: badBootstrap[0].candidateID, baselineSamples: badBootstrap[0].baselineSamples, candidateSamples: badBootstrap[0].candidateSamples, ratios: badBootstrap[0].ratios, deltas: badBootstrap[0].deltas, budgetLimit: badBootstrap[0].budgetLimit, bootstrapInterval: BootstrapInterval(lowerDelta: 2, upperDelta: 1, seed: 48271, resampleCount: 10_000), manualEvidence: nil, disposition: .acceptedNoRegression)
        XCTAssertThrowsError(try PerformanceFixtures.comparison(metrics: badBootstrap).validateStructure())
    }

    func testComparisonRequiresThirtyPairedSamplesAndDerivedArrays() throws {
        var emptyDerived = PerformanceFixtures.comparison().metrics
        let value = emptyDerived[0]
        emptyDerived[0] = MetricComparison(metricID: value.metricID, evidenceClass: value.evidenceClass, unit: value.unit, baselineID: value.baselineID, candidateID: value.candidateID, baselineSamples: value.baselineSamples, candidateSamples: value.candidateSamples, ratios: [], deltas: [], budgetLimit: value.budgetLimit, bootstrapInterval: value.bootstrapInterval, manualEvidence: nil, disposition: value.disposition)
        XCTAssertThrowsError(try PerformanceFixtures.comparison(metrics: emptyDerived).validateStructure())

        var shortDerived = PerformanceFixtures.comparison().metrics
        shortDerived[0] = MetricComparison(metricID: value.metricID, evidenceClass: value.evidenceClass, unit: value.unit, baselineID: value.baselineID, candidateID: value.candidateID, baselineSamples: value.baselineSamples, candidateSamples: value.candidateSamples, ratios: Array(value.ratios.dropLast()), deltas: Array(value.deltas.dropLast()), budgetLimit: value.budgetLimit, bootstrapInterval: value.bootstrapInterval, manualEvidence: nil, disposition: value.disposition)
        XCTAssertThrowsError(try PerformanceFixtures.comparison(metrics: shortDerived).validateStructure())
    }

    func testComparisonRejectsNonPositiveMetricSamples() throws {
        var zeroBaseline = PerformanceFixtures.comparison().metrics
        let value = zeroBaseline[0]
        zeroBaseline[0] = MetricComparison(metricID: value.metricID, evidenceClass: value.evidenceClass, unit: value.unit, baselineID: value.baselineID, candidateID: value.candidateID, baselineSamples: Array(repeating: 0, count: 30), candidateSamples: value.candidateSamples, ratios: value.ratios, deltas: value.deltas, budgetLimit: value.budgetLimit, bootstrapInterval: value.bootstrapInterval, manualEvidence: nil, disposition: value.disposition)
        XCTAssertThrowsError(try PerformanceFixtures.comparison(metrics: zeroBaseline).validateStructure())

        var negativeCandidate = PerformanceFixtures.comparison().metrics
        negativeCandidate[0] = MetricComparison(metricID: value.metricID, evidenceClass: value.evidenceClass, unit: value.unit, baselineID: value.baselineID, candidateID: value.candidateID, baselineSamples: value.baselineSamples, candidateSamples: Array(repeating: -1, count: 30), ratios: value.ratios, deltas: value.deltas, budgetLimit: value.budgetLimit, bootstrapInterval: value.bootstrapInterval, manualEvidence: nil, disposition: value.disposition)
        XCTAssertThrowsError(try PerformanceFixtures.comparison(metrics: negativeCandidate).validateStructure())
    }

    func testComparisonCompletionRejectsSelfConsistentRatioRegressionAndBudgetBreach() throws {
        let value = PerformanceFixtures.comparison().metrics[0]
        let ratioRegression = (0..<30).map { _ in 1.2 }
        let ratioSamples = (0..<30).map { _ in 120.0 }
        let ratioMetric = MetricComparison(metricID: value.metricID, evidenceClass: value.evidenceClass, unit: value.unit, baselineID: value.baselineID, candidateID: value.candidateID, baselineSamples: Array(repeating: 100, count: 30), candidateSamples: ratioSamples, ratios: ratioRegression, deltas: Array(repeating: 20, count: 30), budgetLimit: nil, bootstrapInterval: BootstrapInterval(lowerDelta: 20, upperDelta: 20, seed: 48271, resampleCount: 10_000), manualEvidence: nil, disposition: .acceptedNoRegression)
        var ratioMetrics = PerformanceFixtures.comparison().metrics
        ratioMetrics[0] = ratioMetric
        let ratioReport = PerformanceFixtures.comparison(metrics: ratioMetrics)
        XCTAssertNoThrow(try ratioReport.validateStructure())
        XCTAssertThrowsError(try ratioReport.validateCompletion())

        let budgetValue = PerformanceFixtures.comparison().metrics.first { $0.metricID == .combinedFrame }!
        let budgetMetric = MetricComparison(metricID: budgetValue.metricID, evidenceClass: budgetValue.evidenceClass, unit: budgetValue.unit, baselineID: budgetValue.baselineID, candidateID: budgetValue.candidateID, baselineSamples: Array(repeating: 10, count: 30), candidateSamples: Array(repeating: 17, count: 30), ratios: Array(repeating: 1.7, count: 30), deltas: Array(repeating: 7, count: 30), budgetLimit: 16.7, bootstrapInterval: BootstrapInterval(lowerDelta: 7, upperDelta: 7, seed: 48271, resampleCount: 10_000), manualEvidence: nil, disposition: .acceptedNoRegression)
        var budgetMetrics = PerformanceFixtures.comparison().metrics
        budgetMetrics[budgetMetrics.firstIndex { $0.metricID == .combinedFrame }!] = budgetMetric
        let budgetReport = PerformanceFixtures.comparison(metrics: budgetMetrics)
        XCTAssertNoThrow(try budgetReport.validateStructure())
        XCTAssertThrowsError(try budgetReport.validateCompletion())
    }

    func testComparisonRequiresCanonicalUnitsAndNonSpoofableBudgets() throws {
        XCTAssertEqual(PerformanceMetricID.redrawLayout.canonicalUnit, .milliseconds)
        let metrics = PerformanceFixtures.comparison().metrics
        let combined = metrics.first { $0.metricID == .combinedFrame }!
        let wrongUnit = MetricComparison(metricID: combined.metricID, evidenceClass: combined.evidenceClass, unit: .bytes, baselineID: combined.baselineID, candidateID: combined.candidateID, baselineSamples: combined.baselineSamples, candidateSamples: combined.candidateSamples, ratios: combined.ratios, deltas: combined.deltas, budgetLimit: 16.7, bootstrapInterval: combined.bootstrapInterval, manualEvidence: nil, disposition: combined.disposition)
        var wrongUnitMetrics = metrics
        wrongUnitMetrics[wrongUnitMetrics.firstIndex { $0.metricID == .combinedFrame }!] = wrongUnit
        XCTAssertThrowsError(try PerformanceFixtures.comparison(metrics: wrongUnitMetrics).validateStructure())

        let missingBudget = MetricComparison(metricID: combined.metricID, evidenceClass: combined.evidenceClass, unit: combined.unit, baselineID: combined.baselineID, candidateID: combined.candidateID, baselineSamples: combined.baselineSamples, candidateSamples: combined.candidateSamples, ratios: combined.ratios, deltas: combined.deltas, budgetLimit: nil, bootstrapInterval: combined.bootstrapInterval, manualEvidence: nil, disposition: combined.disposition)
        var missingBudgetMetrics = metrics
        missingBudgetMetrics[missingBudgetMetrics.firstIndex { $0.metricID == .combinedFrame }!] = missingBudget
        XCTAssertThrowsError(try PerformanceFixtures.comparison(metrics: missingBudgetMetrics).validateStructure())

        let spoofedBudget = MetricComparison(metricID: combined.metricID, evidenceClass: combined.evidenceClass, unit: combined.unit, baselineID: combined.baselineID, candidateID: combined.candidateID, baselineSamples: combined.baselineSamples, candidateSamples: combined.candidateSamples, ratios: combined.ratios, deltas: combined.deltas, budgetLimit: 1e300, bootstrapInterval: combined.bootstrapInterval, manualEvidence: nil, disposition: combined.disposition)
        var spoofedBudgetMetrics = metrics
        spoofedBudgetMetrics[spoofedBudgetMetrics.firstIndex { $0.metricID == .combinedFrame }!] = spoofedBudget
        XCTAssertThrowsError(try PerformanceFixtures.comparison(metrics: spoofedBudgetMetrics).validateStructure())

        let memory = metrics.first { $0.metricID == .memoryRSS }!
        let unexpectedBudget = MetricComparison(metricID: memory.metricID, evidenceClass: memory.evidenceClass, unit: memory.unit, baselineID: memory.baselineID, candidateID: memory.candidateID, baselineSamples: memory.baselineSamples, candidateSamples: memory.candidateSamples, ratios: memory.ratios, deltas: memory.deltas, budgetLimit: 1e12, bootstrapInterval: memory.bootstrapInterval, manualEvidence: nil, disposition: memory.disposition)
        var unexpectedBudgetMetrics = metrics
        unexpectedBudgetMetrics[unexpectedBudgetMetrics.firstIndex { $0.metricID == .memoryRSS }!] = unexpectedBudget
        XCTAssertThrowsError(try PerformanceFixtures.comparison(metrics: unexpectedBudgetMetrics).validateStructure())

        XCTAssertNoThrow(try PerformanceFixtures.comparison().validateCompletion())
    }

    func testComparisonCompletionRejectsResponsivenessAndInputToVisibleBudgetBreaches() throws {
        for metricID in [PerformanceMetricID.responsiveness, .inputToVisible] {
            let value = PerformanceFixtures.comparison().metrics.first { $0.metricID == metricID }!
            let breach = MetricComparison(metricID: value.metricID, evidenceClass: value.evidenceClass, unit: value.unit, baselineID: value.baselineID, candidateID: value.candidateID, baselineSamples: Array(repeating: 100, count: 30), candidateSamples: Array(repeating: 101, count: 30), ratios: Array(repeating: 1.01, count: 30), deltas: Array(repeating: 1, count: 30), budgetLimit: 100, bootstrapInterval: BootstrapInterval(lowerDelta: 1, upperDelta: 1, seed: 48271, resampleCount: 10_000), manualEvidence: value.manualEvidence, disposition: .acceptedNoRegression)
            var metrics = PerformanceFixtures.comparison().metrics
            metrics[metrics.firstIndex { $0.metricID == metricID }!] = breach
            let report = PerformanceFixtures.comparison(metrics: metrics)
            XCTAssertNoThrow(try report.validateStructure())
            XCTAssertThrowsError(try report.validateCompletion())
        }
    }

    func testComparisonRequiresMatchingPersistedFixtures() throws {
        let mismatched = FixtureIdentity(identifier: "other-fixture", markCount: PerformanceFixtures.fixture.markCount, continuationSamples: PerformanceFixtures.fixture.continuationSamples, warmupCount: PerformanceFixtures.fixture.warmupCount, trialCount: PerformanceFixtures.fixture.trialCount, seed: PerformanceFixtures.fixture.seed)
        XCTAssertThrowsError(try PerformanceFixtures.comparison(baselineFixture: mismatched).validateStructure())

        let mismatchedCandidate = FixtureIdentity(identifier: "other-fixture", markCount: PerformanceFixtures.fixture.markCount, continuationSamples: PerformanceFixtures.fixture.continuationSamples, warmupCount: PerformanceFixtures.fixture.warmupCount, trialCount: PerformanceFixtures.fixture.trialCount, seed: PerformanceFixtures.fixture.seed)
        let candidateWithMismatchedFixture = PerformanceFixtures.report(fixture: mismatchedCandidate)
        XCTAssertThrowsError(try PerformanceComparisonHarness.preflight(baseline: PerformanceFixtures.baseline, candidate: candidateWithMismatchedFixture, configuration: PerformanceFixtures.configuration, eligibility: PerformanceFixtures.eligibility))
        XCTAssertThrowsError(try PerformanceFixtures.comparison(candidateFixture: mismatchedCandidate).validateStructure())
    }

    func testComparisonRejectsEveryMismatchedMeasurementEnvironmentDimension() throws {
        let mutations: [(String, (MeasurementIdentity) -> MeasurementIdentity)] = [
            ("hostModel", { value in MeasurementIdentity(sourceCommitSHA: value.sourceCommitSHA, contentManifestSHA256: value.contentManifestSHA256, hostModel: "other-model", macOSVersion: value.macOSVersion, xcodeVersion: value.xcodeVersion, developerDirectory: value.developerDirectory, powerState: value.powerState, displayState: value.displayState, buildConfiguration: value.buildConfiguration) }),
            ("macOSVersion", { value in MeasurementIdentity(sourceCommitSHA: value.sourceCommitSHA, contentManifestSHA256: value.contentManifestSHA256, hostModel: value.hostModel, macOSVersion: "other-macos", xcodeVersion: value.xcodeVersion, developerDirectory: value.developerDirectory, powerState: value.powerState, displayState: value.displayState, buildConfiguration: value.buildConfiguration) }),
            ("xcodeVersion", { value in MeasurementIdentity(sourceCommitSHA: value.sourceCommitSHA, contentManifestSHA256: value.contentManifestSHA256, hostModel: value.hostModel, macOSVersion: value.macOSVersion, xcodeVersion: "other-xcode", developerDirectory: value.developerDirectory, powerState: value.powerState, displayState: value.displayState, buildConfiguration: value.buildConfiguration) }),
            ("developerDirectory", { value in MeasurementIdentity(sourceCommitSHA: value.sourceCommitSHA, contentManifestSHA256: value.contentManifestSHA256, hostModel: value.hostModel, macOSVersion: value.macOSVersion, xcodeVersion: value.xcodeVersion, developerDirectory: "/other/developer", powerState: value.powerState, displayState: value.displayState, buildConfiguration: value.buildConfiguration) }),
            ("powerState", { value in MeasurementIdentity(sourceCommitSHA: value.sourceCommitSHA, contentManifestSHA256: value.contentManifestSHA256, hostModel: value.hostModel, macOSVersion: value.macOSVersion, xcodeVersion: value.xcodeVersion, developerDirectory: value.developerDirectory, powerState: "battery", displayState: value.displayState, buildConfiguration: value.buildConfiguration) }),
            ("displayState", { value in MeasurementIdentity(sourceCommitSHA: value.sourceCommitSHA, contentManifestSHA256: value.contentManifestSHA256, hostModel: value.hostModel, macOSVersion: value.macOSVersion, xcodeVersion: value.xcodeVersion, developerDirectory: value.developerDirectory, powerState: value.powerState, displayState: "two-displays", buildConfiguration: value.buildConfiguration) }),
            ("buildConfiguration", { value in MeasurementIdentity(sourceCommitSHA: value.sourceCommitSHA, contentManifestSHA256: value.contentManifestSHA256, hostModel: value.hostModel, macOSVersion: value.macOSVersion, xcodeVersion: value.xcodeVersion, developerDirectory: value.developerDirectory, powerState: value.powerState, displayState: value.displayState, buildConfiguration: "debug") }),
        ]

        for (label, mutate) in mutations {
            let report = PerformanceFixtures.comparison(baselineMeasurementIdentity: mutate(PerformanceFixtures.baselineIdentity))
            XCTAssertThrowsError(try report.validateStructure(), "Expected \(label) mismatch to be rejected")
        }
    }

    func testComparisonEnforcesManualEvidenceAndDeterministicExclusion() throws {
        let manual = PerformanceFixtures.comparison(metrics: PerformanceFixtures.metricComparisons(manualMetric: .inputToVisible))
        XCTAssertNoThrow(try manual.validateStructure())

        var missingEvidence = manual.metrics
        let metric = missingEvidence.firstIndex { $0.metricID == .inputToVisible }!
        let value = missingEvidence[metric]
        missingEvidence[metric] = MetricComparison(metricID: value.metricID, evidenceClass: .manual, unit: value.unit, baselineID: value.baselineID, candidateID: value.candidateID, baselineSamples: value.baselineSamples, candidateSamples: value.candidateSamples, ratios: value.ratios, deltas: value.deltas, budgetLimit: value.budgetLimit, bootstrapInterval: value.bootstrapInterval, manualEvidence: nil, disposition: value.disposition)
        XCTAssertThrowsError(try PerformanceFixtures.comparison(metrics: missingEvidence).validateStructure())

        var wrongHostEvidence = manual.metrics
        let manualIndex = wrongHostEvidence.firstIndex { $0.metricID == .inputToVisible }!
        let manualMetric = wrongHostEvidence[manualIndex]
        let evidence = PerformanceFixtures.manualEvidence
        let wrongHost = ManualMetricEvidence(metricID: evidence.metricID, evidenceClass: evidence.evidenceClass, host: "other-machine", recordedAt: evidence.recordedAt, permissions: evidence.permissions, steps: evidence.steps, samples: evidence.samples, result: evidence.result, evidencePath: evidence.evidencePath)
        wrongHostEvidence[manualIndex] = MetricComparison(metricID: manualMetric.metricID, evidenceClass: manualMetric.evidenceClass, unit: manualMetric.unit, baselineID: manualMetric.baselineID, candidateID: manualMetric.candidateID, baselineSamples: manualMetric.baselineSamples, candidateSamples: manualMetric.candidateSamples, ratios: manualMetric.ratios, deltas: manualMetric.deltas, budgetLimit: manualMetric.budgetLimit, bootstrapInterval: manualMetric.bootstrapInterval, manualEvidence: wrongHost, disposition: manualMetric.disposition)
        XCTAssertThrowsError(try PerformanceFixtures.comparison(metrics: wrongHostEvidence).validateStructure())

        var deterministicEvidence = PerformanceFixtures.comparison().metrics
        let deterministic = deterministicEvidence[0]
        deterministicEvidence[0] = MetricComparison(metricID: deterministic.metricID, evidenceClass: .deterministic, unit: deterministic.unit, baselineID: deterministic.baselineID, candidateID: deterministic.candidateID, baselineSamples: deterministic.baselineSamples, candidateSamples: deterministic.candidateSamples, ratios: deterministic.ratios, deltas: deterministic.deltas, budgetLimit: deterministic.budgetLimit, bootstrapInterval: deterministic.bootstrapInterval, manualEvidence: PerformanceFixtures.manualEvidence, disposition: deterministic.disposition)
        XCTAssertThrowsError(try PerformanceFixtures.comparison(metrics: deterministicEvidence).validateStructure())
    }

    func testComparisonRejectsIncoherentResilienceAndDispositionOnCompletion() throws {
        let badResources = ResourceCounts(overlays: 0, timers: 0, handlers: 0, windows: 0, observers: 0)
        let badCase = ResilienceCase(identifier: "mode-toggle", status: .measured, iterationCount: 100, peakResourceCounts: badResources, endResourceCounts: ResourceCounts(overlays: 1, timers: 0, handlers: 0, windows: 0, observers: 0), leakedResource: false, unexpectedGrowth: false)
        let badResilience = ResilienceMeasurement(status: .measured, cases: [badCase], disposition: .acceptedNoRegression)
        let report = PerformanceFixtures.comparison(resilience: badResilience)
        XCTAssertThrowsError(try report.validateStructure())

        let revise = PerformanceFixtures.comparison(disposition: .revise)
        XCTAssertThrowsError(try revise.validateCompletion())
    }

    func testWriteComparisonIsAtomicAndDoesNotLeavePartialOutputOnFailure() throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent("pointer-comparison-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let baselineURL = temp.appendingPathComponent("baseline.json")
        let candidateURL = temp.appendingPathComponent("candidate.json")
        let outputURL = temp.appendingPathComponent("comparisons/paired-comparison.json")
        try JSONEncoder().encode(PerformanceFixtures.baseline).write(to: baselineURL)
        try JSONEncoder().encode(PerformanceFixtures.candidate).write(to: candidateURL)

        XCTAssertThrowsError(try PerformanceComparisonHarness.writeComparison(baselineURL: baselineURL, candidateURL: candidateURL, manualEvidenceDirectory: temp.appendingPathComponent("manual"), outputDirectory: outputURL.deletingLastPathComponent(), configuration: PerformanceFixtures.configuration, eligibility: PerformanceFixtures.eligibility))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testValidPairPassesMeasuredPreflightButCompareRemainsTask3Owned() throws {
        XCTAssertNoThrow(try PerformanceComparisonHarness.preflight(baseline: PerformanceFixtures.baseline, candidate: PerformanceFixtures.candidate, configuration: PerformanceFixtures.configuration, eligibility: PerformanceFixtures.eligibility))
        XCTAssertThrowsError(try PerformanceComparisonHarness.compare(baseline: PerformanceFixtures.baseline, candidate: PerformanceFixtures.candidate, configuration: PerformanceFixtures.configuration, eligibility: PerformanceFixtures.eligibility))
    }
}
