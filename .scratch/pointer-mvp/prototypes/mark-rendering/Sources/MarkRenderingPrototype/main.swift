import AppKit
import Darwin

enum Tool: String, CaseIterable {
    case select = "🎯 Select"
    case arrow = "➡️ Arrow"
    case rectangle = "⬜️ Rectangle"
    case ellipse = "⭕️ Ellipse"
    case freehand = "✏️ Freehand"
    case emoji = "😀 Emoji"
    case eraser = "🧽 Eraser"
}

private enum ResizeHandle: Equatable {
    case arrowStart
    case arrowEnd
    case bottomLeft
    case bottomRight
    case topLeft
    case topRight

    func point(in bounds: NSRect) -> NSPoint {
        switch self {
        case .bottomLeft:
            return NSPoint(x: bounds.minX, y: bounds.minY)
        case .bottomRight:
            return NSPoint(x: bounds.maxX, y: bounds.minY)
        case .topLeft:
            return NSPoint(x: bounds.minX, y: bounds.maxY)
        case .topRight:
            return NSPoint(x: bounds.maxX, y: bounds.maxY)
        case .arrowStart, .arrowEnd:
            preconditionFailure("Arrow handles use the arrow endpoints")
        }
    }

    func oppositePoint(in bounds: NSRect) -> NSPoint {
        switch self {
        case .bottomLeft:
            return NSPoint(x: bounds.maxX, y: bounds.maxY)
        case .bottomRight:
            return NSPoint(x: bounds.minX, y: bounds.maxY)
        case .topLeft:
            return NSPoint(x: bounds.maxX, y: bounds.minY)
        case .topRight:
            return NSPoint(x: bounds.minX, y: bounds.minY)
        case .arrowStart, .arrowEnd:
            preconditionFailure("Arrow handles use the arrow endpoints")
        }
    }
}

struct Mark: Identifiable {
    enum Geometry {
        case arrow(start: NSPoint, end: NSPoint)
        case rectangle(NSRect)
        case ellipse(NSRect)
        case freehand([NSPoint])
        case emoji(text: String, rect: NSRect)
    }

    let id: UUID
    var geometry: Geometry
    var opacity: CGFloat

    var bounds: NSRect {
        switch geometry {
        case let .arrow(start, end):
            return NSRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
        case let .rectangle(rect), let .ellipse(rect):
            return rect
        case let .freehand(points):
            guard let first = points.first else { return .zero }
            return points.dropFirst().reduce(NSRect(origin: first, size: .zero)) {
                $0.union(NSRect(origin: $1, size: .zero))
            }
        case let .emoji(_, rect):
            return rect
        }
    }

    var stateDescription: String {
        let shortID = id.uuidString.prefix(6)
        let shape: String
        switch geometry {
        case let .arrow(start, end):
            shape = "arrow \(start.compact) → \(end.compact)"
        case let .rectangle(rect):
            shape = "rectangle \(rect.compact)"
        case let .ellipse(rect):
            shape = "ellipse \(rect.compact)"
        case let .freehand(points):
            shape = "freehand \(points.count) points, bounds \(bounds.compact)"
        case let .emoji(text, rect):
            shape = "emoji \(text) \(rect.compact)"
        }
        return "\(shortID)  \(shape)  opacity \(String(format: "%.2f", Double(opacity)))"
    }

    mutating func translate(dx: CGFloat, dy: CGFloat) {
        switch geometry {
        case let .arrow(start, end):
            geometry = .arrow(
                start: NSPoint(x: start.x + dx, y: start.y + dy),
                end: NSPoint(x: end.x + dx, y: end.y + dy)
            )
        case let .rectangle(rect):
            geometry = .rectangle(rect.offsetBy(dx: dx, dy: dy))
        case let .ellipse(rect):
            geometry = .ellipse(rect.offsetBy(dx: dx, dy: dy))
        case let .freehand(points):
            geometry = .freehand(points.map { NSPoint(x: $0.x + dx, y: $0.y + dy) })
        case let .emoji(text, rect):
            geometry = .emoji(text: text, rect: rect.offsetBy(dx: dx, dy: dy))
        }
    }

    fileprivate mutating func resize(from original: Mark, using handle: ResizeHandle, to point: NSPoint) {
        switch original.geometry {
        case let .arrow(start, end):
            if handle == .arrowStart {
                geometry = .arrow(start: point, end: end)
            } else if handle == .arrowEnd {
                geometry = .arrow(start: start, end: point)
            }

        case .rectangle, .ellipse, .freehand, .emoji:
            let originalBounds = original.bounds
            let anchor = handle.oppositePoint(in: originalBounds)
            let newBounds = NSRect(
                x: min(anchor.x, point.x),
                y: min(anchor.y, point.y),
                width: abs(point.x - anchor.x),
                height: abs(point.y - anchor.y)
            )

            switch original.geometry {
            case .rectangle:
                geometry = .rectangle(newBounds)
            case .ellipse:
                geometry = .ellipse(newBounds)
            case let .freehand(points):
                func scale(_ value: CGFloat, oldMin: CGFloat, oldSize: CGFloat, newMin: CGFloat, newSize: CGFloat) -> CGFloat {
                    guard oldSize > 0 else { return newMin + newSize / 2 }
                    return newMin + ((value - oldMin) / oldSize) * newSize
                }

                geometry = .freehand(points.map {
                    NSPoint(
                        x: scale(
                            $0.x,
                            oldMin: originalBounds.minX,
                            oldSize: originalBounds.width,
                            newMin: newBounds.minX,
                            newSize: newBounds.width
                        ),
                        y: scale(
                            $0.y,
                            oldMin: originalBounds.minY,
                            oldSize: originalBounds.height,
                            newMin: newBounds.minY,
                            newSize: newBounds.height
                        )
                    )
                })
            case let .emoji(text, _):
                geometry = .emoji(text: text, rect: newBounds)
            case .arrow:
                break
            }
        }
    }
}

private enum SelectionGesture {
    case move
    case resize(handle: ResizeHandle, original: Mark)
}

private extension NSPoint {
    var compact: String {
        "(\(Int(x.rounded())), \(Int(y.rounded())))"
    }
}

private extension NSRect {
    var compact: String {
        "[\(Int(minX.rounded())), \(Int(minY.rounded())), \(Int(width.rounded()))×\(Int(height.rounded()))]"
    }
}

@MainActor
final class CanvasView: NSView {
    var onStateChange: ((String) -> Void)?

    var tool: Tool = .select {
        didSet {
            selectedID = nil
            publishState()
            needsDisplay = true
        }
    }

    var currentOpacity: CGFloat = 0.9 {
        didSet {
            if let selectedID, let index = marks.firstIndex(where: { $0.id == selectedID }) {
                marks[index].opacity = currentOpacity
                needsDisplay = true
            }
            publishState()
        }
    }

    var currentEmoji = "😀" {
        didSet {
            publishState()
        }
    }

    private(set) var marks: [Mark] = []
    private var undoStack: [[Mark]] = []
    private var selectedID: UUID?
    private var dragStart: NSPoint?
    private var previousDragPoint: NSPoint?
    private var selectionGesture: SelectionGesture?

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
        dirtyRect.fill()
        drawGrid(in: dirtyRect)

        for mark in marks {
            draw(mark)
            if mark.id == selectedID {
                drawSelection(for: mark)
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        beginGesture(at: convert(event.locationInWindow, from: nil))
    }

    func beginGesture(at point: NSPoint) {
        dragStart = point
        previousDragPoint = point

        if tool == .select {
            if
                let selectedID,
                let selectedMark = marks.first(where: { $0.id == selectedID }),
                let handle = resizeHandle(at: point, for: selectedMark)
            {
                pushUndoSnapshot()
                selectionGesture = .resize(handle: handle, original: selectedMark)
            } else {
                selectedID = marks.reversed().first(where: { hit($0, at: point) })?.id
                if selectedID != nil {
                    pushUndoSnapshot()
                    selectionGesture = .move
                } else {
                    selectionGesture = nil
                }
            }
        } else if tool == .eraser {
            pushUndoSnapshot()
            selectedID = nil
            selectionGesture = nil
            eraseMarks(at: point)
        } else if tool == .emoji {
            addEmojiStamp(at: point)
        } else {
            pushUndoSnapshot()
            selectedID = nil
            selectionGesture = nil
            marks.append(Mark(id: UUID(), geometry: initialGeometry(at: point), opacity: currentOpacity))
        }

        publishState()
        needsDisplay = true
    }

    func addEmojiStamp(at point: NSPoint) {
        pushUndoSnapshot()
        selectedID = nil
        selectionGesture = nil
        marks.append(Mark(id: UUID(), geometry: initialGeometry(at: point), opacity: currentOpacity))
    }

    override func mouseDragged(with event: NSEvent) {
        continueGesture(to: convert(event.locationInWindow, from: nil))
    }

    func continueGesture(to point: NSPoint) {
        if tool == .select {
            guard
                let selectedID,
                let index = marks.firstIndex(where: { $0.id == selectedID })
            else { return }

            switch selectionGesture {
            case .move:
                guard let previousDragPoint else { return }
                marks[index].translate(dx: point.x - previousDragPoint.x, dy: point.y - previousDragPoint.y)
                self.previousDragPoint = point
            case let .resize(handle, original):
                marks[index].resize(from: original, using: handle, to: point)
            case nil:
                return
            }
        } else if tool == .eraser {
            eraseMarks(at: point)
        } else {
            guard let dragStart, let index = marks.indices.last else { return }
            switch marks[index].geometry {
            case .arrow:
                marks[index].geometry = .arrow(start: dragStart, end: point)
            case .rectangle:
                marks[index].geometry = .rectangle(rect(from: dragStart, to: point))
            case .ellipse:
                marks[index].geometry = .ellipse(rect(from: dragStart, to: point))
            case var .freehand(points):
                points.append(point)
                marks[index].geometry = .freehand(points)
            case .emoji:
                break
            }
        }

        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        endGesture()
    }

    func endGesture() {
        dragStart = nil
        previousDragPoint = nil
        selectionGesture = nil
        publishState()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 {
            deleteSelected()
        } else {
            super.keyDown(with: event)
        }
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        marks = previous
        selectedID = nil
        publishState()
        needsDisplay = true
    }

    func clear() {
        guard !marks.isEmpty else { return }
        pushUndoSnapshot()
        marks.removeAll()
        selectedID = nil
        publishState()
        needsDisplay = true
    }

    func deleteSelected() {
        guard let selectedID, let index = marks.firstIndex(where: { $0.id == selectedID }) else { return }
        pushUndoSnapshot()
        marks.remove(at: index)
        self.selectedID = nil
        publishState()
        needsDisplay = true
    }

    func publishState() {
        let selected = selectedID.map { String($0.uuidString.prefix(6)) } ?? "none"
        let markLines = marks.isEmpty
            ? "  (none)"
            : marks.enumerated().map { "  \($0.offset + 1). \($0.element.stateDescription)" }.joined(separator: "\n")

        onStateChange?(
            """
            tool: \(tool.rawValue)
            emoji: \(currentEmoji)
            opacity: \(String(format: "%.2f", Double(currentOpacity)))
            selected: \(selected)
            undo snapshots: \(undoStack.count)
            marks: \(marks.count)
            \(markLines)
            """
        )
    }

    private func pushUndoSnapshot() {
        undoStack.append(marks)
    }

    private func initialGeometry(at point: NSPoint) -> Mark.Geometry {
        switch tool {
        case .arrow:
            return .arrow(start: point, end: point)
        case .rectangle:
            return .rectangle(NSRect(origin: point, size: .zero))
        case .ellipse:
            return .ellipse(NSRect(origin: point, size: .zero))
        case .freehand:
            return .freehand([point])
        case .emoji:
            let size: CGFloat = 56
            return .emoji(
                text: currentEmoji,
                rect: NSRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
            )
        case .select, .eraser:
            preconditionFailure("Selection and erasing do not create marks")
        }
    }

    private func eraseMarks(at point: NSPoint) {
        marks.removeAll { hit($0, at: point) }
    }

    private func rect(from start: NSPoint, to end: NSPoint) -> NSRect {
        NSRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    private func draw(_ mark: Mark) {
        let color = NSColor.systemRed.withAlphaComponent(mark.opacity)
        color.setStroke()
        color.setFill()

        switch mark.geometry {
        case let .arrow(start, end):
            let path = NSBezierPath()
            path.lineWidth = 5
            path.lineCapStyle = .round
            path.move(to: start)
            path.line(to: end)

            let angle = atan2(end.y - start.y, end.x - start.x)
            let headLength: CGFloat = 18
            path.move(to: end)
            path.line(
                to: NSPoint(
                    x: end.x - headLength * cos(angle - .pi / 6),
                    y: end.y - headLength * sin(angle - .pi / 6)
                )
            )
            path.move(to: end)
            path.line(
                to: NSPoint(
                    x: end.x - headLength * cos(angle + .pi / 6),
                    y: end.y - headLength * sin(angle + .pi / 6)
                )
            )
            path.stroke()

        case let .rectangle(rect):
            let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
            path.lineWidth = 5
            path.stroke()

        case let .ellipse(rect):
            let path = NSBezierPath(ovalIn: rect)
            path.lineWidth = 5
            path.stroke()

        case let .freehand(points):
            guard let first = points.first else { return }
            if points.count == 1 {
                NSBezierPath(ovalIn: NSRect(x: first.x - 2.5, y: first.y - 2.5, width: 5, height: 5)).fill()
                return
            }
            let path = NSBezierPath()
            path.lineWidth = 5
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: first)
            points.dropFirst().forEach(path.line(to:))
            path.stroke()

        case let .emoji(text, rect):
            let fontSize = max(12, min(rect.width, rect.height))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize)
            ]
            let textSize = (text as NSString).size(withAttributes: attributes)
            let origin = NSPoint(
                x: rect.midX - textSize.width / 2,
                y: rect.midY - textSize.height / 2
            )
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.cgContext.setAlpha(mark.opacity)
            (text as NSString).draw(at: origin, withAttributes: attributes)
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private func drawSelection(for mark: Mark) {
        let selection = NSBezierPath(rect: mark.bounds.insetBy(dx: -8, dy: -8))
        selection.lineWidth = 2
        selection.setLineDash([6, 4], count: 2, phase: 0)
        NSColor.controlAccentColor.setStroke()
        selection.stroke()

        for (_, point) in resizeHandles(for: mark) {
            let handleRect = NSRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)
            NSColor.white.setFill()
            NSColor.controlAccentColor.setStroke()
            let handle = NSBezierPath(roundedRect: handleRect, xRadius: 2, yRadius: 2)
            handle.lineWidth = 2
            handle.fill()
            handle.stroke()
        }
    }

    private func resizeHandles(for mark: Mark) -> [(ResizeHandle, NSPoint)] {
        switch mark.geometry {
        case let .arrow(start, end):
            return [(.arrowStart, start), (.arrowEnd, end)]
        case .rectangle, .ellipse, .freehand, .emoji:
            let handles: [ResizeHandle] = [.bottomLeft, .bottomRight, .topLeft, .topRight]
            return handles.map { ($0, $0.point(in: mark.bounds)) }
        }
    }

    private func resizeHandle(at point: NSPoint, for mark: Mark) -> ResizeHandle? {
        resizeHandles(for: mark).first {
            hypot(point.x - $0.1.x, point.y - $0.1.y) <= 10
        }?.0
    }

    private func drawGrid(in rect: NSRect) {
        let path = NSBezierPath()
        path.lineWidth = 1
        let spacing: CGFloat = 24

        var x = floor(rect.minX / spacing) * spacing
        while x <= rect.maxX {
            path.move(to: NSPoint(x: x, y: rect.minY))
            path.line(to: NSPoint(x: x, y: rect.maxY))
            x += spacing
        }

        var y = floor(rect.minY / spacing) * spacing
        while y <= rect.maxY {
            path.move(to: NSPoint(x: rect.minX, y: y))
            path.line(to: NSPoint(x: rect.maxX, y: y))
            y += spacing
        }

        NSColor(calibratedWhite: 0.88, alpha: 1).setStroke()
        path.stroke()
    }

    private func hit(_ mark: Mark, at point: NSPoint) -> Bool {
        switch mark.geometry {
        case let .arrow(start, end):
            return distance(from: point, toSegmentFrom: start, to: end) <= 10
        case let .rectangle(rect), let .ellipse(rect):
            return rect.insetBy(dx: -10, dy: -10).contains(point)
        case let .freehand(points):
            if points.count == 1 {
                return hypot(point.x - points[0].x, point.y - points[0].y) <= 10
            }
            return zip(points, points.dropFirst()).contains {
                distance(from: point, toSegmentFrom: $0.0, to: $0.1) <= 10
            }
        case let .emoji(_, rect):
            return rect.insetBy(dx: -10, dy: -10).contains(point)
        }
    }

    private func distance(from point: NSPoint, toSegmentFrom start: NSPoint, to end: NSPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(point.x - start.x, point.y - start.y) }

        let projection = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        let nearest = NSPoint(x: start.x + projection * dx, y: start.y + projection * dy)
        return hypot(point.x - nearest.x, point.y - nearest.y)
    }
}

struct DragBenchmarkConfiguration: Sendable {
    let warmupGestures: Int
    let trialCount: Int
    let gesturesPerTrial: Int
    let samplesPerGesture: Int

    static let standard = DragBenchmarkConfiguration(
        warmupGestures: 5,
        trialCount: 30,
        gesturesPerTrial: 20,
        samplesPerGesture: 240
    )
    static let smoke = DragBenchmarkConfiguration(
        warmupGestures: 0,
        trialCount: 1,
        gesturesPerTrial: 1,
        samplesPerGesture: 240
    )
}

struct DragBenchmarkTrial: Codable {
    let wholeGestureNanoseconds: Double
    let continuationLoopNanoseconds: Double
    let nanosecondsPerDragSample: Double
    let publicationsPerGesture: Int
    let publicationCountsUniform: Bool
}

struct DragBenchmarkReport: Codable {
    let label: String
    let fixtureID: String
    let buildConfiguration: String
    let warmupGestures: Int
    let trialCount: Int
    let gesturesPerTrial: Int
    let samplesPerGesture: Int
    let trials: [DragBenchmarkTrial]
    let wholeGestureMedianNanoseconds: Double
    let wholeGestureP95Nanoseconds: Double
    let wholeGestureMADNanoseconds: Double
    let continuationMedianNanoseconds: Double
    let continuationP95Nanoseconds: Double
    let continuationMADNanoseconds: Double
    let modelChecksum: String
    let inspectorChecksum: String
    let finalStateValid: Bool
    let renderTimed: Bool
    let gridTimed: Bool
    let eventDispatchTimed: Bool
}

func fnv1a64(_ value: String) -> String {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in value.utf8 {
        hash ^= UInt64(byte)
        hash &*= 1_099_511_628_211
    }
    return String(format: "%016llx", hash)
}

@MainActor
enum DragPublicationBenchmark {
    private static let fixtureID = "freehand-12-basic-240-drag"

    private struct GestureMeasurement {
        let wholeGestureNanoseconds: Double
        let continuationLoopNanoseconds: Double
        let publications: Int
        let modelChecksum: String
        let inspectorChecksum: String
        let finalStateValid: Bool
    }

    static func run(configuration: DragBenchmarkConfiguration, label: String) -> DragBenchmarkReport {
        _ = NSApplication.shared

        for _ in 0..<configuration.warmupGestures {
            _ = measureGesture(samplesPerGesture: configuration.samplesPerGesture)
        }

        var trials: [DragBenchmarkTrial] = []
        var modelChecksum = ""
        var inspectorChecksum = ""
        var finalStateValid = true

        for _ in 0..<configuration.trialCount {
            var wholeGestureNanoseconds: [Double] = []
            var continuationLoopNanoseconds: [Double] = []
            var publications: [Int] = []

            for _ in 0..<configuration.gesturesPerTrial {
                let measurement = measureGesture(samplesPerGesture: configuration.samplesPerGesture)
                wholeGestureNanoseconds.append(measurement.wholeGestureNanoseconds)
                continuationLoopNanoseconds.append(measurement.continuationLoopNanoseconds)
                publications.append(measurement.publications)
                finalStateValid = finalStateValid && measurement.finalStateValid

                if modelChecksum.isEmpty {
                    modelChecksum = measurement.modelChecksum
                    inspectorChecksum = measurement.inspectorChecksum
                } else {
                    finalStateValid = finalStateValid
                        && measurement.modelChecksum == modelChecksum
                        && measurement.inspectorChecksum == inspectorChecksum
                }
            }

            let trial = makeTrial(
                wholeGestureNanoseconds: wholeGestureNanoseconds,
                continuationLoopNanoseconds: continuationLoopNanoseconds,
                publications: publications,
                samplesPerGesture: configuration.samplesPerGesture
            )
            finalStateValid = finalStateValid && trial.publicationCountsUniform
            trials.append(trial)
        }

        let wholeGestureValues = trials.map(\.wholeGestureNanoseconds)
        let continuationValues = trials.map(\.continuationLoopNanoseconds)

        return DragBenchmarkReport(
            label: label,
            fixtureID: fixtureID,
            buildConfiguration: buildConfiguration,
            warmupGestures: configuration.warmupGestures,
            trialCount: configuration.trialCount,
            gesturesPerTrial: configuration.gesturesPerTrial,
            samplesPerGesture: configuration.samplesPerGesture,
            trials: trials,
            wholeGestureMedianNanoseconds: median(wholeGestureValues),
            wholeGestureP95Nanoseconds: p95(wholeGestureValues),
            wholeGestureMADNanoseconds: medianAbsoluteDeviation(wholeGestureValues),
            continuationMedianNanoseconds: median(continuationValues),
            continuationP95Nanoseconds: p95(continuationValues),
            continuationMADNanoseconds: medianAbsoluteDeviation(continuationValues),
            modelChecksum: modelChecksum,
            inspectorChecksum: inspectorChecksum,
            finalStateValid: finalStateValid,
            renderTimed: false,
            gridTimed: false,
            eventDispatchTimed: false
        )
    }

    private static var buildConfiguration: String {
        #if DEBUG
        return "debug"
        #else
        return "release"
        #endif
    }

    static func makeTrial(
        wholeGestureNanoseconds: [Double],
        continuationLoopNanoseconds: [Double],
        publications: [Int],
        samplesPerGesture: Int
    ) -> DragBenchmarkTrial {
        precondition(!publications.isEmpty)
        precondition(wholeGestureNanoseconds.count == publications.count)
        precondition(continuationLoopNanoseconds.count == publications.count)

        let publicationCountsUniform = publications.dropFirst().allSatisfy {
            $0 == publications[0]
        }
        let wholeGestureAverage = wholeGestureNanoseconds.reduce(0, +)
            / Double(publications.count)
        let continuationAverage = continuationLoopNanoseconds.reduce(0, +)
            / Double(publications.count)

        return DragBenchmarkTrial(
            wholeGestureNanoseconds: wholeGestureAverage,
            continuationLoopNanoseconds: continuationAverage,
            nanosecondsPerDragSample: continuationAverage / Double(samplesPerGesture),
            publicationsPerGesture: publicationCountsUniform ? publications[0] : 0,
            publicationCountsUniform: publicationCountsUniform
        )
    }

    private static func measureGesture(samplesPerGesture: Int) -> GestureMeasurement {
        let canvas = CanvasView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600)
        )
        let basicTools: [Tool] = [.arrow, .rectangle, .ellipse]

        for index in 0..<12 {
            let start = NSPoint(
                x: CGFloat(20 + 80 * (index % 4)),
                y: CGFloat(40 + 80 * (index / 4))
            )
            let end = NSPoint(x: start.x + 40, y: start.y + 30)
            canvas.tool = basicTools[index % basicTools.count]
            canvas.beginGesture(at: start)
            canvas.continueGesture(to: end)
            canvas.endGesture()
        }

        let inspector = NSTextView()
        var publications = 0
        canvas.onStateChange = { state in
            inspector.string = state
            publications += 1
        }
        canvas.tool = .freehand
        let fixtureChecksum = modelChecksum(for: canvas)
        publications = 0

        let start = NSPoint(x: 20, y: 100)
        let clock = ContinuousClock()
        let wholeGestureStart = clock.now
        canvas.beginGesture(at: start)
        let continuationStart = clock.now

        for index in 1...samplesPerGesture {
            canvas.continueGesture(
                to: NSPoint(
                    x: CGFloat(20 + 2 * index),
                    y: CGFloat(100 + 20 * (index % 2))
                )
            )
        }

        let continuationEnd = clock.now
        canvas.endGesture()
        let wholeGestureEnd = clock.now
        let gesturePublications = publications

        let finalModelChecksum = modelChecksum(for: canvas)
        let inspectorChecksum = fnv1a64(normalizedInspectorState(inspector.string))
        let expectedBounds = NSRect(x: 20, y: 100, width: 480, height: 20)
        let finalFreehandValid: Bool

        if let finalMark = canvas.marks.last,
           case let .freehand(points) = finalMark.geometry {
            finalFreehandValid = canvas.marks.count == 13
                && points.count == samplesPerGesture + 1
                && finalMark.bounds == expectedBounds
        } else {
            finalFreehandValid = false
        }

        canvas.undo()
        let undoRestoredFixture = canvas.marks.count == 12
            && modelChecksum(for: canvas) == fixtureChecksum

        return GestureMeasurement(
            wholeGestureNanoseconds: nanoseconds(
                from: wholeGestureStart.duration(to: wholeGestureEnd)
            ),
            continuationLoopNanoseconds: nanoseconds(
                from: continuationStart.duration(to: continuationEnd)
            ),
            publications: gesturePublications,
            modelChecksum: finalModelChecksum,
            inspectorChecksum: inspectorChecksum,
            finalStateValid: finalFreehandValid && undoRestoredFixture
        )
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
        let index = Int(ceil(0.95 * Double(sorted.count))) - 1
        return sorted[index]
    }

    private static func medianAbsoluteDeviation(_ values: [Double]) -> Double {
        let center = median(values)
        return median(values.map { abs($0 - center) })
    }

    private static func modelChecksum(for canvas: CanvasView) -> String {
        let color = NSColor.systemRed.usingColorSpace(.deviceRGB)!
        let model = [
            "tool=\(canvas.tool.rawValue)",
            "color=\(coordinate(color.redComponent)),\(coordinate(color.greenComponent)),\(coordinate(color.blueComponent)),\(coordinate(color.alphaComponent))",
            "lineWidth=\(coordinate(5))"
        ] + canvas.marks.map { mark in
            "tool=\(tool(for: mark).rawValue)|opacity=\(coordinate(mark.opacity))|\(geometry(for: mark.geometry))"
        }
        return fnv1a64(model.joined(separator: "\n"))
    }

    private static func normalizedInspectorState(_ state: String) -> String {
        let expression = try! NSRegularExpression(
            pattern: "(?m)^( {2}\\d+\\. )[0-9A-Fa-f]{6}(?= {2})"
        )
        let range = NSRange(state.startIndex..., in: state)
        return expression.stringByReplacingMatches(
            in: state,
            range: range,
            withTemplate: "$1<id>"
        )
    }

    private static func tool(for mark: Mark) -> Tool {
        switch mark.geometry {
        case .arrow:
            return .arrow
        case .rectangle:
            return .rectangle
        case .ellipse:
            return .ellipse
        case .freehand:
            return .freehand
        case .emoji:
            return .emoji
        }
    }

    private static func geometry(for geometry: Mark.Geometry) -> String {
        switch geometry {
        case let .arrow(start, end):
            return "arrow=\(point(start));\(point(end))"
        case let .rectangle(rect):
            return "rectangle=\(rect.origin.x),\(rect.origin.y),\(rect.size.width),\(rect.size.height)"
        case let .ellipse(rect):
            return "ellipse=\(rect.origin.x),\(rect.origin.y),\(rect.size.width),\(rect.size.height)"
        case let .freehand(points):
            return "freehand=\(points.map(point).joined(separator: ";"))"
        case let .emoji(text, rect):
            return "emoji=\(text);\(rect.origin.x),\(rect.origin.y),\(rect.size.width),\(rect.size.height)"
        }
    }

    private static func point(_ point: NSPoint) -> String {
        "\(coordinate(point.x)),\(coordinate(point.y))"
    }

    private static func coordinate(_ value: CGFloat) -> String {
        String(format: "%.9f", Double(value))
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private let canvas = CanvasView()
    private let inspector = NSTextView()
    private weak var toolControl: NSSegmentedControl?
    private weak var emojiPicker: NSPopUpButton?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_160, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Pointer — Mark Rendering PROTOTYPE"
        window.minSize = NSSize(width: 860, height: 560)
        window.center()
        window.contentView = makeContentView()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        self.window = window

        canvas.publishState()
        if CommandLine.arguments.contains("--demo-emoji") {
            canvas.currentEmoji = "🎉"
            canvas.tool = .emoji
            toolControl?.selectedSegment = Tool.allCases.firstIndex(of: .emoji) ?? -1
            emojiPicker?.selectItem(withTitle: "🎉")
            canvas.addEmojiStamp(at: NSPoint(x: 320, y: 320))
            canvas.publishState()
            canvas.needsDisplay = true
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func makeContentView() -> NSView {
        let root = NSView()
        let toolbar = makeToolbar()
        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin

        canvas.translatesAutoresizingMaskIntoConstraints = false
        canvas.setContentHuggingPriority(.defaultLow, for: .horizontal)

        inspector.isEditable = false
        inspector.isSelectable = true
        inspector.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        inspector.textContainerInset = NSSize(width: 12, height: 12)
        inspector.backgroundColor = NSColor.windowBackgroundColor

        let inspectorScroll = NSScrollView()
        inspectorScroll.hasVerticalScroller = true
        inspectorScroll.documentView = inspector
        inspectorScroll.translatesAutoresizingMaskIntoConstraints = false

        splitView.addArrangedSubview(canvas)
        splitView.addArrangedSubview(inspectorScroll)
        splitView.setHoldingPriority(.defaultLow, forSubviewAt: 0)
        splitView.setHoldingPriority(.defaultHigh, forSubviewAt: 1)
        splitView.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(toolbar)
        root.addSubview(splitView)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            toolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            toolbar.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -14),

            splitView.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 12),
            splitView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            splitView.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            canvas.widthAnchor.constraint(greaterThanOrEqualToConstant: 600),
            inspectorScroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 290)
        ])

        canvas.onStateChange = { [weak inspector] state in
            inspector?.string = state
        }

        return root
    }

    private func makeToolbar() -> NSStackView {
        let badge = NSTextField(labelWithString: "PROTOTYPE")
        badge.font = .systemFont(ofSize: 12, weight: .bold)
        badge.textColor = .systemOrange

        let tools = NSSegmentedControl(
            labels: Tool.allCases.map(\.rawValue),
            trackingMode: .selectOne,
            target: self,
            action: #selector(changeTool(_:))
        )
        tools.selectedSegment = 0
        tools.setContentCompressionResistancePriority(.required, for: .horizontal)
        toolControl = tools

        let emojiPicker = NSPopUpButton()
        emojiPicker.addItems(withTitles: ["😀", "👍", "❤️", "🔥", "✅", "❌", "⭐️", "💡", "🎉", "⚠️"])
        emojiPicker.target = self
        emojiPicker.action = #selector(changeEmoji(_:))
        emojiPicker.toolTip = "Choose an emoji to stamp"
        self.emojiPicker = emojiPicker

        let opacityLabel = NSTextField(labelWithString: "🌗 Opacity")
        let opacity = NSSlider(
            value: Double(canvas.currentOpacity),
            minValue: 0.1,
            maxValue: 1,
            target: self,
            action: #selector(changeOpacity(_:))
        )
        opacity.widthAnchor.constraint(equalToConstant: 120).isActive = true

        let toolRow = NSStackView(views: [
            badge,
            tools,
            emojiPicker
        ])
        toolRow.orientation = .horizontal
        toolRow.alignment = .centerY
        toolRow.spacing = 10

        let actionRow = NSStackView(views: [
            opacityLabel,
            opacity,
            button("↩️ Undo", action: #selector(undo)),
            button("🗑️ Delete", action: #selector(deleteSelected)),
            button("🧹 Clear", action: #selector(clear))
        ])
        actionRow.orientation = .horizontal
        actionRow.alignment = .centerY
        actionRow.spacing = 10

        let toolbar = NSStackView(views: [toolRow, actionRow])
        toolbar.orientation = .vertical
        toolbar.alignment = .leading
        toolbar.spacing = 6
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        return toolbar
    }

    private func button(_ title: String, action: Selector) -> NSButton {
        NSButton(title: title, target: self, action: action)
    }

    @objc private func changeTool(_ sender: NSSegmentedControl) {
        guard Tool.allCases.indices.contains(sender.selectedSegment) else { return }
        canvas.tool = Tool.allCases[sender.selectedSegment]
    }

    @objc private func changeOpacity(_ sender: NSSlider) {
        canvas.currentOpacity = CGFloat(sender.doubleValue)
    }

    @objc private func changeEmoji(_ sender: NSPopUpButton) {
        guard let emoji = sender.titleOfSelectedItem else { return }
        canvas.currentEmoji = emoji
        canvas.tool = .emoji
        toolControl?.selectedSegment = Tool.allCases.firstIndex(of: .emoji) ?? -1
    }

    @objc private func undo() {
        canvas.undo()
    }

    @objc private func deleteSelected() {
        canvas.deleteSelected()
    }

    @objc private func clear() {
        canvas.clear()
    }
}

@main
@MainActor
enum MarkRenderingPrototype {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.contains("--benchmark-drag") {
            guard
                arguments.count == 5,
                arguments[0] == "--benchmark-drag",
                arguments[1] == "--label",
                !arguments[2].isEmpty,
                arguments[3] == "--format",
                arguments[4] == "json"
            else {
                FileHandle.standardError.write(
                    Data("usage: MarkRenderingPrototype --benchmark-drag --label <label> --format json\n".utf8)
                )
                exit(1)
            }

            _ = NSApplication.shared
            let report = DragPublicationBenchmark.run(
                configuration: .standard,
                label: arguments[2]
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]

            do {
                let data = try encoder.encode(report)
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
            } catch {
                FileHandle.standardError.write(Data("failed to encode benchmark report\n".utf8))
                exit(1)
            }
            return
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
        _ = delegate
    }
}
