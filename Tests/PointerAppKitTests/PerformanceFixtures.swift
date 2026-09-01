import Foundation
import CryptoKit
@testable import PointerAppKit

enum PerformanceFixtures {
    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static let configuration = PerformanceConfiguration.standard
    static let foundation = configuration.foundationIdentity
    static let commit = String(repeating: "a", count: 40)
    static let sourceManifest = String(repeating: "b", count: 64)
    static let executable = String(repeating: "c", count: 64)
    static let bundle = String(repeating: "d", count: 64)
    static let foundationArtifact = String(repeating: "e", count: 64)
    static let baselineMeasurementReportSHA256 = String(repeating: "6", count: 64)
    static let candidateMeasurementReportSHA256 = String(repeating: "7", count: 64)
    static let recordedAtUTC = "2026-08-31T12:00:00Z"

    static let build = BuildProvenance(
        sourceTreeStatus: .clean,
        sourceIdentity: SourceIdentity(kind: .sourceCommitSHA, value: commit),
        sourceManifestSHA256: sourceManifest,
        executableSHA256: executable,
        bundleManifestSHA256: bundle,
        buildConfiguration: "release",
        recordedAtUTC: recordedAtUTC,
        foundation: foundation,
        harnessVersion: configuration.harnessVersion,
        buildContractVersion: configuration.buildContractVersion,
        acceptedFoundationArtifactSHA256: foundationArtifact
    )

    static let host = HostIdentity(
        machineIdentifier: "fixture-machine",
        processArchitecture: "arm64",
        connectedDisplayUUIDs: ["fixture-display"]
    )

    static let identity = MeasurementIdentity(
        sourceCommitSHA: commit,
        contentManifestSHA256: nil,
        hostModel: "MacBookPro18,3",
        macOSVersion: "14.6.1",
        xcodeVersion: "16.0",
        developerDirectory: "/Applications/Xcode.app/Contents/Developer",
        powerState: "ac",
        displayState: "one-display",
        buildConfiguration: "release"
    )

    static let fixture = FixtureIdentity(
        identifier: PerformanceFixtureProfile.standard12.identifier,
        fixtureProfile: .standard12,
        fixtureVersion: PerformanceFixtureProfile.standard12.version,
        markCount: configuration.fixtureMarkCount,
        continuationSamples: configuration.samplesPerGesture,
        warmupCount: configuration.warmupCount,
        trialCount: configuration.trialCount,
        seed: 1234
    )

    static let run = PerformanceRunProvenance(
        variant: "candidate",
        outputRoot: "build/candidate",
        sourceRef: commit,
        build: build,
        host: host,
        recordedAtUTC: recordedAtUTC,
        configuration: configuration,
        foundationProvenancePath: ".codex/sdd/reports/quality-campaign/foundation/accepted-foundation.json",
        foundation: foundation,
        harnessVersion: configuration.harnessVersion,
        buildContractVersion: configuration.buildContractVersion,
        acceptedFoundationArtifactSHA256: foundationArtifact
    )

    static let baselineCommit = String(repeating: "f", count: 40)

    static let baselineBuild = BuildProvenance(
        sourceTreeStatus: .clean,
        sourceIdentity: SourceIdentity(kind: .sourceCommitSHA, value: baselineCommit),
        sourceManifestSHA256: sourceManifest,
        executableSHA256: String(repeating: "1", count: 64),
        bundleManifestSHA256: String(repeating: "2", count: 64),
        buildConfiguration: "release",
        recordedAtUTC: recordedAtUTC,
        foundation: foundation,
        harnessVersion: configuration.harnessVersion,
        buildContractVersion: configuration.buildContractVersion,
        acceptedFoundationArtifactSHA256: foundationArtifact
    )

    static let baselineIdentity = MeasurementIdentity(
        sourceCommitSHA: baselineCommit,
        contentManifestSHA256: nil,
        hostModel: identity.hostModel,
        macOSVersion: identity.macOSVersion,
        xcodeVersion: identity.xcodeVersion,
        developerDirectory: identity.developerDirectory,
        powerState: identity.powerState,
        displayState: identity.displayState,
        buildConfiguration: "release"
    )

    static let baselineRun = PerformanceRunProvenance(
        variant: "baseline",
        outputRoot: "build/baseline",
        sourceRef: baselineCommit,
        build: baselineBuild,
        host: host,
        recordedAtUTC: recordedAtUTC,
        configuration: configuration,
        foundationProvenancePath: run.foundationProvenancePath,
        foundation: foundation,
        harnessVersion: configuration.harnessVersion,
        buildContractVersion: configuration.buildContractVersion,
        acceptedFoundationArtifactSHA256: foundationArtifact
    )

    static let foundationProvenance = ValidatedFoundationProvenance(
        path: run.foundationProvenancePath,
        foundation: foundation,
        checkpointCommitSHA: String(repeating: "9", count: 40),
        fullSourceManifestSHA256: sourceManifest,
        harnessVersion: configuration.harnessVersion,
        buildContractVersion: configuration.buildContractVersion
    )

    static let eligibility = PerformancePairEligibility(
        baselineRoot: baselineRun.outputRoot,
        candidateRoot: run.outputRoot,
        baselineCommitSHA: baselineCommit,
        candidateCommitSHA: commit,
        foundationProvenance: foundationProvenance
    )

    static let executionArtifact = PerformancePairExecutionArtifact(
        baselineID: baselineCommit,
        candidateID: commit,
        baselineMeasurementReportSHA256: baselineMeasurementReportSHA256,
        candidateMeasurementReportSHA256: candidateMeasurementReportSHA256,
        records: (0..<configuration.totalPairs).map { index in
            let baselineFirst = index < configuration.pairsPerOrder
            let firstStart = index * 4
            let secondStart = firstStart + 2
            return PerformancePairExecutionRecord(
                pairIndex: index,
                order: baselineFirst ? .baselineFirst : .candidateFirst,
                baselineSampleIndex: (index * 7) % configuration.totalPairs,
                candidateSampleIndex: (index * 7) % configuration.totalPairs,
                baselineStartedAtUTC: timestamp(baselineFirst ? firstStart : secondStart),
                candidateStartedAtUTC: timestamp(baselineFirst ? secondStart : firstStart),
                baselineEndedAtUTC: timestamp(baselineFirst ? firstStart + 1 : secondStart + 1),
                candidateEndedAtUTC: timestamp(baselineFirst ? secondStart + 1 : firstStart + 1)
            )
        }
    )

    private static func timestamp(_ offset: Int) -> String {
        String(format: "2026-08-31T12:%02d:%02dZ", offset / 60, offset % 60)
    }

    static let executionArtifactSHA256: String = {
        sha256(try! PerformancePairExecutionArtifact.canonicalData(for: executionArtifact))
    }()

    static let manualEvidencePair: ManualMetricEvidencePair = {
        let records = executionArtifact.records.sorted { $0.pairIndex < $1.pairIndex }
        let baselineSamples = records.map { inputToVisible.sampleMilliseconds[$0.baselineSampleIndex] }
        let candidateSamples = records.map { inputToVisible.sampleMilliseconds[$0.candidateSampleIndex] }
        let baseline = ManualMetricEvidence(metricID: .inputToVisible, evidenceClass: .manual, variant: "baseline", sourceCommitSHA: baselineCommit, measurementReportSHA256: baselineMeasurementReportSHA256, pairExecutionArtifactSHA256: executionArtifactSHA256, host: host.machineIdentifier, recordedAt: recordedAtUTC, permissions: ["Screen Recording"], steps: "Trigger the first-use guide and record input-to-visible latency.", samples: baselineSamples, result: "All samples remained below the 100 ms budget.", evidencePath: "inputToVisible.json")
        let candidate = ManualMetricEvidence(metricID: .inputToVisible, evidenceClass: .manual, variant: "candidate", sourceCommitSHA: commit, measurementReportSHA256: candidateMeasurementReportSHA256, pairExecutionArtifactSHA256: executionArtifactSHA256, host: host.machineIdentifier, recordedAt: recordedAtUTC, permissions: ["Screen Recording"], steps: "Trigger the first-use guide and record input-to-visible latency.", samples: candidateSamples, result: "All samples remained below the 100 ms budget.", evidencePath: "inputToVisible.json")
        return ManualMetricEvidencePair(procedureVersion: "pointer-manual-procedure/v1", pairOrders: records.map(\.order), baseline: baseline, candidate: candidate)
    }()

    static func metricComparisons(manualMetric: PerformanceMetricID? = nil) -> [MetricComparison] {
        PerformanceMetricID.allCases.map { metricID in
            let startingValue: Double
            let delta: Double
            switch metricID {
            case .renderer:
                startingValue = 10
                delta = 0
            case .compositor:
                startingValue = 6.7
                delta = 0
            default:
                startingValue = metricID.canonicalBudgetLimit.map { $0 * 0.5 } ?? 100
                delta = 1
            }
            let pairRecords = executionArtifact.records.sorted { $0.pairIndex < $1.pairIndex }
            let baselineSamples = metricID == manualMetric
                ? pairRecords.map { inputToVisible.sampleMilliseconds[$0.baselineSampleIndex] }
                : (0..<configuration.trialCount).map { index in
                    startingValue + ((metricID == .renderer || metricID == .compositor) ? 0 : Double(index) * 0.1)
                }
            let candidateSamples = metricID == manualMetric ? manualEvidencePair.candidate.samples : baselineSamples.map { $0 - delta }
            let ratios = zip(baselineSamples, candidateSamples).map { baseline, candidate in candidate / baseline }
            let deltas = zip(baselineSamples, candidateSamples).map { baseline, candidate in candidate - baseline }
            let bootstrap = PerformanceComparisonBootstrap.interval(deltas: deltas, seed: configuration.bootstrapSeed, resampleCount: configuration.bootstrapResamples)
            let evidenceClass: MetricEvidenceClass = metricID == manualMetric ? .manual : .deterministic
            return MetricComparison(
                metricID: metricID,
                evidenceClass: evidenceClass,
                unit: metricID.canonicalUnit,
                baselineID: baselineCommit,
                candidateID: commit,
                baselineSamples: baselineSamples,
                candidateSamples: candidateSamples,
                ratios: ratios,
                deltas: deltas,
                budgetLimit: metricID.canonicalBudgetLimit,
                bootstrapInterval: bootstrap,
                manualEvidence: metricID == manualMetric ? manualEvidencePair : nil,
                disposition: .acceptedNoRegression,
                improvementClaimed: bootstrap.upperDelta < 0
            )
        }
    }

    static let baseline: PerformanceMeasurementReport = report(identity: baselineIdentity, build: baselineBuild, run: baselineRun)
    static let candidate: PerformanceMeasurementReport = report()

    static let model = ModelMeasurement(
        status: .measured,
        trialNanoseconds: Array(repeating: 1_000_000, count: 15)
            + Array(repeating: 3_000_000, count: 15),
        medianNanoseconds: 2_000_000,
        p95Nanoseconds: 3_000_000,
        madNanoseconds: 1_000_000,
        publicationCount: 2,
        modelChecksum: "882b4fb5d86096de",
        finalStateValid: true
    )

    static let renderer = FrameMeasurement(
        status: .measured,
        sampleCount: 30,
        p95Milliseconds: 3.0,
        frameMilliseconds: Array(repeating: 2.0, count: 28) + [3.0, 3.0],
        frameCount: 30,
        missedFrameCount: 0,
        instrumentationStatus: "offscreen-cgcontext"
    )

    static let compositor = FrameMeasurement(
        status: .measured,
        sampleCount: 30,
        p95Milliseconds: 2.0,
        frameMilliseconds: Array(repeating: 1.0, count: 28) + [2.0, 2.0],
        frameCount: 30,
        missedFrameCount: 0,
        instrumentationStatus: "windowserver-signpost"
    )

    static let combinedFrame = FrameMeasurement(
        status: .measured,
        sampleCount: 30,
        p95Milliseconds: 5.0,
        frameMilliseconds: Array(repeating: 4.0, count: 28) + [5.0, 5.0],
        frameCount: 30,
        missedFrameCount: 0,
        instrumentationStatus: "render-plus-compositor"
    )

    static let launch = LaunchMeasurement(
        status: .measured,
        coldMilliseconds: Array(repeating: 120, count: configuration.trialCount),
        warmMilliseconds: Array(repeating: 32, count: configuration.trialCount)
    )

    static let allocations = AllocationMeasurement(
        status: .measured,
        bytesPerGesture: Array(repeating: 1024, count: configuration.trialCount),
        peakAllocationBytes: 2048
    )

    static let redrawLayout = RedrawLayoutMeasurement(
        status: .measured,
        redrawsPerSample: Array(repeating: 1, count: configuration.trialCount),
        layoutPasses: Array(repeating: 1, count: configuration.trialCount),
        p95Milliseconds: 1.5,
        sampleMilliseconds: Array(repeating: 1.0, count: 28) + [1.5, 1.5]
    )

    static let responsiveness = ResponsivenessMeasurement(
        status: .measured,
        stallCount: 0,
        maximumMainThreadStallMilliseconds: 20,
        p95ResponseMilliseconds: 10,
        responseMilliseconds: Array(repeating: 8.0, count: 28) + [10.0, 10.0]
    )

    static let inputToVisible = InputToVisibleMeasurement(
        status: .measured,
        sampleCount: 30,
        p95Milliseconds: 25,
        missedSampleCount: 0,
        sampleMilliseconds: Array(repeating: 20.0, count: 28) + [25.0, 25.0]
    )

    static let resources = ResourceCounts(
        overlays: 1,
        timers: 1,
        handlers: 1,
        windows: 1,
        observers: 1
    )

    static let zeroResources = ResourceCounts(
        overlays: 0,
        timers: 0,
        handlers: 0,
        windows: 0,
        observers: 0
    )

    static let runningMemorySamples: [MemorySample] = (0...120).map { index in
        MemorySample(
            elapsedSeconds: Double(index * configuration.memorySampleIntervalSeconds),
            rssBytes: 100_000_000,
            phase: .running,
            resources: resources
        )
    }

    static let memorySamples = runningMemorySamples + [
        MemorySample(elapsedSeconds: 605, rssBytes: 100_000_000, phase: .stopping, resources: zeroResources),
        MemorySample(elapsedSeconds: 610, rssBytes: 100_000_000, phase: .stopped, resources: zeroResources),
        MemorySample(elapsedSeconds: 615, rssBytes: 100_000_000, phase: .restarted, resources: resources),
    ]

    static let memory = MemoryMeasurement(
        status: .measured,
        windowSeconds: configuration.memoryWindowSeconds,
        sampleIntervalSeconds: configuration.memorySampleIntervalSeconds,
        samples: memorySamples,
        aggregates: (0..<11).map { index in
            MemoryAggregate(
                intervalIndex: index,
                sampleCount: 11,
                meanRSSBytes: 100_000_000,
                peakRSSBytes: 100_000_000
            )
        },
        peakRSSBytes: 100_000_000,
        finalWindowDeltaBytes: 0,
        finalWindowDeltaPercent: 0,
        postWarmupSlopeBytesPerSecond: 0,
        matchedBaselineSeries: runningMemorySamples.map(\.elapsedSeconds),
        matchedBaselineValues: Array(repeating: 100_000_000, count: runningMemorySamples.count),
        peakLiveResourceCounts: resources,
        endLiveResourceCounts: resources
    )

    static let resilience = ResilienceMeasurement(
        status: .measured,
        cases: [ResilienceCase(
            identifier: "mode-toggle",
            status: .measured,
            iterationCount: 100,
            peakResourceCounts: resources,
            endResourceCounts: resources,
            leakedResource: false,
            unexpectedGrowth: false
        )],
        disposition: .acceptedNoRegression
    )

    static func report(
        reportKind: PerformanceReportKind = .measurement,
        identity: MeasurementIdentity = PerformanceFixtures.identity,
        build: BuildProvenance = PerformanceFixtures.build,
        run: PerformanceRunProvenance = PerformanceFixtures.run,
        model: ModelMeasurement = PerformanceFixtures.model,
        renderer: FrameMeasurement = PerformanceFixtures.renderer,
        compositor: FrameMeasurement = PerformanceFixtures.compositor,
        combinedFrame: FrameMeasurement = PerformanceFixtures.combinedFrame,
        launch: LaunchMeasurement = PerformanceFixtures.launch,
        allocations: AllocationMeasurement = PerformanceFixtures.allocations,
        redrawLayout: RedrawLayoutMeasurement = PerformanceFixtures.redrawLayout,
        responsiveness: ResponsivenessMeasurement = PerformanceFixtures.responsiveness,
        inputToVisible: InputToVisibleMeasurement = PerformanceFixtures.inputToVisible,
        memory: MemoryMeasurement = PerformanceFixtures.memory,
        resilience: ResilienceMeasurement = PerformanceFixtures.resilience,
        fixture: FixtureIdentity = PerformanceFixtures.fixture,
        disposition: Disposition = .acceptedNoRegression
    ) -> PerformanceMeasurementReport {
        return PerformanceMeasurementReport(
            reportKind: reportKind,
            schemaVersion: 1,
            harnessVersion: configuration.harnessVersion,
            foundationIdentity: foundation,
            buildContractVersion: configuration.buildContractVersion,
            buildProvenance: build,
            runProvenance: run,
            identity: identity,
            host: host,
            fixture: fixture,
            model: model,
            renderer: renderer,
            compositor: compositor,
            combinedFrame: combinedFrame,
            launch: launch,
            allocations: allocations,
            redrawLayout: redrawLayout,
            responsiveness: responsiveness,
            inputToVisible: inputToVisible,
            memory: memory,
            resilience: resilience,
            disposition: disposition
        )
    }

    static func draft(
        baselineBuild: BuildProvenance = PerformanceFixtures.baselineBuild,
        candidateBuild: BuildProvenance = PerformanceFixtures.build,
        baselineRun: PerformanceRunProvenance = PerformanceFixtures.baselineRun,
        candidateRun: PerformanceRunProvenance = PerformanceFixtures.run,
        eligibility: PerformancePairEligibility = PerformanceFixtures.eligibility,
        pairExecutionArtifact: PerformancePairExecutionArtifact = PerformanceFixtures.executionArtifact,
        pairExecutionArtifactSHA256: String = PerformanceFixtures.executionArtifactSHA256,
        baselineFixture: FixtureIdentity = PerformanceFixtures.fixture,
        candidateFixture: FixtureIdentity = PerformanceFixtures.fixture,
        baselineMeasurementIdentity: MeasurementIdentity = PerformanceFixtures.baselineIdentity,
        candidateMeasurementIdentity: MeasurementIdentity = PerformanceFixtures.identity,
        metrics: [MetricComparison] = PerformanceFixtures.metricComparisons(),
        resilience: ResilienceMeasurement = PerformanceFixtures.resilience,
        disposition: Disposition = .acceptedNoRegression
    ) -> PerformanceComparisonDraft {
        PerformanceComparisonDraft(
            harnessVersion: configuration.harnessVersion,
            foundationIdentity: foundation,
            buildContractVersion: configuration.buildContractVersion,
            baselineBuildProvenance: baselineBuild,
            candidateBuildProvenance: candidateBuild,
            baselineRunProvenance: baselineRun,
            candidateRunProvenance: candidateRun,
            pairEligibility: eligibility,
            pairExecutionArtifact: pairExecutionArtifact,
            pairExecutionArtifactSHA256: pairExecutionArtifactSHA256,
            baselineFixture: baselineFixture,
            candidateFixture: candidateFixture,
            baselineMeasurementIdentity: baselineMeasurementIdentity,
            candidateMeasurementIdentity: candidateMeasurementIdentity,
            baselineID: baselineBuild.sourceIdentity.value,
            candidateID: candidateBuild.sourceIdentity.value,
            metrics: metrics,
            resilience: resilience,
            seed: configuration.bootstrapSeed,
            resampleCount: configuration.bootstrapResamples,
            disposition: disposition
        )
    }

    static func comparison(
        baselineBuild: BuildProvenance = PerformanceFixtures.baselineBuild,
        candidateBuild: BuildProvenance = PerformanceFixtures.build,
        baselineRun: PerformanceRunProvenance = PerformanceFixtures.baselineRun,
        candidateRun: PerformanceRunProvenance = PerformanceFixtures.run,
        eligibility: PerformancePairEligibility = PerformanceFixtures.eligibility,
        pairExecutionArtifact: PerformancePairExecutionArtifact = PerformanceFixtures.executionArtifact,
        pairExecutionArtifactSHA256: String = PerformanceFixtures.executionArtifactSHA256,
        baselineFixture: FixtureIdentity = PerformanceFixtures.fixture,
        candidateFixture: FixtureIdentity = PerformanceFixtures.fixture,
        baselineMeasurementIdentity: MeasurementIdentity = PerformanceFixtures.baselineIdentity,
        candidateMeasurementIdentity: MeasurementIdentity = PerformanceFixtures.identity,
        baselineMeasurementReportSHA256: String = PerformanceFixtures.baselineMeasurementReportSHA256,
        candidateMeasurementReportSHA256: String = PerformanceFixtures.candidateMeasurementReportSHA256,
        metrics: [MetricComparison] = PerformanceFixtures.metricComparisons(),
        resilience: ResilienceMeasurement = PerformanceFixtures.resilience,
        disposition: Disposition = .acceptedNoRegression
    ) -> PerformanceComparisonReport {
        PerformanceComparisonReport(
            draft: draft(
                baselineBuild: baselineBuild,
                candidateBuild: candidateBuild,
                baselineRun: baselineRun,
                candidateRun: candidateRun,
                eligibility: eligibility,
                pairExecutionArtifact: pairExecutionArtifact,
                pairExecutionArtifactSHA256: pairExecutionArtifactSHA256,
                baselineFixture: baselineFixture,
                candidateFixture: candidateFixture,
                baselineMeasurementIdentity: baselineMeasurementIdentity,
                candidateMeasurementIdentity: candidateMeasurementIdentity,
                metrics: metrics,
                resilience: resilience,
                disposition: disposition
            ),
            baselineMeasurementReportSHA256: baselineMeasurementReportSHA256,
            candidateMeasurementReportSHA256: candidateMeasurementReportSHA256
        )
    }

    static func withStatuses(
        _ report: PerformanceMeasurementReport,
        status measurementStatus: MeasurementStatus,
        disposition: Disposition = .revise
    ) -> PerformanceMeasurementReport {
        func modelWithStatus(_ value: ModelMeasurement) -> ModelMeasurement {
            ModelMeasurement(status: measurementStatus, trialNanoseconds: value.trialNanoseconds, medianNanoseconds: value.medianNanoseconds, p95Nanoseconds: value.p95Nanoseconds, madNanoseconds: value.madNanoseconds, publicationCount: value.publicationCount, modelChecksum: value.modelChecksum, finalStateValid: value.finalStateValid)
        }
        func frameWithStatus(_ value: FrameMeasurement) -> FrameMeasurement {
            FrameMeasurement(status: measurementStatus, sampleCount: measurementStatus == .measured ? value.sampleCount : 0, p95Milliseconds: value.p95Milliseconds, frameMilliseconds: measurementStatus == .measured ? value.frameMilliseconds : [], frameCount: measurementStatus == .measured ? value.frameCount : 0, missedFrameCount: measurementStatus == .measured ? value.missedFrameCount : 0, instrumentationStatus: value.instrumentationStatus)
        }
        return PerformanceMeasurementReport(
            reportKind: report.reportKind,
            schemaVersion: report.schemaVersion,
            harnessVersion: report.harnessVersion,
            foundationIdentity: report.foundationIdentity,
            buildContractVersion: report.buildContractVersion,
            buildProvenance: report.buildProvenance,
            runProvenance: report.runProvenance,
            identity: report.identity,
            host: report.host,
            fixture: report.fixture,
            model: modelWithStatus(report.model),
            renderer: frameWithStatus(report.renderer),
            compositor: frameWithStatus(report.compositor),
            combinedFrame: frameWithStatus(report.combinedFrame),
            launch: LaunchMeasurement(status: measurementStatus, coldMilliseconds: report.launch.coldMilliseconds, warmMilliseconds: report.launch.warmMilliseconds),
            allocations: AllocationMeasurement(status: measurementStatus, bytesPerGesture: report.allocations.bytesPerGesture, peakAllocationBytes: report.allocations.peakAllocationBytes),
            redrawLayout: RedrawLayoutMeasurement(status: measurementStatus, redrawsPerSample: measurementStatus == .measured ? report.redrawLayout.redrawsPerSample : [], layoutPasses: measurementStatus == .measured ? report.redrawLayout.layoutPasses : [], p95Milliseconds: report.redrawLayout.p95Milliseconds, sampleMilliseconds: measurementStatus == .measured ? report.redrawLayout.sampleMilliseconds : []),
            responsiveness: ResponsivenessMeasurement(status: measurementStatus, stallCount: measurementStatus == .measured ? report.responsiveness.stallCount : 0, maximumMainThreadStallMilliseconds: report.responsiveness.maximumMainThreadStallMilliseconds, p95ResponseMilliseconds: report.responsiveness.p95ResponseMilliseconds, responseMilliseconds: measurementStatus == .measured ? report.responsiveness.responseMilliseconds : []),
            inputToVisible: InputToVisibleMeasurement(status: measurementStatus, sampleCount: measurementStatus == .measured ? report.inputToVisible.sampleCount : 0, p95Milliseconds: report.inputToVisible.p95Milliseconds, missedSampleCount: measurementStatus == .measured ? report.inputToVisible.missedSampleCount : 0, sampleMilliseconds: measurementStatus == .measured ? report.inputToVisible.sampleMilliseconds : []),
            memory: MemoryMeasurement(status: measurementStatus, windowSeconds: report.memory.windowSeconds, sampleIntervalSeconds: report.memory.sampleIntervalSeconds, samples: report.memory.samples, aggregates: report.memory.aggregates, peakRSSBytes: report.memory.peakRSSBytes, finalWindowDeltaBytes: report.memory.finalWindowDeltaBytes, finalWindowDeltaPercent: report.memory.finalWindowDeltaPercent, postWarmupSlopeBytesPerSecond: report.memory.postWarmupSlopeBytesPerSecond, matchedBaselineSeries: report.memory.matchedBaselineSeries, matchedBaselineValues: report.memory.matchedBaselineValues, peakLiveResourceCounts: report.memory.peakLiveResourceCounts, endLiveResourceCounts: report.memory.endLiveResourceCounts),
            resilience: ResilienceMeasurement(status: measurementStatus, cases: report.resilience.cases.map { ResilienceCase(identifier: $0.identifier, status: measurementStatus, iterationCount: $0.iterationCount, peakResourceCounts: $0.peakResourceCounts, endResourceCounts: $0.endResourceCounts, leakedResource: $0.leakedResource, unexpectedGrowth: $0.unexpectedGrowth) }, disposition: report.resilience.disposition),
            disposition: disposition
        )
    }

    static func makeMemory(
        samples: [MemorySample] = PerformanceFixtures.memorySamples,
        aggregates: [MemoryAggregate] = PerformanceFixtures.memory.aggregates,
        peakRSSBytes: Int64 = PerformanceFixtures.memory.peakRSSBytes,
        finalWindowDeltaBytes: Int64 = PerformanceFixtures.memory.finalWindowDeltaBytes,
        finalWindowDeltaPercent: Double = PerformanceFixtures.memory.finalWindowDeltaPercent,
        postWarmupSlopeBytesPerSecond: Double? = nil,
        matchedBaselineSeries: [Double] = PerformanceFixtures.memory.matchedBaselineSeries,
        matchedBaselineValues: [Int64] = PerformanceFixtures.memory.matchedBaselineValues,
        peakLiveResourceCounts: ResourceCounts = PerformanceFixtures.memory.peakLiveResourceCounts,
        endLiveResourceCounts: ResourceCounts = PerformanceFixtures.memory.endLiveResourceCounts,
        status: MeasurementStatus = .measured
    ) -> MemoryMeasurement {
        MemoryMeasurement(
            status: status,
            windowSeconds: configuration.memoryWindowSeconds,
            sampleIntervalSeconds: configuration.memorySampleIntervalSeconds,
            samples: samples,
            aggregates: aggregates,
            peakRSSBytes: peakRSSBytes,
            finalWindowDeltaBytes: finalWindowDeltaBytes,
            finalWindowDeltaPercent: finalWindowDeltaPercent,
            postWarmupSlopeBytesPerSecond: postWarmupSlopeBytesPerSecond ?? leastSquaresSlope(for: samples),
            matchedBaselineSeries: matchedBaselineSeries,
            matchedBaselineValues: matchedBaselineValues,
            peakLiveResourceCounts: peakLiveResourceCounts,
            endLiveResourceCounts: endLiveResourceCounts
        )
    }

    static func leastSquaresSlope(for samples: [MemorySample]) -> Double {
        let running = samples.filter { $0.phase == .running }
        let postWarmup = Array(running.dropFirst(configuration.warmupCount))
        let meanElapsed = postWarmup.map(\.elapsedSeconds).reduce(0, +) / Double(postWarmup.count)
        let meanRSS = postWarmup.map { Double($0.rssBytes) }.reduce(0, +) / Double(postWarmup.count)
        let numerator = postWarmup.reduce(0.0) { total, sample in
            total + (sample.elapsedSeconds - meanElapsed) * (Double(sample.rssBytes) - meanRSS)
        }
        let denominator = postWarmup.reduce(0.0) { total, sample in
            total + pow(sample.elapsedSeconds - meanElapsed, 2)
        }
        return numerator / denominator
    }
}
