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

internal struct RendererSemanticSnapshot: Equatable, Sendable {
    let profile: PerformanceFixtureProfile
    let renderPlanIdentity: String
    let committedMarkCount: Int
    let hasActiveDraft: Bool
    let positiveMarkOccupancy: [Int]
    let positiveMarkColorMatches: [Int]
    let negativeRegionOccupied: [Bool]
    let occupiedStrata: [Bool]
    let nonTransparentPixelCount: Int
    let occupiedQuadrantCount: Int
    let pixelChecksum: UInt64
    let boundsWidth: Int
    let boundsHeight: Int

    init(
        profile: PerformanceFixtureProfile = .standard12,
        renderPlanIdentity: String = "",
        committedMarkCount: Int,
        hasActiveDraft: Bool,
        positiveMarkOccupancy: [Int] = [],
        positiveMarkColorMatches: [Int] = [],
        negativeRegionOccupied: [Bool] = [],
        occupiedStrata: [Bool] = [],
        nonTransparentPixelCount: Int,
        occupiedQuadrantCount: Int,
        pixelChecksum: UInt64,
        boundsWidth: Int,
        boundsHeight: Int
    ) {
        self.profile = profile
        self.renderPlanIdentity = renderPlanIdentity
        self.committedMarkCount = committedMarkCount
        self.hasActiveDraft = hasActiveDraft
        self.positiveMarkOccupancy = positiveMarkOccupancy
        self.positiveMarkColorMatches = positiveMarkColorMatches
        self.negativeRegionOccupied = negativeRegionOccupied
        self.occupiedStrata = occupiedStrata
        self.nonTransparentPixelCount = nonTransparentPixelCount
        self.occupiedQuadrantCount = occupiedQuadrantCount
        self.pixelChecksum = pixelChecksum
        self.boundsWidth = boundsWidth
        self.boundsHeight = boundsHeight
    }
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

private enum PerformanceFixtureBuilder {
    static func session(
        display: DisplayUUID,
        profile: PerformanceFixtureProfile
    ) -> PointerSession {
        var session = PointerSession()
        let count = profile == .standard12 ? 12 : 1_000
        for index in 0..<count {
            session.apply(.append(mark(index: index, profile: profile), to: display))
        }
        return session
    }

    private static func mark(index: Int, profile: PerformanceFixtureProfile) -> Mark {
        let geometry: MarkGeometry
        switch profile {
        case .standard12:
            let column = index % 4
            let row = index / 4
            let start = NormalizedPoint(
                x: 0.05 + Double(column) * 0.22,
                y: 0.08 + Double(row) * 0.24
            )
            switch index % 3 {
            case 0:
                geometry = .arrow(
                    start: start,
                    end: NormalizedPoint(x: start.x + 0.1, y: start.y + 0.09)
                )
            case 1:
                geometry = .rectangle(
                    NormalizedRect(x: start.x, y: start.y, width: 0.12, height: 0.1)
                )
            default:
                geometry = .ellipse(
                    NormalizedRect(x: start.x, y: start.y, width: 0.12, height: 0.1)
                )
            }
        case .dense1000:
            let column = index % 50
            let row = index / 50
            let start = NormalizedPoint(
                x: 0.01 + Double(column) * 0.019,
                y: 0.04 + Double(row) * 0.045
            )
            switch index % 4 {
            case 0:
                geometry = .arrow(
                    start: start,
                    end: NormalizedPoint(x: start.x + 0.012, y: start.y + 0.01)
                )
            case 1:
                geometry = .rectangle(
                    NormalizedRect(x: start.x, y: start.y, width: 0.012, height: 0.012)
                )
            case 2:
                geometry = .ellipse(
                    NormalizedRect(x: start.x, y: start.y, width: 0.012, height: 0.012)
                )
            default:
                geometry = .freehand([
                    start,
                    NormalizedPoint(x: start.x + 0.006, y: start.y + 0.01),
                    NormalizedPoint(x: start.x + 0.012, y: start.y),
                ])
            }
        }
        let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!
        return Mark(id: id, geometry: geometry, style: .default)
    }
}

/// Runs one immutable measurement report. The public surface uses production
/// adapters; the internal bundle keeps unavailable OS instrumentation explicit
/// and makes deterministic adapter tests possible without faking application
/// input or replacing the PointerSession/CanvasView path.
@MainActor
public enum PerformanceHarness {
    internal typealias AdapterBundle = PerformanceHarnessAdapterBundle

    internal static func fixtureProfile(for configuration: PerformanceConfiguration) -> PerformanceFixtureProfile? {
        configuration.isCanonical ? configuration.fixtureProfile : nil
    }

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
        guard configuration.isCanonical else {
            throw PerformanceHarnessError.invalidInput(
                "public performance runs require a canonical performance configuration"
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
        guard configuration.isCanonical else {
            throw PerformanceHarnessError.invalidInput(
                "performance runs require a canonical performance configuration"
            )
        }
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
                identifier: configuration.fixtureProfile.identifier,
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
            disposition: .revise
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
            return .revise
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

    /// Measures one scalar trial. GestureBenchmark owns its five local
    /// warmups, so callers never run a thirty-trial batch and select a value.
    internal func measureSingleTrial(configuration: PerformanceConfiguration) -> ModelMeasurement {
        guard configuration.isCanonical else {
            return ModelMeasurement(
                status: .failed,
                trialNanoseconds: [],
                medianNanoseconds: 0,
                p95Nanoseconds: 0,
                madNanoseconds: 0,
                publicationCount: 0,
                modelChecksum: "unsupported-fixture-profile",
                finalStateValid: false
            )
        }
        if configuration.fixtureProfile == .dense1000 {
            return Self.measureDense(configuration: configuration, trialCount: 1)
        }
        let result = GestureBenchmark.run(
            trials: 1,
            samples: configuration.samplesPerGesture
        )
        return ModelMeasurement(
            status: result.trialNanoseconds.isEmpty
                ? .unmeasured
                : PerformanceHarness.modelStatus(
                    checksumIsStable: result.checksumIsStable,
                    finalStateValid: result.finalStateValid,
                    publicationsPerGesture: result.publicationsPerGesture,
                    expectedTrialCount: 1
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

    public func measureModel(configuration: PerformanceConfiguration) -> ModelMeasurement {
        guard configuration.isCanonical else {
            return ModelMeasurement(
                status: .failed,
                trialNanoseconds: [],
                medianNanoseconds: 0,
                p95Nanoseconds: 0,
                madNanoseconds: 0,
                publicationCount: 0,
                modelChecksum: "unsupported-fixture-profile",
                finalStateValid: false
            )
        }
        let profile = configuration.fixtureProfile
        if profile == .dense1000 {
            return Self.measureDense(configuration: configuration, trialCount: configuration.trialCount)
        }
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

    private static func measureDense(
        configuration: PerformanceConfiguration,
        trialCount: Int
    ) -> ModelMeasurement {
        var trialNanoseconds: [Double] = []
        var checksums: [String] = []
        var publicationCounts: [Int] = []
        var finalStateValid = true
        for _ in 0..<configuration.warmupCount {
            _ = denseMeasurement(configuration: configuration)
        }
        trialNanoseconds.reserveCapacity(trialCount)
        checksums.reserveCapacity(trialCount)
        publicationCounts.reserveCapacity(trialCount)
        for _ in 0..<trialCount {
            let measurement = denseMeasurement(configuration: configuration)
            trialNanoseconds.append(measurement.nanoseconds)
            checksums.append(measurement.checksum)
            publicationCounts.append(measurement.publications)
            finalStateValid = finalStateValid && measurement.finalStateValid
        }
        let checksum = checksums.first ?? "dense1000-empty"
        let stable = !trialNanoseconds.isEmpty
            && checksums.allSatisfy { $0 == checksum }
            && publicationCounts.count == trialCount
            && publicationCounts.allSatisfy { $0 == 2 }
        return ModelMeasurement(
            status: stable && finalStateValid ? .measured : .failed,
            trialNanoseconds: trialNanoseconds,
            medianNanoseconds: median(trialNanoseconds),
            p95Nanoseconds: nearestRankP95(trialNanoseconds),
            madNanoseconds: mad(trialNanoseconds),
            publicationCount: publicationCounts.first ?? 0,
            modelChecksum: checksum,
            finalStateValid: finalStateValid
        )
    }

    private struct DenseMeasurement {
        let nanoseconds: Double
        let checksum: String
        let publications: Int
        let finalStateValid: Bool
    }

    internal static func denseFreehandIsValid(_ mark: Mark, sampleCount: Int) -> Bool {
        guard sampleCount >= 0,
              mark.style == .default,
              case let .freehand(points) = mark.geometry,
              points.count == sampleCount + 1
        else {
            return false
        }
        let expectedPoints = (0...sampleCount).map { index in
            NormalizedPoint(
                x: 0.1 + Double(index) * 0.0005,
                y: 0.2 + (index.isMultiple(of: 2) ? 0 : 0.005)
            )
        }
        return points == expectedPoints
    }

    private static func denseMeasurement(configuration: PerformanceConfiguration) -> DenseMeasurement {
        let display = DisplayUUID(rawValue: "performance-dense-model")
        var session = PerformanceFixtureBuilder.session(display: display, profile: .dense1000)
        let fixture = session.canvas(for: display)
        let fixtureChecksum = checksum(for: fixture)
        let start = CACurrentMediaTime()
        let began = session.beginGesture(
            tool: .pen,
            at: NormalizedPoint(x: 0.1, y: 0.2),
            on: display
        )
        var publications = began.boundaryEvent == .began ? 1 : 0
        for index in 1...configuration.samplesPerGesture {
            _ = session.advanceGesture(
                to: NormalizedPoint(
                    x: 0.1 + Double(index) * 0.0005,
                    y: 0.2 + (index.isMultiple(of: 2) ? 0 : 0.005)
                )
            )
        }
        let committed = session.commitGesture()
        let end = CACurrentMediaTime()
        if committed.boundaryEvent == .committed {
            publications += 1
        }
        let canvas = session.canvas(for: display)
        let valid = committed.didMutate
            && canvas.marks.count == 1_001
            && session.hasActiveGesture(on: display) == false
            && canvas.marks.last.map {
                denseFreehandIsValid($0, sampleCount: configuration.samplesPerGesture)
            } == true
        let modelChecksum = checksum(for: canvas)
        session.apply(.undo(on: display))
        let restored = session.canvas(for: display) == fixture
            && checksum(for: session.canvas(for: display)) == fixtureChecksum
        return DenseMeasurement(
            nanoseconds: (end - start) * 1_000_000_000,
            checksum: modelChecksum,
            publications: publications,
            finalStateValid: valid && restored
        )
    }

    private static func checksum(for canvas: Canvas) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for mark in canvas.marks {
            update(&hash, geometryIdentity(mark.geometry))
            update(&hash, styleIdentity(mark.style))
        }
        return String(format: "%016llx", hash)
    }

    private static func update(_ hash: inout UInt64, _ value: String) {
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
    }

    private static func geometryIdentity(_ geometry: MarkGeometry) -> String {
        switch geometry {
        case let .arrow(start, end): return "arrow:\(pointIdentity(start)):\(pointIdentity(end))"
        case let .rectangle(rect): return "rectangle:\(rectIdentity(rect))"
        case let .ellipse(rect): return "ellipse:\(rectIdentity(rect))"
        case let .freehand(points): return "freehand:\(points.map(pointIdentity).joined(separator: ","))"
        case let .emoji(text, rect): return "emoji:\(text):\(rectIdentity(rect))"
        case let .spotlight(center, radius, dimness): return "spotlight:\(pointIdentity(center)):\(unitIdentity(radius)):\(unitIdentity(dimness))"
        }
    }

    private static func pointIdentity(_ point: NormalizedPoint) -> String {
        "\(unitIdentity(point.x)),\(unitIdentity(point.y))"
    }

    private static func rectIdentity(_ rect: NormalizedRect) -> String {
        "\(unitIdentity(rect.x)),\(unitIdentity(rect.y)),\(unitIdentity(rect.width)),\(unitIdentity(rect.height))"
    }

    private static func styleIdentity(_ style: MarkStyle) -> String {
        "\(unitIdentity(style.color.red)),\(unitIdentity(style.color.green)),\(unitIdentity(style.color.blue)),\(unitIdentity(style.color.alpha));\(unitIdentity(style.strokeWidth));\(unitIdentity(style.opacity))"
    }

    private static func unitIdentity(_ value: Double) -> String {
        String(Int((value * 1_000_000).rounded()))
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }

    private static func nearestRankP95(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let rank = max(1, Int(ceil(0.95 * Double(sorted.count))))
        return sorted[rank - 1]
    }

    private static func mad(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let center = median(values)
        return median(values.map { abs($0 - center) })
    }
}

@MainActor
public final class OffscreenCanvasRendererAdapter: RendererInstrumentationAdapter {
    public init() {}

    private struct SemanticProbe {
        let positivePoints: [CGPoint]
        let negativeRegions: [CGRect]
        let minimumPositiveHits: Int
    }

    private static let canonicalFixtureMarkCount = 12
    private static let canonicalRenderPlanIdentity = [
        "state=display=performance-render-display|mode=standby|canvasTool=select|sessionTool=arrow|toolStyle=rgba=1000000,0,0,1000000;stroke=4000000;opacity=1000000|emoji=👉|spotlight=150000,500000|selection=none|selectedDisplay=none|activeGesture=0|cursor=clickThrough",
        "committed=id=00000000-0000-0000-0000-000000000001,geometry=arrow:50000,80000:150000,170000,style=rgba=1000000,0,0,1000000;stroke=4000000;opacity=1000000;id=00000000-0000-0000-0000-000000000002,geometry=rectangle:270000,80000,120000,100000,style=rgba=1000000,0,0,1000000;stroke=4000000;opacity=1000000;id=00000000-0000-0000-0000-000000000003,geometry=ellipse:490000,80000,120000,100000,style=rgba=1000000,0,0,1000000;stroke=4000000;opacity=1000000;id=00000000-0000-0000-0000-000000000004,geometry=arrow:710000,80000:810000,170000,style=rgba=1000000,0,0,1000000;stroke=4000000;opacity=1000000;id=00000000-0000-0000-0000-000000000005,geometry=rectangle:50000,320000,120000,100000,style=rgba=1000000,0,0,1000000;stroke=4000000;opacity=1000000;id=00000000-0000-0000-0000-000000000006,geometry=ellipse:270000,320000,120000,100000,style=rgba=1000000,0,0,1000000;stroke=4000000;opacity=1000000;id=00000000-0000-0000-0000-000000000007,geometry=arrow:490000,320000:590000,410000,style=rgba=1000000,0,0,1000000;stroke=4000000;opacity=1000000;id=00000000-0000-0000-0000-000000000008,geometry=rectangle:710000,320000,120000,100000,style=rgba=1000000,0,0,1000000;stroke=4000000;opacity=1000000;id=00000000-0000-0000-0000-000000000009,geometry=ellipse:50000,560000,120000,100000,style=rgba=1000000,0,0,1000000;stroke=4000000;opacity=1000000;id=00000000-0000-0000-0000-000000000010,geometry=arrow:270000,560000:370000,650000,style=rgba=1000000,0,0,1000000;stroke=4000000;opacity=1000000;id=00000000-0000-0000-0000-000000000011,geometry=rectangle:490000,560000,120000,100000,style=rgba=1000000,0,0,1000000;stroke=4000000;opacity=1000000;id=00000000-0000-0000-0000-000000000012,geometry=ellipse:710000,560000,120000,100000,style=rgba=1000000,0,0,1000000;stroke=4000000;opacity=1000000",
        "draft=none",
        "handles=selection=none,0|hover=none,0|resize=0,|delete=0",
    ].joined(separator: "|")
    private static let canonicalNegativeRegionCount = 27

    private static let canonicalPositiveProbes: [SemanticProbe] = [
        SemanticProbe(positivePoints: [CGPoint(x: 0.10, y: 0.125), CGPoint(x: 0.15, y: 0.17)], negativeRegions: [CGRect(x: 0.06, y: 0.13, width: 0.02, height: 0.02), CGRect(x: 0.13, y: 0.11, width: 0.02, height: 0.02)], minimumPositiveHits: 2),
        SemanticProbe(positivePoints: [CGPoint(x: 0.33, y: 0.08), CGPoint(x: 0.39, y: 0.13), CGPoint(x: 0.33, y: 0.18), CGPoint(x: 0.27, y: 0.13)], negativeRegions: [CGRect(x: 0.32, y: 0.12, width: 0.02, height: 0.02), CGRect(x: 0.32, y: 0.045, width: 0.02, height: 0.02)], minimumPositiveHits: 4),
        SemanticProbe(positivePoints: [CGPoint(x: 0.55, y: 0.08), CGPoint(x: 0.61, y: 0.13), CGPoint(x: 0.55, y: 0.18), CGPoint(x: 0.49, y: 0.13)], negativeRegions: [CGRect(x: 0.54, y: 0.12, width: 0.02, height: 0.02), CGRect(x: 0.435, y: 0.12, width: 0.02, height: 0.02), CGRect(x: 0.54, y: 0.045, width: 0.02, height: 0.02)], minimumPositiveHits: 4),
        SemanticProbe(positivePoints: [CGPoint(x: 0.76, y: 0.125), CGPoint(x: 0.81, y: 0.17)], negativeRegions: [CGRect(x: 0.72, y: 0.13, width: 0.02, height: 0.02), CGRect(x: 0.79, y: 0.11, width: 0.02, height: 0.02)], minimumPositiveHits: 2),
        SemanticProbe(positivePoints: [CGPoint(x: 0.11, y: 0.32), CGPoint(x: 0.17, y: 0.37), CGPoint(x: 0.11, y: 0.42), CGPoint(x: 0.05, y: 0.37)], negativeRegions: [CGRect(x: 0.10, y: 0.36, width: 0.02, height: 0.02), CGRect(x: 0.10, y: 0.285, width: 0.02, height: 0.02)], minimumPositiveHits: 4),
        SemanticProbe(positivePoints: [CGPoint(x: 0.33, y: 0.32), CGPoint(x: 0.39, y: 0.37), CGPoint(x: 0.33, y: 0.42), CGPoint(x: 0.27, y: 0.37)], negativeRegions: [CGRect(x: 0.32, y: 0.36, width: 0.02, height: 0.02), CGRect(x: 0.32, y: 0.285, width: 0.02, height: 0.02)], minimumPositiveHits: 4),
        SemanticProbe(positivePoints: [CGPoint(x: 0.54, y: 0.365), CGPoint(x: 0.59, y: 0.41)], negativeRegions: [CGRect(x: 0.50, y: 0.38, width: 0.02, height: 0.02), CGRect(x: 0.57, y: 0.35, width: 0.02, height: 0.02)], minimumPositiveHits: 2),
        SemanticProbe(positivePoints: [CGPoint(x: 0.77, y: 0.32), CGPoint(x: 0.83, y: 0.37), CGPoint(x: 0.77, y: 0.42), CGPoint(x: 0.71, y: 0.37)], negativeRegions: [CGRect(x: 0.76, y: 0.36, width: 0.02, height: 0.02), CGRect(x: 0.76, y: 0.285, width: 0.02, height: 0.02)], minimumPositiveHits: 4),
        SemanticProbe(positivePoints: [CGPoint(x: 0.11, y: 0.56), CGPoint(x: 0.17, y: 0.61), CGPoint(x: 0.11, y: 0.66), CGPoint(x: 0.05, y: 0.61)], negativeRegions: [CGRect(x: 0.10, y: 0.60, width: 0.02, height: 0.02), CGRect(x: 0.10, y: 0.525, width: 0.02, height: 0.02), CGRect(x: 0.02, y: 0.58, width: 0.02, height: 0.02)], minimumPositiveHits: 4),
        SemanticProbe(positivePoints: [CGPoint(x: 0.32, y: 0.605), CGPoint(x: 0.37, y: 0.65)], negativeRegions: [CGRect(x: 0.28, y: 0.62, width: 0.02, height: 0.02), CGRect(x: 0.35, y: 0.59, width: 0.02, height: 0.02)], minimumPositiveHits: 2),
        SemanticProbe(positivePoints: [CGPoint(x: 0.55, y: 0.56), CGPoint(x: 0.61, y: 0.61), CGPoint(x: 0.55, y: 0.66), CGPoint(x: 0.49, y: 0.61)], negativeRegions: [CGRect(x: 0.54, y: 0.60, width: 0.02, height: 0.02), CGRect(x: 0.54, y: 0.525, width: 0.02, height: 0.02)], minimumPositiveHits: 4),
        SemanticProbe(positivePoints: [CGPoint(x: 0.77, y: 0.56), CGPoint(x: 0.83, y: 0.61), CGPoint(x: 0.77, y: 0.66), CGPoint(x: 0.71, y: 0.61)], negativeRegions: [CGRect(x: 0.76, y: 0.60, width: 0.02, height: 0.02), CGRect(x: 0.76, y: 0.525, width: 0.02, height: 0.02), CGRect(x: 0.67, y: 0.58, width: 0.02, height: 0.02)], minimumPositiveHits: 4),
    ]
    private static let canonicalMinimumPositiveHits = canonicalPositiveProbes.map(\.minimumPositiveHits)
    private static let canonicalDenseRenderPlanIdentity = "dense1000|planDigest=cd81b9529b3682d5"
    private static let densePositiveProbes = makeDensePositiveProbes()
    private static let denseMinimumPositiveHits = densePositiveProbes.map(\.minimumPositiveHits)
    private static let denseNegativeRegionCount = densePositiveProbes
        .reduce(0) { $0 + $1.negativeRegions.count }
    private static let denseStratumCount = 16

    private static func makeDensePositiveProbes() -> [SemanticProbe] {
        (0..<1_000).map { index in
            let column = index % 50
            let row = index / 50
            let x = 0.01 + Double(column) * 0.019
            let y = 0.04 + Double(row) * 0.045
            let positivePoints: [CGPoint]
            let negativeRegions: [CGRect]
            switch index % 4 {
            case 0:
                positivePoints = [CGPoint(x: x + 0.006, y: y + 0.005)]
                negativeRegions = index == 0
                    ? [
                        CGRect(x: 0.012, y: 0.067, width: 0.006, height: 0.004),
                        CGRect(x: 0.012, y: 0.015, width: 0.006, height: 0.004),
                    ]
                    : []
            case 1:
                positivePoints = [CGPoint(x: x + 0.006, y: y)]
                negativeRegions = index == 1
                    ? [
                        CGRect(x: 0.031, y: 0.067, width: 0.006, height: 0.004),
                        CGRect(x: 0.031, y: 0.015, width: 0.006, height: 0.004),
                    ]
                    : []
            case 2:
                positivePoints = [CGPoint(x: x + 0.006, y: y)]
                negativeRegions = index == 2
                    ? [
                        CGRect(x: 0.050, y: 0.020, width: 0.006, height: 0.004),
                        CGRect(x: 0.025, y: 0.020, width: 0.004, height: 0.004),
                        CGRect(x: 0.050, y: 0.001, width: 0.006, height: 0.004),
                    ]
                    : []
            default:
                positivePoints = [CGPoint(x: x + 0.006, y: y + 0.01)]
                negativeRegions = index == 3
                    ? [
                        CGRect(x: 0.069, y: 0.067, width: 0.006, height: 0.004),
                        CGRect(x: 0.069, y: 0.015, width: 0.006, height: 0.004),
                    ]
                    : []
            }
            return SemanticProbe(
                positivePoints: positivePoints,
                negativeRegions: negativeRegions,
                minimumPositiveHits: 1
            )
        }
    }

    internal static func semanticStatus(
        _ snapshot: RendererSemanticSnapshot
    ) -> MeasurementStatus {
        let expectedMarkCount: Int
        let expectedPlanIdentity: String
        let expectedMinimumHits: [Int]
        let expectedNegativeRegionCount: Int
        let expectedStrataCount: Int
        switch snapshot.profile {
        case .standard12:
            expectedMarkCount = canonicalFixtureMarkCount
            expectedPlanIdentity = canonicalRenderPlanIdentity
            expectedMinimumHits = canonicalMinimumPositiveHits
            expectedNegativeRegionCount = canonicalNegativeRegionCount
            expectedStrataCount = 0
        case .dense1000:
            expectedMarkCount = 1_000
            expectedPlanIdentity = canonicalDenseRenderPlanIdentity
            expectedMinimumHits = denseMinimumPositiveHits
            expectedNegativeRegionCount = denseNegativeRegionCount
            expectedStrataCount = denseStratumCount
        }
        guard snapshot.committedMarkCount == expectedMarkCount,
              !snapshot.hasActiveDraft,
              snapshot.renderPlanIdentity == expectedPlanIdentity,
              snapshot.boundsWidth == 512,
              snapshot.boundsHeight == 512,
              snapshot.nonTransparentPixelCount > 0,
              snapshot.occupiedQuadrantCount >= 4,
              snapshot.positiveMarkOccupancy.count == expectedMinimumHits.count,
              zip(snapshot.positiveMarkOccupancy, expectedMinimumHits)
                  .allSatisfy({ $0 >= $1 }),
              snapshot.positiveMarkColorMatches.count == expectedMinimumHits.count,
              zip(snapshot.positiveMarkColorMatches, expectedMinimumHits)
                  .allSatisfy({ $0 >= $1 }),
              snapshot.negativeRegionOccupied.count == expectedNegativeRegionCount,
              snapshot.negativeRegionOccupied.allSatisfy({ !$0 }),
              snapshot.occupiedStrata.count == expectedStrataCount,
              snapshot.occupiedStrata.allSatisfy({ $0 })
        else {
            return .failed
        }
        return .measured
    }

    internal static func semanticRasterStatus(
        before: RendererSemanticSnapshot,
        after: RendererSemanticSnapshot
    ) -> MeasurementStatus {
        guard before.profile == after.profile,
              semanticStatus(before) == .measured,
              semanticStatus(after) == .measured,
              before.pixelChecksum == after.pixelChecksum
        else {
            return .failed
        }
        return .measured
    }

    public func measureRenderer(configuration: PerformanceConfiguration) -> FrameMeasurement {
        measureRenderer(configuration: configuration, sampleCount: configuration.trialCount)
    }

    /// Measures one renderer scalar after five local warmups. This seam is
    /// used by the paired trial runner and intentionally does not call the
    /// thirty-sample production method.
    internal func measureSingleTrial(configuration: PerformanceConfiguration) -> FrameMeasurement {
        measureRenderer(configuration: configuration, sampleCount: 1)
    }

    private func measureRenderer(
        configuration: PerformanceConfiguration,
        sampleCount: Int
    ) -> FrameMeasurement {
        guard sampleCount > 0 else {
            return Self.unmeasured("offscreen-canvasview-invalid-trial-count")
        }
        _ = NSApplication.shared

        let display = DisplayUUID(rawValue: "performance-render-display")
        let frame = NSRect(x: 0, y: 0, width: 512, height: 512)
        guard configuration.isCanonical else {
            return Self.failed("offscreen-canvasview-unsupported-fixture-profile")
        }
        let profile = configuration.fixtureProfile
        let session = Self.fixtureSession(display: display, profile: profile)
        let view = CanvasView(frame: frame, display: display, session: session, tool: .select)
        let window = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: true
        )
        window.contentView = view
        defer { window.contentView = nil }

        let bitmapByteCount = 512 * 512 * 4
        let bitmap = UnsafeMutableRawPointer.allocate(
            byteCount: bitmapByteCount,
            alignment: MemoryLayout<UInt8>.alignment
        )
        bitmap.initializeMemory(as: UInt8.self, repeating: 0, count: bitmapByteCount)
        defer { bitmap.deallocate() }

        guard let sRGBColorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            return Self.failed("offscreen-canvasview-srgb-colorspace-unavailable")
        }
        guard let context = CGContext(
            data: bitmap,
            width: 512,
            height: 512,
            bitsPerComponent: 8,
            bytesPerRow: 512 * 4,
            space: sRGBColorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return Self.unmeasured("offscreen-canvasview-context-unavailable")
        }

        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        func prepareBitmap() {
            context.clear(frame)
        }
        func renderIntoBitmap() {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphicsContext
            view.draw(frame)
            NSGraphicsContext.restoreGraphicsState()
        }

        prepareBitmap()
        renderIntoBitmap()
        let beforeTiming = Self.semanticSnapshot(
            view: view,
            profile: profile,
            bitmap: bitmap,
            width: 512,
            height: 512
        )
        guard Self.semanticStatus(
            beforeTiming
        ) == .measured else {
            return Self.failed("offscreen-canvasview-semantic-preflight-failed")
        }

        for _ in 0..<configuration.warmupCount {
            prepareBitmap()
            renderIntoBitmap()
        }
        var samples: [Double] = []
        samples.reserveCapacity(sampleCount)
        if sampleCount == configuration.trialCount {
            for _ in 0..<configuration.trialCount {
                prepareBitmap()
                let start = CACurrentMediaTime()
                renderIntoBitmap()
                samples.append((CACurrentMediaTime() - start) * 1_000)
            }
        } else {
            for _ in 0..<sampleCount {
                prepareBitmap()
                let start = CACurrentMediaTime()
                renderIntoBitmap()
                samples.append((CACurrentMediaTime() - start) * 1_000)
            }
        }
        guard samples.allSatisfy({ $0.isFinite && $0 > 0 }) else {
            return Self.failed("offscreen-canvasview-invalid-sample")
        }
        let afterTiming = Self.semanticSnapshot(
            view: view,
            profile: profile,
            bitmap: bitmap,
            width: 512,
            height: 512
        )
        guard Self.semanticRasterStatus(before: beforeTiming, after: afterTiming) == .measured else {
            return Self.failed("offscreen-canvasview-semantic-postflight-failed")
        }
        return FrameMeasurement(
            status: .measured,
            sampleCount: samples.count,
            p95Milliseconds: Self.nearestRankP95(samples),
            frameMilliseconds: samples,
            frameCount: samples.count,
            missedFrameCount: samples.filter { $0 > 16.7 }.count,
            instrumentationStatus: "offscreen-canvasview-cgcontext-semantic-\(profile.rawValue)"
        )
    }

    internal static func fixtureSession(
        display: DisplayUUID,
        profile: PerformanceFixtureProfile
    ) -> PointerSession {
        PerformanceFixtureBuilder.session(display: display, profile: profile)
    }

    internal static func semanticSnapshot(
        view: CanvasView,
        profile: PerformanceFixtureProfile,
        bitmap: UnsafeRawPointer,
        width: Int,
        height: Int
    ) -> RendererSemanticSnapshot {
        let alphaThreshold: UInt8 = 32
        var nonTransparentPixelCount = 0
        var occupiedQuadrants = Set<Int>()
        var occupiedStrata = Array(repeating: false, count: denseStratumCount)
        var checksum: UInt64 = 14_695_981_039_346_656_037
        let byteCount = width * height * 4
        for offset in 0..<byteCount {
            let byte = bitmap.load(fromByteOffset: offset, as: UInt8.self)
            checksum ^= UInt64(byte)
            checksum &*= 1_099_511_628_211
        }
        for pixelIndex in 0..<(width * height) {
            let alpha = bitmap.load(
                fromByteOffset: pixelIndex * 4 + 3,
                as: UInt8.self
            )
            guard alpha > 0 else { continue }
            nonTransparentPixelCount += 1
            let x = pixelIndex % width
            let y = pixelIndex / width
            occupiedQuadrants.insert((x / (width / 2)) + 2 * (y / (height / 2)))
            let stratumX = min(3, (x * 4) / width)
            let stratumY = min(3, (y * 4) / height)
            occupiedStrata[stratumX + 4 * stratumY] = true
        }
        let probes = profile == .standard12 ? canonicalPositiveProbes : densePositiveProbes
        let positiveMarkOccupancy = probes.map { probe in
            probe.positivePoints.filter {
                probeHit(
                    at: $0,
                    bitmap: bitmap,
                    width: width,
                    height: height,
                    alphaThreshold: alphaThreshold,
                    expectedColor: MarkStyle.default.color
                ) != .none
            }.count
        }
        let positiveMarkColorMatches = probes.map { probe in
            probe.positivePoints.filter {
                probeHit(
                    at: $0,
                    bitmap: bitmap,
                    width: width,
                    height: height,
                    alphaThreshold: alphaThreshold,
                    expectedColor: MarkStyle.default.color
                ) == .colorMatched
            }.count
        }
        let negativeRegionOccupied = probes.flatMap { probe in
            probe.negativeRegions.map { region in
                occupiedPixels(
                    in: CGRect(
                        x: region.minX,
                        y: 1 - region.maxY,
                        width: region.width,
                        height: region.height
                    ),
                    bitmap: bitmap,
                    width: width,
                    height: height,
                    alphaThreshold: alphaThreshold
                ) > 0
            }
        }
        return RendererSemanticSnapshot(
            profile: profile,
            renderPlanIdentity: renderPlanIdentity(for: view, profile: profile),
            committedMarkCount: view.renderPlan.committedMarks.count,
            hasActiveDraft: view.renderPlan.activeDraft != nil,
            positiveMarkOccupancy: positiveMarkOccupancy,
            positiveMarkColorMatches: positiveMarkColorMatches,
            negativeRegionOccupied: negativeRegionOccupied,
            occupiedStrata: profile == .dense1000 ? occupiedStrata : [],
            nonTransparentPixelCount: nonTransparentPixelCount,
            occupiedQuadrantCount: occupiedQuadrants.count,
            pixelChecksum: checksum,
            boundsWidth: Int(view.bounds.width),
            boundsHeight: Int(view.bounds.height)
        )
    }

    private static func occupiedPixels(
        in normalizedRegion: CGRect,
        bitmap: UnsafeRawPointer,
        width: Int,
        height: Int,
        alphaThreshold: UInt8
    ) -> Int {
        let minX = max(0, Int(floor(normalizedRegion.minX * CGFloat(width))))
        let maxX = min(width, Int(ceil(normalizedRegion.maxX * CGFloat(width))))
        let minY = max(0, Int(floor(normalizedRegion.minY * CGFloat(height))))
        let maxY = min(height, Int(ceil(normalizedRegion.maxY * CGFloat(height))))
        guard minX < maxX, minY < maxY else { return 0 }
        var count = 0
        for y in minY..<maxY {
            for x in minX..<maxX {
                let offset = (y * width + x) * 4 + 3
                if bitmap.load(fromByteOffset: offset, as: UInt8.self) > alphaThreshold {
                    count += 1
                }
            }
        }
        return count
    }

    private enum ProbeHit {
        case none
        case alphaOnly
        case colorMatched
    }

    private static func probeHit(
        at normalizedPoint: CGPoint,
        bitmap: UnsafeRawPointer,
        width: Int,
        height: Int,
        alphaThreshold: UInt8,
        expectedColor: RGBAColor
    ) -> ProbeHit {
        let centerX = Int((normalizedPoint.x * CGFloat(width)).rounded())
        let centerY = Int(((1 - normalizedPoint.y) * CGFloat(height)).rounded())
        let radius = 4
        var sawAlpha = false
        for y in max(0, centerY - radius)...min(height - 1, centerY + radius) {
            for x in max(0, centerX - radius)...min(width - 1, centerX + radius) {
                let offset = (y * width + x) * 4
                let red = bitmap.load(fromByteOffset: offset, as: UInt8.self)
                let green = bitmap.load(fromByteOffset: offset + 1, as: UInt8.self)
                let blue = bitmap.load(fromByteOffset: offset + 2, as: UInt8.self)
                let alpha = bitmap.load(fromByteOffset: offset + 3, as: UInt8.self)
                guard alpha > alphaThreshold else { continue }
                sawAlpha = true
                let expectedRed = UInt8((expectedColor.red * 255).rounded())
                let expectedGreen = UInt8((expectedColor.green * 255).rounded())
                let expectedBlue = UInt8((expectedColor.blue * 255).rounded())
                let colorTolerance: UInt8 = 48
                if abs(Int(red) - Int(expectedRed)) <= Int(colorTolerance),
                   abs(Int(green) - Int(expectedGreen)) <= Int(colorTolerance),
                   abs(Int(blue) - Int(expectedBlue)) <= Int(colorTolerance),
                   alpha >= UInt8((expectedColor.alpha * 255 * 0.65).rounded()) {
                    return .colorMatched
                }
            }
        }
        return sawAlpha ? .alphaOnly : .none
    }

    private static func renderPlanIdentity(
        for view: CanvasView,
        profile: PerformanceFixtureProfile
    ) -> String {
        let session = view.session
        let plan = view.renderPlan
        let state = [
            "display=\(view.display.rawValue)",
            "mode=\(modeIdentity(session.mode))",
            "canvasTool=\(toolIdentity(view.tool))",
            "sessionTool=\(toolIdentity(session.toolState.tool))",
            "toolStyle=\(styleIdentity(session.toolState.style))",
            "emoji=\(session.toolState.emoji)",
            "spotlight=\(unitIdentity(session.toolState.spotlightRadius)),\(unitIdentity(session.toolState.spotlightDimness))",
            "selection=\(identifierIdentity(session.selection))",
            "selectedDisplay=\(session.selectedDisplay?.rawValue ?? "none")",
            "activeGesture=\(session.hasActiveGesture(on: view.display) ? 1 : 0)",
            "cursor=\(cursorIdentity(view.cursorPlan))",
        ].joined(separator: "|")
        let handles = [
            "selection=\(identifierIdentity(plan.handles.selection.selectedMarkID)),\(plan.handles.selection.isVisible ? 1 : 0)",
            "hover=\(identifierIdentity(plan.handles.hover.hoveredMarkID)),\(plan.handles.hover.isVisible ? 1 : 0)",
            "resize=\(plan.handles.resize.isVisible ? 1 : 0),\(plan.handles.resize.handles.map(handleIdentity).joined(separator: ","))",
            "delete=\(plan.handles.contextualDeleteVisible ? 1 : 0)",
        ].joined(separator: "|")
        let serialized = [
            "state=\(state)",
            "committed=\(plan.committedMarks.map(markIdentity).joined(separator: ";"))",
            "draft=\(plan.activeDraft.map(markIdentity) ?? "none")",
            "handles=\(handles)",
        ].joined(separator: "|")
        switch profile {
        case .standard12:
            return serialized
        case .dense1000:
            return "dense1000|planDigest=\(planDigest(serialized))"
        }
    }

    private static func planDigest(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }

    private static func markIdentity(_ mark: Mark) -> String {
        "id=\(mark.id.uuidString.lowercased()),geometry=\(geometryIdentity(mark.geometry)),style=\(styleIdentity(mark.style))"
    }

    private static func geometryIdentity(_ geometry: MarkGeometry) -> String {
        switch geometry {
        case let .arrow(start, end):
            return "arrow:\(pointIdentity(start)):\(pointIdentity(end))"
        case let .rectangle(rect):
            return "rectangle:\(rectIdentity(rect))"
        case let .ellipse(rect):
            return "ellipse:\(rectIdentity(rect))"
        case let .freehand(points):
            return "freehand:\(points.map(pointIdentity).joined(separator: ","))"
        case let .emoji(text, rect):
            return "emoji:\(text):\(rectIdentity(rect))"
        case let .spotlight(center, radius, dimness):
            return "spotlight:\(pointIdentity(center)):\(unitIdentity(radius)):\(unitIdentity(dimness))"
        }
    }

    private static func pointIdentity(_ point: NormalizedPoint) -> String {
        "\(unitIdentity(point.x)),\(unitIdentity(point.y))"
    }

    private static func rectIdentity(_ rect: NormalizedRect) -> String {
        "\(unitIdentity(rect.x)),\(unitIdentity(rect.y)),\(unitIdentity(rect.width)),\(unitIdentity(rect.height))"
    }

    private static func unitIdentity(_ value: Double) -> String {
        String(Int((value * 1_000_000).rounded()))
    }

    private static func identifierIdentity(_ identifier: Mark.ID?) -> String {
        identifier?.uuidString.lowercased() ?? "none"
    }

    private static func styleIdentity(_ style: MarkStyle) -> String {
        "rgba=\(unitIdentity(style.color.red)),\(unitIdentity(style.color.green)),\(unitIdentity(style.color.blue)),\(unitIdentity(style.color.alpha));stroke=\(unitIdentity(style.strokeWidth));opacity=\(unitIdentity(style.opacity))"
    }

    private static func modeIdentity(_ mode: PointerMode) -> String {
        switch mode {
        case .standby: return "standby"
        case .annotation: return "annotation"
        }
    }

    private static func toolIdentity(_ tool: PointerTool) -> String {
        switch tool {
        case .select: return "select"
        case .arrow: return "arrow"
        case .rectangle: return "rectangle"
        case .ellipse: return "ellipse"
        case .pen: return "pen"
        case .eraser: return "eraser"
        case .emoji: return "emoji"
        case .spotlight: return "spotlight"
        }
    }

    private static func cursorIdentity(_ plan: CanvasView.CursorPlan) -> String {
        switch plan {
        case .clickThrough: return "clickThrough"
        case .select: return "select"
        case .draw: return "draw"
        case .erase: return "erase"
        case .emoji: return "emoji"
        case .spotlight: return "spotlight"
        }
    }

    private static func handleIdentity(_ handle: ResizeHandle) -> String {
        switch handle {
        case .arrowStart: return "arrowStart"
        case .arrowEnd: return "arrowEnd"
        case .topLeft: return "topLeft"
        case .topCenter: return "topCenter"
        case .topRight: return "topRight"
        case .middleLeft: return "middleLeft"
        case .middleRight: return "middleRight"
        case .bottomLeft: return "bottomLeft"
        case .bottomCenter: return "bottomCenter"
        case .bottomRight: return "bottomRight"
        case .spotlightCenter: return "spotlightCenter"
        case .spotlightRadius: return "spotlightRadius"
        }
    }

    private static func failed(_ reason: String) -> FrameMeasurement {
        FrameMeasurement(
            status: .failed,
            sampleCount: 0,
            p95Milliseconds: 0,
            frameMilliseconds: [],
            frameCount: 0,
            missedFrameCount: 0,
            instrumentationStatus: reason
        )
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
        ResilienceMeasurement(status: .unmeasured, cases: [], disposition: .revise)
    }
}

private extension ResourceCounts {
    static let zero = ResourceCounts(overlays: 0, timers: 0, handlers: 0, windows: 0, observers: 0)
}
