import Foundation
import PointerCore

/// Measures the production transactional gesture path without involving AppKit
/// rendering, event dispatch, or WindowServer composition.
public enum GestureBenchmark {
    public struct Result: Codable, Sendable {
        public let fixtureMarkCount: Int
        public let samplesPerGesture: Int
        public let buildConfiguration: String
        public let trialCount: Int
        public let warmupCount: Int
        public let trialNanoseconds: [Double]
        public let medianNanoseconds: Double
        public let p95Nanoseconds: Double
        public let madNanoseconds: Double
        public let publicationsPerGesture: [Int]
        public let modelChecksum: String
        public let checksumIsStable: Bool
        public let finalStateValid: Bool
        public let rendererTimed: Bool
        public let compositorTimed: Bool

        fileprivate init(
            fixtureMarkCount: Int,
            samplesPerGesture: Int,
            trialCount: Int,
            warmupCount: Int,
            trialNanoseconds: [Double],
            publicationsPerGesture: [Int],
            modelChecksum: String,
            checksumIsStable: Bool,
            finalStateValid: Bool
        ) {
            self.fixtureMarkCount = fixtureMarkCount
            self.samplesPerGesture = samplesPerGesture
            #if DEBUG
            buildConfiguration = "debug"
            #else
            buildConfiguration = "release"
            #endif
            self.trialCount = trialCount
            self.warmupCount = warmupCount
            self.trialNanoseconds = trialNanoseconds
            medianNanoseconds = GestureBenchmark.median(trialNanoseconds)
            p95Nanoseconds = GestureBenchmark.p95(trialNanoseconds)
            madNanoseconds = GestureBenchmark.mad(trialNanoseconds)
            self.publicationsPerGesture = publicationsPerGesture
            self.modelChecksum = modelChecksum
            self.checksumIsStable = checksumIsStable
            self.finalStateValid = finalStateValid
            rendererTimed = false
            compositorTimed = false
        }
    }

    private struct Measurement {
        let nanoseconds: Double
        let publications: Int
        let checksum: String
        let finalStateValid: Bool
    }

    private static let fixtureDisplay = DisplayUUID(rawValue: "benchmark-display")
    private static let fixtureMarkCount = 12
    private static let warmupCount = 5
    private static let expectedModelChecksum = "882b4fb5d86096de"

    /// Runs five warmups and the requested number of measured gestures.
    ///
    /// Each gesture starts from twelve committed marks and appends one
    /// freehand mark through `PointerSession`'s production begin/advance/commit
    /// APIs. Only the gesture model path is timed.
    public static func run(trials: Int = 30, samples: Int = 240) -> Result {
        precondition(trials > 0, "Gesture benchmark requires at least one trial.")
        precondition(samples > 0, "Gesture benchmark requires at least one sample.")

        for _ in 0..<warmupCount {
            _ = measure(samples: samples)
        }

        var measurements: [Measurement] = []
        measurements.reserveCapacity(trials)
        for _ in 0..<trials {
            measurements.append(measure(samples: samples))
        }

        let trialNanoseconds = measurements.map(\.nanoseconds)
        let publications = measurements.map(\.publications)
        let checksums = measurements.map(\.checksum)
        let modelChecksum = checksums[0]
        let checksumIsStable = samples == 240
            && modelChecksum == expectedModelChecksum
            && checksums.allSatisfy { $0 == modelChecksum }
            && publications.allSatisfy { $0 == 2 }
        let finalStateValid = measurements.allSatisfy(\.finalStateValid)

        return Result(
            fixtureMarkCount: fixtureMarkCount,
            samplesPerGesture: samples,
            trialCount: trials,
            warmupCount: warmupCount,
            trialNanoseconds: trialNanoseconds,
            publicationsPerGesture: publications,
            modelChecksum: modelChecksum,
            checksumIsStable: checksumIsStable,
            finalStateValid: finalStateValid
        )
    }

    private static func measure(samples: Int) -> Measurement {
        var session = PointerSession()
        let fixtureMarks = makeFixture()
        for mark in fixtureMarks {
            session.apply(.append(mark, to: fixtureDisplay))
        }
        let fixture = session.canvas(for: fixtureDisplay)
        let fixtureChecksum = checksum(for: session.canvas(for: fixtureDisplay))

        let clock = ContinuousClock()
        let wholeStart = clock.now
        let began = session.beginGesture(
            tool: .pen,
            at: NormalizedPoint(x: 0.05, y: 0.2),
            on: fixtureDisplay
        )
        var publications = began.boundaryEvent == .began ? 1 : 0
        let continuationStart = clock.now
        for index in 1...samples {
            _ = session.advanceGesture(
                to: NormalizedPoint(
                    x: 0.05 + Double(index) * 0.0025,
                    y: 0.2 + (index.isMultiple(of: 2) ? 0 : 0.02)
                )
            )
        }
        let continuationEnd = clock.now
        let committed = session.commitGesture()
        if committed.boundaryEvent == .committed {
            publications += 1
        }
        let wholeEnd = clock.now

        let canvas = session.canvas(for: fixtureDisplay)
        let finalStateValid = validate(
            canvas: canvas,
            samples: samples,
            session: &session,
            fixture: fixture,
            fixtureChecksum: fixtureChecksum
        )

        return Measurement(
            nanoseconds: nanoseconds(from: wholeStart.duration(to: wholeEnd)),
            publications: publications,
            checksum: checksum(for: canvas),
            finalStateValid: finalStateValid
                && nanoseconds(from: continuationStart.duration(to: continuationEnd)) > 0
        )
    }

    private static func makeFixture() -> [Mark] {
        var marks: [Mark] = []
        let tools: [PointerTool] = [.arrow, .rectangle, .ellipse]
        for index in 0..<fixtureMarkCount {
            let column = index % 4
            let row = index / 4
            let start = NormalizedPoint(
                x: 0.05 + Double(column) * 0.2,
                y: 0.05 + Double(row) * 0.2
            )
            let end = NormalizedPoint(x: start.x + 0.1, y: start.y + 0.1)
            let geometry: MarkGeometry
            switch tools[index % tools.count] {
            case .arrow:
                geometry = .arrow(start: start, end: end)
            case .rectangle:
                geometry = .rectangle(
                    NormalizedRect(x: start.x, y: start.y, width: 0.1, height: 0.1)
                )
            case .ellipse:
                geometry = .ellipse(
                    NormalizedRect(x: start.x, y: start.y, width: 0.1, height: 0.1)
                )
            case .select, .pen, .eraser, .emoji, .spotlight:
                continue
            }
            let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!
            marks.append(Mark(id: id, geometry: geometry, style: .default))
        }
        return marks
    }

    private static func validate(
        canvas: Canvas,
        samples: Int,
        session: inout PointerSession,
        fixture: Canvas,
        fixtureChecksum: String
    ) -> Bool {
        guard canvas.marks.count == fixtureMarkCount + 1,
              let freehand = canvas.marks.last,
              case let .freehand(points) = freehand.geometry,
              points.count == samples + 1,
              points.first == NormalizedPoint(x: 0.05, y: 0.2),
              points.last == NormalizedPoint(
                x: 0.05 + Double(samples) * 0.0025,
                y: 0.2 + (samples.isMultiple(of: 2) ? 0 : 0.02)
              ),
              points.map(\.x).min() == 0.05,
              points.map(\.x).max() == 0.05 + Double(samples) * 0.0025,
              points.map(\.y).min() == 0.2,
              points.map(\.y).max() == 0.22
        else {
            return false
        }

        session.apply(.undo(on: fixtureDisplay))
        return session.canvas(for: fixtureDisplay) == fixture
            && checksum(for: session.canvas(for: fixtureDisplay)) == fixtureChecksum
    }

    private static func checksum(for canvas: Canvas) -> String {
        let model = canvas.marks.map { mark in
            "tool=\(tool(for: mark.geometry));style=\(style(for: mark.style));geometry=\(geometry(for: mark.geometry))"
        }.joined(separator: "\n")
        return fnv1a64(model)
    }

    private static func tool(for geometry: MarkGeometry) -> String {
        switch geometry {
        case .arrow: return "arrow"
        case .rectangle: return "rectangle"
        case .ellipse: return "ellipse"
        case .freehand: return "pen"
        case .emoji: return "emoji"
        case .spotlight: return "spotlight"
        }
    }

    private static func style(for style: MarkStyle) -> String {
        "color=\(style.color.red.description),\(style.color.green.description),\(style.color.blue.description),\(style.color.alpha.description);stroke=\(style.strokeWidth.description);opacity=\(style.opacity.description)"
    }

    private static func geometry(for geometry: MarkGeometry) -> String {
        switch geometry {
        case let .arrow(start, end):
            return "arrow=\(point(start));\(point(end))"
        case let .rectangle(rect):
            return "rectangle=\(rect.x),\(rect.y),\(rect.width),\(rect.height)"
        case let .ellipse(rect):
            return "ellipse=\(rect.x),\(rect.y),\(rect.width),\(rect.height)"
        case let .freehand(points):
            return "freehand=\(points.map(point).joined(separator: ";"))"
        case let .emoji(text, rect):
            return "emoji=\(text);\(rect.x),\(rect.y),\(rect.width),\(rect.height)"
        case let .spotlight(center, radius, dimness):
            return "spotlight=\(point(center));\(radius);\(dimness)"
        }
    }

    private static func point(_ point: NormalizedPoint) -> String {
        "\(point.x.description),\(point.y.description)"
    }

    private static func fnv1a64(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }

    private static func nanoseconds(from duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000_000_000
            + Double(components.attoseconds) / 1_000_000_000
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private static func p95(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let rank = max(1, Int(ceil(0.95 * Double(sorted.count))))
        return sorted[rank - 1]
    }

    private static func mad(_ values: [Double]) -> Double {
        let center = median(values)
        return median(values.map { abs($0 - center) })
    }
}
