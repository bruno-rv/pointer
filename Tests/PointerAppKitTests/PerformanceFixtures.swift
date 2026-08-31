import Foundation
@testable import PointerAppKit

enum PerformanceFixtures {
    static let configuration = PerformanceConfiguration.standard
    static let foundation = configuration.foundationIdentity
    static let commit = String(repeating: "a", count: 40)
    static let sourceManifest = String(repeating: "b", count: 64)
    static let executable = String(repeating: "c", count: 64)
    static let bundle = String(repeating: "d", count: 64)
    static let foundationArtifact = String(repeating: "e", count: 64)
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
        identifier: "pointer-dense-12-marks",
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
        frameCount: 30,
        missedFrameCount: 0,
        instrumentationStatus: "offscreen-cgcontext"
    )

    static let compositor = FrameMeasurement(
        status: .measured,
        sampleCount: 30,
        p95Milliseconds: 2.0,
        frameCount: 30,
        missedFrameCount: 0,
        instrumentationStatus: "windowserver-signpost"
    )

    static let combinedFrame = FrameMeasurement(
        status: .measured,
        sampleCount: 30,
        p95Milliseconds: 5.0,
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
        p95Milliseconds: 1.5
    )

    static let responsiveness = ResponsivenessMeasurement(
        status: .measured,
        stallCount: 0,
        maximumMainThreadStallMilliseconds: 20,
        p95ResponseMilliseconds: 10
    )

    static let inputToVisible = InputToVisibleMeasurement(
        status: .measured,
        sampleCount: 30,
        p95Milliseconds: 25,
        missedSampleCount: 0
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

    static func withStatuses(
        _ report: PerformanceMeasurementReport,
        status measurementStatus: MeasurementStatus
    ) -> PerformanceMeasurementReport {
        func modelWithStatus(_ value: ModelMeasurement) -> ModelMeasurement {
            ModelMeasurement(status: measurementStatus, trialNanoseconds: value.trialNanoseconds, medianNanoseconds: value.medianNanoseconds, p95Nanoseconds: value.p95Nanoseconds, madNanoseconds: value.madNanoseconds, publicationCount: value.publicationCount, modelChecksum: value.modelChecksum, finalStateValid: value.finalStateValid)
        }
        func frameWithStatus(_ value: FrameMeasurement) -> FrameMeasurement {
            FrameMeasurement(status: measurementStatus, sampleCount: value.sampleCount, p95Milliseconds: value.p95Milliseconds, frameCount: value.frameCount, missedFrameCount: value.missedFrameCount, instrumentationStatus: value.instrumentationStatus)
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
            redrawLayout: RedrawLayoutMeasurement(status: measurementStatus, redrawsPerSample: report.redrawLayout.redrawsPerSample, layoutPasses: report.redrawLayout.layoutPasses, p95Milliseconds: report.redrawLayout.p95Milliseconds),
            responsiveness: ResponsivenessMeasurement(status: measurementStatus, stallCount: report.responsiveness.stallCount, maximumMainThreadStallMilliseconds: report.responsiveness.maximumMainThreadStallMilliseconds, p95ResponseMilliseconds: report.responsiveness.p95ResponseMilliseconds),
            inputToVisible: InputToVisibleMeasurement(status: measurementStatus, sampleCount: report.inputToVisible.sampleCount, p95Milliseconds: report.inputToVisible.p95Milliseconds, missedSampleCount: report.inputToVisible.missedSampleCount),
            memory: MemoryMeasurement(status: measurementStatus, windowSeconds: report.memory.windowSeconds, sampleIntervalSeconds: report.memory.sampleIntervalSeconds, samples: report.memory.samples, aggregates: report.memory.aggregates, peakRSSBytes: report.memory.peakRSSBytes, finalWindowDeltaBytes: report.memory.finalWindowDeltaBytes, finalWindowDeltaPercent: report.memory.finalWindowDeltaPercent, matchedBaselineSeries: report.memory.matchedBaselineSeries, matchedBaselineValues: report.memory.matchedBaselineValues, peakLiveResourceCounts: report.memory.peakLiveResourceCounts, endLiveResourceCounts: report.memory.endLiveResourceCounts),
            resilience: ResilienceMeasurement(status: measurementStatus, cases: report.resilience.cases.map { ResilienceCase(identifier: $0.identifier, status: measurementStatus, iterationCount: $0.iterationCount, peakResourceCounts: $0.peakResourceCounts, endResourceCounts: $0.endResourceCounts, leakedResource: $0.leakedResource, unexpectedGrowth: $0.unexpectedGrowth) }, disposition: report.resilience.disposition),
            disposition: report.disposition
        )
    }

    static func makeMemory(
        samples: [MemorySample] = PerformanceFixtures.memorySamples,
        aggregates: [MemoryAggregate] = PerformanceFixtures.memory.aggregates,
        peakRSSBytes: Int64 = PerformanceFixtures.memory.peakRSSBytes,
        finalWindowDeltaBytes: Int64 = PerformanceFixtures.memory.finalWindowDeltaBytes,
        finalWindowDeltaPercent: Double = PerformanceFixtures.memory.finalWindowDeltaPercent,
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
            matchedBaselineSeries: matchedBaselineSeries,
            matchedBaselineValues: matchedBaselineValues,
            peakLiveResourceCounts: peakLiveResourceCounts,
            endLiveResourceCounts: endLiveResourceCounts
        )
    }
}
