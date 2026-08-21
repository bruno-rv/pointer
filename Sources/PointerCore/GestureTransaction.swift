import Foundation

public enum GestureBoundaryEvent: Equatable, Sendable {
    case began
    case committed
    case cancelled
}

public struct GestureUpdate: Equatable, Sendable {
    public let previewMarks: [Mark]
    public let selection: Mark.ID?
    public let needsRedraw: Bool
    public let boundaryEvent: GestureBoundaryEvent?

    public init(
        previewMarks: [Mark],
        selection: Mark.ID?,
        needsRedraw: Bool,
        boundaryEvent: GestureBoundaryEvent?
    ) {
        self.previewMarks = previewMarks
        self.selection = selection
        self.needsRedraw = needsRedraw
        self.boundaryEvent = boundaryEvent
    }
}

public struct GestureCommit: Equatable, Sendable {
    public let didMutate: Bool
    public let previewMarks: [Mark]
    public let selection: Mark.ID?
    public let boundaryEvent: GestureBoundaryEvent

    public init(
        didMutate: Bool,
        previewMarks: [Mark],
        selection: Mark.ID?
    ) {
        self.didMutate = didMutate
        self.previewMarks = previewMarks
        self.selection = selection
        boundaryEvent = .committed
    }
}

public struct GestureCancellation: Equatable, Sendable {
    public let previewMarks: [Mark]
    public let selection: Mark.ID?
    public let boundaryEvent: GestureBoundaryEvent

    public init(previewMarks: [Mark], selection: Mark.ID?) {
        self.previewMarks = previewMarks
        self.selection = selection
        boundaryEvent = .cancelled
    }
}

public struct GestureTransaction: Equatable, Sendable {
    public let display: DisplayUUID
    public let tool: PointerTool

    let baseCanvas: Canvas
    let baseSelection: Mark.ID?
    let baseSelectionDisplay: DisplayUUID?
    var previewCanvas: Canvas
    var selection: Mark.ID?
    var startPoint: NormalizedPoint
    var previousPoint: NormalizedPoint
    var draftMarkID: Mark.ID?
    var selectionInteraction: SelectionInteraction?
    var didErase: Bool
    var emojiDidDrag: Bool
    var geometryDidChange: Bool

    enum SelectionInteraction: Equatable, Sendable {
        case move(original: Mark)
        case resize(handle: ResizeHandle, original: Mark)
        case selecting
    }

    static let defaultEmojiSide: Double = 0.08

    mutating func advance(to point: NormalizedPoint, style: MarkStyle, toolState: ToolState) {
        switch tool {
        case .select:
            advanceSelection(to: point)
        case .eraser:
            erase(alongSegmentFrom: previousPoint, to: point)
        case .arrow, .rectangle, .ellipse, .pen, .emoji, .spotlight:
            advanceDraft(to: point, style: style, toolState: toolState)
        }
        previousPoint = point
    }

    func isMeaningfulCommit() -> Bool {
        switch tool {
        case .select:
            return geometryDidChange
        case .eraser:
            return didErase
        case .arrow, .rectangle, .ellipse, .pen:
            guard let draft = draftMark() else { return false }
            return !Self.isZeroLength(draft.geometry)
        case .emoji, .spotlight:
            return draftMark() != nil
        }
    }

    func draftMark() -> Mark? {
        guard let draftMarkID else { return nil }
        return previewCanvas.marks.first { $0.id == draftMarkID }
    }

    static func isZeroLength(_ geometry: MarkGeometry) -> Bool {
        switch geometry {
        case let .arrow(start, end):
            return start == end
        case let .rectangle(rect), let .ellipse(rect):
            return rect.width == 0 && rect.height == 0
        case let .freehand(points):
            return points.count < 2
        case .emoji, .spotlight:
            return false
        }
    }

    private mutating func advanceSelection(to point: NormalizedPoint) {
        guard let selection,
              let index = previewCanvas.marks.firstIndex(where: { $0.id == selection })
        else {
            return
        }

        switch selectionInteraction {
        case .move:
            let dx = point.x - previousPoint.x
            let dy = point.y - previousPoint.y
            if dx == 0, dy == 0 { return }
            var mark = previewCanvas.marks[index]
            mark = Mark(
                id: mark.id,
                geometry: ResizeGeometry.translate(mark.geometry, dx: dx, dy: dy),
                style: mark.style
            )
            previewCanvas.replace(mark)
            geometryDidChange = true
        case let .resize(handle, original):
            if point == previousPoint { return }
            let current = previewCanvas.marks[index]
            let newGeometry = ResizeGeometry.resize(
                current.geometry,
                using: handle,
                to: point,
                original: original.geometry
            )
            guard newGeometry != current.geometry else { return }
            previewCanvas.replace(
                Mark(id: current.id, geometry: newGeometry, style: current.style)
            )
            geometryDidChange = newGeometry != original.geometry
        case .selecting, nil:
            break
        }
    }

    private mutating func advanceDraft(
        to point: NormalizedPoint,
        style: MarkStyle,
        toolState: ToolState
    ) {
        guard let draftMarkID,
              let index = previewCanvas.marks.firstIndex(where: { $0.id == draftMarkID })
        else {
            return
        }

        let current = previewCanvas.marks[index]
        let geometry: MarkGeometry
        switch tool {
        case .arrow:
            geometry = .arrow(start: startPoint, end: point)
        case .rectangle:
            geometry = .rectangle(ResizeGeometry.rect(from: startPoint, to: point))
        case .ellipse:
            geometry = .ellipse(ResizeGeometry.rect(from: startPoint, to: point))
        case .pen:
            if case var .freehand(points) = current.geometry {
                points.append(point)
                geometry = .freehand(points)
            } else {
                geometry = .freehand([startPoint, point])
            }
        case .emoji:
            emojiDidDrag = true
            let side = max(abs(point.x - startPoint.x), abs(point.y - startPoint.y)) * 2
            geometry = .emoji(
                text: toolState.emoji,
                rect: ResizeGeometry.clampedSquare(
                    centeredAt: startPoint,
                    side: max(side, Self.defaultEmojiSide)
                )
            )
        case .spotlight:
            let radius = hypot(point.x - startPoint.x, point.y - startPoint.y)
            geometry = .spotlight(
                center: startPoint,
                radius: max(radius, 0),
                dimness: toolState.spotlightDimness
            )
        case .select, .eraser:
            return
        }

        previewCanvas.replace(Mark(id: current.id, geometry: geometry, style: style))
    }

    mutating func erase(alongSegmentFrom start: NormalizedPoint, to end: NormalizedPoint) {
        let tolerance = HitTesting.defaultTolerance
        let remaining = previewCanvas.marks.filter { mark in
            if start == end {
                return !HitTesting.intersects(mark: mark, at: end, tolerance: tolerance)
            }
            return !HitTesting.intersects(
                mark: mark,
                segmentFrom: start,
                to: end,
                tolerance: tolerance
            )
        }
        if remaining.count != previewCanvas.marks.count {
            didErase = true
            previewCanvas.setMarks(remaining)
        }
    }

    mutating func erase(at point: NormalizedPoint) {
        erase(alongSegmentFrom: point, to: point)
    }
}
