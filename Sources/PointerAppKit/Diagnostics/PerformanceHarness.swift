import AppKit
import CoreGraphics
import Foundation
import PointerCore
import QuartzCore

@MainActor
public protocol ModelInstrumentationAdapter {
    func measureModel(configuration: PerformanceConfiguration) -> ModelMeasurement
}

@MainActor
public protocol RendererInstrumentationAdapter {
    func measureRenderer(configuration: PerformanceConfiguration) -> FrameMeasurement
}

@MainActor
public protocol CompositorInstrumentationAdapter {
    func measureCompositor(configuration: PerformanceConfiguration) -> FrameMeasurement
}

@MainActor
public protocol CombinedFrameInstrumentationAdapter {
    func measureCombinedFrame(configuration: PerformanceConfiguration) -> FrameMeasurement
}

@MainActor
public protocol LaunchInstrumentationAdapter {
    func measureLaunch(configuration: PerformanceConfiguration) -> LaunchMeasurement
}

@MainActor
public protocol AllocationInstrumentationAdapter {
    func measureAllocations(configuration: PerformanceConfiguration) -> AllocationMeasurement
}

@MainActor
public protocol RedrawLayoutInstrumentationAdapter {
    func measureRedrawLayout(configuration: PerformanceConfiguration) -> RedrawLayoutMeasurement
}

@MainActor
public protocol ResponsivenessInstrumentationAdapter {
    func measureResponsiveness(configuration: PerformanceConfiguration) -> ResponsivenessMeasurement
}

@MainActor
public protocol InputToVisibleInstrumentationAdapter {
    func measureInputToVisible(configuration: PerformanceConfiguration) -> InputToVisibleMeasurement
}

@MainActor
public protocol MemoryInstrumentationAdapter {
    func measureMemory(configuration: PerformanceConfiguration) -> MemoryMeasurement
}

@MainActor
public protocol ResilienceInstrumentationAdapter {
    func measureResilience(configuration: PerformanceConfiguration) -> ResilienceMeasurement
}

/// A process-oriented adapter may be supplied by the Release launcher when
/// `/usr/bin/time` and task_info are available. It is intentionally separate
/// from the report schema so an unavailable host probe cannot look measured.
@MainActor
public protocol ProcessMetricsInstrumentationAdapter {
    func measureLaunch(configuration: PerformanceConfiguration) -> LaunchMeasurement
    func measureAllocations(configuration: PerformanceConfiguration) -> AllocationMeasurement
    func measureMemory(configuration: PerformanceConfiguration) -> MemoryMeasurement
}

@MainActor
internal struct PerformanceHarnessAdapterBundle {
    let model: any ModelInstrumentationAdapter
    let renderer: any RendererInstrumentationAdapter
    let compositor: any CompositorInstrumentationAdapter
    let combinedFrame: any CombinedFrameInstrumentationAdapter
    let launch: any LaunchInstrumentationAdapter
    let allocations: any AllocationInstrumentationAdapter
    let redrawLayout: any RedrawLayoutInstrumentationAdapter
    let responsiveness: any ResponsivenessInstrumentationAdapter
    let inputToVisible: any InputToVisibleInstrumentationAdapter
    let memory: any MemoryInstrumentationAdapter
    let resilience: any ResilienceInstrumentationAdapter

    init(
        model: any ModelInstrumentationAdapter,
        renderer: any RendererInstrumentationAdapter,
        compositor: any CompositorInstrumentationAdapter,
        combinedFrame: any CombinedFrameInstrumentationAdapter,
        launch: any LaunchInstrumentationAdapter,
        allocations: any AllocationInstrumentationAdapter,
        redrawLayout: any RedrawLayoutInstrumentationAdapter,
        responsiveness: any ResponsivenessInstrumentationAdapter,
        inputToVisible: any InputToVisibleInstrumentationAdapter,
        memory: any MemoryInstrumentationAdapter,
        resilience: any ResilienceInstrumentationAdapter
    ) {
        self.model = model
        self.renderer = renderer
        self.compositor = compositor
        self.combinedFrame = combinedFrame
        self.launch = launch
        self.allocations = allocations
        self.redrawLayout = redrawLayout
        self.responsiveness = responsiveness
        self.inputToVisible = inputToVisible
        self.memory = memory
        self.resilience = resilience
    }
}

public enum PerformanceHarnessError: Error, Equatable, Sendable, CustomStringConvertible {
    case invalidInput(String)

    public var description: String {
        switch self {
        case let .invalidInput(message): return message
        }
    }
}

/// Runs one immutable measurement report. The public surface uses production
/// adapters; the internal bundle keeps unavailable OS instrumentation explicit
/// and makes deterministic adapter tests possible without faking application
/// input or replacing the PointerSession/CanvasView path.
@MainActor
public enum PerformanceHarness {
    internal typealias AdapterBundle = PerformanceHarnessAdapterBundle

    public static func measureModel(configuration: PerformanceConfiguration) -> ModelMeasurement {
        GestureBenchmarkInstrumentationAdapter().measureModel(configuration: configuration)
    }

    public static func measureRenderer(configuration: PerformanceConfiguration) -> FrameMeasurement {
        OffscreenCanvasRendererAdapter().measureRenderer(configuration: configuration)
    }

    public static func measureCompositor(configuration: PerformanceConfiguration) -> FrameMeasurement {
        SignpostWindowServerAdapter().measureCompositor(configuration: configuration)
    }

    public static func measureCombinedFrame(configuration: PerformanceConfiguration) -> FrameMeasurement {
        UnavailableCombinedFrameAdapter().measureCombinedFrame(configuration: configuration)
    }

    public static func measureLaunch(configuration: PerformanceConfiguration) -> LaunchMeasurement {
        DefaultProcessMetricsAdapter().measureLaunch(configuration: configuration)
    }

    public static func measureAllocations(configuration: PerformanceConfiguration) -> AllocationMeasurement {
        DefaultProcessMetricsAdapter().measureAllocations(configuration: configuration)
    }

    public static func measureRedrawLayout(configuration: PerformanceConfiguration) -> RedrawLayoutMeasurement {
        UnavailableRedrawLayoutAdapter().measureRedrawLayout(configuration: configuration)
    }

    public static func measureResponsiveness(configuration: PerformanceConfiguration) -> ResponsivenessMeasurement {
        UnavailableResponsivenessAdapter().measureResponsiveness(configuration: configuration)
    }

    public static func measureInputToVisible(configuration: PerformanceConfiguration) -> InputToVisibleMeasurement {
        UnavailableInputToVisibleAdapter().measureInputToVisible(configuration: configuration)
    }

    public static func measureMemory(configuration: PerformanceConfiguration) -> MemoryMeasurement {
        DefaultProcessMetricsAdapter().measureMemory(configuration: configuration)
    }

    public static func measureResilience(configuration: PerformanceConfiguration) -> ResilienceMeasurement {
        UnavailableResilienceAdapter().measureResilience(configuration: configuration)
    }

    public static func run(
        configuration: PerformanceConfiguration,
        buildProvenance: BuildProvenance,
        runProvenance: PerformanceRunProvenance
    ) throws -> PerformanceMeasurementReport {
        guard configuration == .standard else {
            throw PerformanceHarnessError.invalidInput(
                "public performance runs require PerformanceConfiguration.standard"
            )
        }
        return try run(
            configuration: configuration,
            buildProvenance: buildProvenance,
            runProvenance: runProvenance,
            adapters: productionAdapters()
        )
    }

    internal static func run(
        configuration: PerformanceConfiguration,
        buildProvenance: BuildProvenance,
        runProvenance: PerformanceRunProvenance,
        adapters: AdapterBundle
    ) throws -> PerformanceMeasurementReport {
        guard runProvenance.configuration == configuration else {
            throw PerformanceHarnessError.invalidInput("run/configuration mismatch")
        }
        guard runProvenance.build == buildProvenance else {
            throw PerformanceHarnessError.invalidInput("run/build provenance mismatch")
        }

        let report = PerformanceMeasurementReport(
            reportKind: .measurement,
            schemaVersion: PerformanceMeasurementReport.currentSchemaVersion,
            harnessVersion: configuration.harnessVersion,
            foundationIdentity: configuration.foundationIdentity,
            buildContractVersion: configuration.buildContractVersion,
            buildProvenance: buildProvenance,
            runProvenance: runProvenance,
            identity: identity(for: buildProvenance, host: runProvenance.host),
            host: runProvenance.host,
            fixture: FixtureIdentity(
                identifier: "pointer-dense-\(configuration.fixtureMarkCount)-marks",
                markCount: configuration.fixtureMarkCount,
                continuationSamples: configuration.samplesPerGesture,
                warmupCount: configuration.warmupCount,
                trialCount: configuration.trialCount,
                seed: 1234
            ),
            model: adapters.model.measureModel(configuration: configuration),
            renderer: adapters.renderer.measureRenderer(configuration: configuration),
            compositor: adapters.compositor.measureCompositor(configuration: configuration),
            combinedFrame: adapters.combinedFrame.measureCombinedFrame(configuration: configuration),
            launch: adapters.launch.measureLaunch(configuration: configuration),
            allocations: adapters.allocations.measureAllocations(configuration: configuration),
            redrawLayout: adapters.redrawLayout.measureRedrawLayout(configuration: configuration),
            responsiveness: adapters.responsiveness.measureResponsiveness(configuration: configuration),
            inputToVisible: adapters.inputToVisible.measureInputToVisible(configuration: configuration),
            memory: adapters.memory.measureMemory(configuration: configuration),
            resilience: adapters.resilience.measureResilience(configuration: configuration),
            disposition: .blocked
        )

        try report.validateStructure()
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
            model: report.model,
            renderer: report.renderer,
            compositor: report.compositor,
            combinedFrame: report.combinedFrame,
            launch: report.launch,
            allocations: report.allocations,
            redrawLayout: report.redrawLayout,
            responsiveness: report.responsiveness,
            inputToVisible: report.inputToVisible,
            memory: report.memory,
            resilience: report.resilience,
            disposition: disposition(for: report)
        )
    }

    private static func productionAdapters() -> AdapterBundle {
        AdapterBundle(
            model: GestureBenchmarkInstrumentationAdapter(),
            renderer: OffscreenCanvasRendererAdapter(),
            compositor: SignpostWindowServerAdapter(),
            combinedFrame: UnavailableCombinedFrameAdapter(),
            launch: DefaultProcessMetricsAdapter(),
            allocations: DefaultProcessMetricsAdapter(),
            redrawLayout: UnavailableRedrawLayoutAdapter(),
            responsiveness: UnavailableResponsivenessAdapter(),
            inputToVisible: UnavailableInputToVisibleAdapter(),
            memory: DefaultProcessMetricsAdapter(),
            resilience: UnavailableResilienceAdapter()
        )
    }

    private static func identity(
        for build: BuildProvenance,
        host: HostIdentity
    ) -> MeasurementIdentity {
        let environment = ProcessInfo.processInfo.environment
        let sourceCommitSHA = build.sourceTreeStatus == .clean
            ? build.sourceIdentity.value
            : nil
        let contentManifestSHA256 = build.sourceTreeStatus == .dirty
            ? build.sourceIdentity.value
            : nil
        return MeasurementIdentity(
            sourceCommitSHA: sourceCommitSHA,
            contentManifestSHA256: contentManifestSHA256,
            hostModel: host.machineIdentifier,
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            xcodeVersion: environment["POINTER_XCODE_VERSION"] ?? "unavailable",
            developerDirectory: environment["DEVELOPER_DIR"] ?? "unavailable",
            powerState: environment["POINTER_POWER_STATE"] ?? "unavailable",
            displayState: host.connectedDisplayUUIDs.sorted().joined(separator: ","),
            buildConfiguration: build.buildConfiguration
        )
    }

    private static func disposition(for report: PerformanceMeasurementReport) -> Disposition {
        let statuses = [
            report.model.status,
            report.renderer.status,
            report.compositor.status,
            report.combinedFrame.status,
            report.launch.status,
            report.allocations.status,
            report.redrawLayout.status,
            report.responsiveness.status,
            report.inputToVisible.status,
            report.memory.status,
            report.resilience.status,
        ]
        if statuses.contains(.failed) {
            return .revise
        }
        if statuses.contains(.unmeasured) {
            return .blocked
        }
        if report.renderer.missedFrameCount > 0
            || report.compositor.missedFrameCount > 0
            || report.combinedFrame.missedFrameCount > 0
            || report.renderer.p95Milliseconds + report.compositor.p95Milliseconds > 16.7
            || report.combinedFrame.p95Milliseconds > 16.7
            || report.responsiveness.stallCount > 0
            || report.responsiveness.maximumMainThreadStallMilliseconds > 100
            || report.responsiveness.p95ResponseMilliseconds > 100
            || report.inputToVisible.missedSampleCount > 0
            || report.inputToVisible.p95Milliseconds > 100
            || abs(report.memory.finalWindowDeltaBytes) > 50 * 1024 * 1024
            || report.memory.finalWindowDeltaPercent > 10
            || report.memory.postWarmupSlopeBytesPerSecond > 1e-9 {
            return .revise
        }
        if report.resilience.disposition != .acceptedNoRegression
            || report.resilience.cases.contains(where: { $0.leakedResource || $0.unexpectedGrowth }) {
            return .revise
        }
        return .acceptedNoRegression
    }

    internal static func modelStatus(
        checksumIsStable: Bool,
        finalStateValid: Bool,
        publicationsPerGesture: [Int],
        expectedTrialCount: Int
    ) -> MeasurementStatus {
        guard checksumIsStable,
              finalStateValid,
              publicationsPerGesture.count == expectedTrialCount,
              publicationsPerGesture.allSatisfy({ $0 == 2 })
        else {
            return .failed
        }
        return .measured
    }
}

@MainActor
public final class GestureBenchmarkInstrumentationAdapter: ModelInstrumentationAdapter {
    public init() {}

    public func measureModel(configuration: PerformanceConfiguration) -> ModelMeasurement {
        let result = GestureBenchmark.run(
            trials: configuration.trialCount,
            samples: configuration.samplesPerGesture
        )
        return ModelMeasurement(
            status: result.trialNanoseconds.isEmpty
                ? .unmeasured
                : PerformanceHarness.modelStatus(
                    checksumIsStable: result.checksumIsStable,
                    finalStateValid: result.finalStateValid,
                    publicationsPerGesture: result.publicationsPerGesture,
                    expectedTrialCount: configuration.trialCount
                ),
            trialNanoseconds: result.trialNanoseconds,
            medianNanoseconds: result.medianNanoseconds,
            p95Nanoseconds: result.p95Nanoseconds,
            madNanoseconds: result.madNanoseconds,
            publicationCount: result.publicationsPerGesture.first ?? 0,
            modelChecksum: result.modelChecksum,
            finalStateValid: result.finalStateValid
        )
    }
}

@MainActor
public final class OffscreenCanvasRendererAdapter: RendererInstrumentationAdapter {
    public init() {}

    public func measureRenderer(configuration: PerformanceConfiguration) -> FrameMeasurement {
        guard configuration.trialCount > 0 else {
            return Self.unmeasured("offscreen-canvasview-invalid-trial-count")
        }
        _ = NSApplication.shared

        let display = DisplayUUID(rawValue: "performance-render-display")
        let frame = NSRect(x: 0, y: 0, width: 512, height: 512)
        let session = Self.fixtureSession(display: display)
        let view = CanvasView(frame: frame, display: display, session: session, tool: .select)
        let window = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: true
        )
        window.contentView = view
        defer { window.contentView = nil }

        guard let context = CGContext(
            data: nil,
            width: 512,
            height: 512,
            bitsPerComponent: 8,
            bytesPerRow: 512 * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return Self.unmeasured("offscreen-canvasview-context-unavailable")
        }

        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        for _ in 0..<configuration.warmupCount {
            context.clear(frame)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphicsContext
            view.draw(frame)
            NSGraphicsContext.restoreGraphicsState()
        }
        var samples: [Double] = []
        samples.reserveCapacity(configuration.trialCount)
        for _ in 0..<configuration.trialCount {
            context.clear(frame)
            let start = CACurrentMediaTime()
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphicsContext
            view.draw(frame)
            NSGraphicsContext.restoreGraphicsState()
            samples.append((CACurrentMediaTime() - start) * 1_000)
        }
        guard samples.allSatisfy({ $0.isFinite && $0 > 0 }) else {
            return Self.unmeasured("offscreen-canvasview-invalid-sample")
        }
        return FrameMeasurement(
            status: .measured,
            sampleCount: samples.count,
            p95Milliseconds: Self.nearestRankP95(samples),
            frameMilliseconds: samples,
            frameCount: samples.count,
            missedFrameCount: 0,
            instrumentationStatus: "offscreen-canvasview-cgcontext"
        )
    }

    private static func fixtureSession(display: DisplayUUID) -> PointerSession {
        var session = PointerSession()
        let tools: [MarkGeometry] = [
            .arrow(
                start: NormalizedPoint(x: 0.06, y: 0.08),
                end: NormalizedPoint(x: 0.18, y: 0.17)
            ),
            .rectangle(NormalizedRect(x: 0.28, y: 0.1, width: 0.18, height: 0.14)),
            .ellipse(NormalizedRect(x: 0.56, y: 0.1, width: 0.16, height: 0.15)),
        ]
        for index in 0..<12 {
            let geometry = tools[index % tools.count]
            let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!
            session.apply(.append(Mark(id: id, geometry: geometry, style: .default), to: display))
        }
        return session
    }

    private static func unmeasured(_ reason: String) -> FrameMeasurement {
        FrameMeasurement(
            status: .unmeasured,
            sampleCount: 0,
            p95Milliseconds: 0,
            frameCount: 0,
            missedFrameCount: 0,
            instrumentationStatus: reason
        )
    }

    private static func nearestRankP95(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let rank = max(1, Int(ceil(0.95 * Double(sorted.count))))
        return sorted[rank - 1]
    }
}

@MainActor
public final class SignpostWindowServerAdapter: CompositorInstrumentationAdapter {
    public init() {}

    public func measureCompositor(configuration: PerformanceConfiguration) -> FrameMeasurement {
        FrameMeasurement(
            status: .unmeasured,
            sampleCount: 0,
            p95Milliseconds: 0,
            frameCount: 0,
            missedFrameCount: 0,
            instrumentationStatus: "windowserver-signpost-unavailable: host compositor timing is not observable in-process"
        )
    }
}

@MainActor
private final class UnavailableCombinedFrameAdapter: CombinedFrameInstrumentationAdapter {
    func measureCombinedFrame(configuration: PerformanceConfiguration) -> FrameMeasurement {
        FrameMeasurement(
            status: .unmeasured,
            sampleCount: 0,
            p95Milliseconds: 0,
            frameCount: 0,
            missedFrameCount: 0,
            instrumentationStatus: "combined-frame-unavailable: compositor timing is unmeasured"
        )
    }
}

@MainActor
public final class DefaultProcessMetricsAdapter: ProcessMetricsInstrumentationAdapter,
    LaunchInstrumentationAdapter,
    AllocationInstrumentationAdapter,
    MemoryInstrumentationAdapter {
    public init() {}

    public func measureLaunch(configuration: PerformanceConfiguration) -> LaunchMeasurement {
        LaunchMeasurement(
            status: .unmeasured,
            coldMilliseconds: [],
            warmMilliseconds: []
        )
    }

    public func measureAllocations(configuration: PerformanceConfiguration) -> AllocationMeasurement {
        AllocationMeasurement(
            status: .unmeasured,
            bytesPerGesture: [],
            peakAllocationBytes: 0
        )
    }

    public func measureMemory(configuration: PerformanceConfiguration) -> MemoryMeasurement {
        MemoryMeasurement(
            status: .unmeasured,
            windowSeconds: configuration.memoryWindowSeconds,
            sampleIntervalSeconds: configuration.memorySampleIntervalSeconds,
            samples: [],
            aggregates: [],
            peakRSSBytes: 0,
            finalWindowDeltaBytes: 0,
            finalWindowDeltaPercent: 0,
            postWarmupSlopeBytesPerSecond: 0,
            matchedBaselineSeries: [],
            matchedBaselineValues: [],
            peakLiveResourceCounts: .zero,
            endLiveResourceCounts: .zero
        )
    }
}

@MainActor
private final class UnavailableRedrawLayoutAdapter: RedrawLayoutInstrumentationAdapter {
    func measureRedrawLayout(configuration: PerformanceConfiguration) -> RedrawLayoutMeasurement {
        RedrawLayoutMeasurement(status: .unmeasured, redrawsPerSample: [], layoutPasses: [], p95Milliseconds: 0)
    }
}

@MainActor
private final class UnavailableResponsivenessAdapter: ResponsivenessInstrumentationAdapter {
    func measureResponsiveness(configuration: PerformanceConfiguration) -> ResponsivenessMeasurement {
        ResponsivenessMeasurement(status: .unmeasured, stallCount: 0, maximumMainThreadStallMilliseconds: 0, p95ResponseMilliseconds: 0)
    }
}

@MainActor
private final class UnavailableInputToVisibleAdapter: InputToVisibleInstrumentationAdapter {
    func measureInputToVisible(configuration: PerformanceConfiguration) -> InputToVisibleMeasurement {
        InputToVisibleMeasurement(status: .unmeasured, sampleCount: 0, p95Milliseconds: 0, missedSampleCount: 0)
    }
}

@MainActor
private final class UnavailableResilienceAdapter: ResilienceInstrumentationAdapter {
    func measureResilience(configuration: PerformanceConfiguration) -> ResilienceMeasurement {
        ResilienceMeasurement(status: .unmeasured, cases: [], disposition: .blocked)
    }
}

private extension ResourceCounts {
    static let zero = ResourceCounts(overlays: 0, timers: 0, handlers: 0, windows: 0, observers: 0)
}
