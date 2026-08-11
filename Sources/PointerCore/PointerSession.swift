public struct PointerSession: Equatable, Sendable {
    public private(set) var mode: PointerMode
    public private(set) var toolState: ToolState

    private var canvases: [DisplayUUID: Canvas]
    private var undoHistories: [DisplayUUID: UndoHistory]
    private var connectedDisplays: Set<DisplayUUID>
    private var clearAllSnapshot: ClearAllSnapshot?

    public init(
        mode: PointerMode = .standby,
        toolState: ToolState = ToolState()
    ) {
        self.mode = mode
        self.toolState = toolState
        canvases = [:]
        undoHistories = [:]
        connectedDisplays = []
        clearAllSnapshot = nil
    }

    public mutating func ensureCanvas(for display: DisplayUUID) {
        connectedDisplays.insert(display)
        if canvases[display] == nil {
            canvases[display] = Canvas()
            undoHistories[display] = UndoHistory()
        }
    }

    public mutating func disconnect(_ display: DisplayUUID) {
        connectedDisplays.remove(display)
    }

    public func canvas(for display: DisplayUUID) -> Canvas {
        canvases[display] ?? Canvas()
    }

    public mutating func apply(_ command: SessionCommand) {
        switch command {
        case let .append(mark, display):
            append(mark, to: display)
        case let .remove(markID, display):
            remove(markID, from: display)
        case let .clear(display):
            clear(display)
        case let .undo(display):
            undo(on: display)
        case .clearAll:
            clearAll()
        case .undoClearAll:
            undoClearAll()
        case let .setMode(mode):
            self.mode = mode
        case let .setTool(tool):
            toolState.setTool(tool)
        case let .setStyle(style):
            toolState.setStyle(style)
        case let .setEmoji(emoji):
            toolState.setEmoji(emoji)
        case let .setSpotlight(radius, dimness):
            toolState.setSpotlight(radius: radius, dimness: dimness)
        }
    }

    private mutating func append(_ mark: Mark, to display: DisplayUUID) {
        ensureCanvas(for: display)
        invalidateClearAllUndo()
        recordSnapshot(for: display)
        var canvas = canvas(for: display)
        canvas.append(mark)
        canvases[display] = canvas
    }

    private mutating func remove(_ markID: Mark.ID, from display: DisplayUUID) {
        guard var canvas = canvases[display], canvas.marks.contains(where: { $0.id == markID }) else {
            return
        }
        invalidateClearAllUndo()
        recordSnapshot(for: display)
        _ = canvas.remove(id: markID)
        canvases[display] = canvas
    }

    private mutating func clear(_ display: DisplayUUID) {
        guard var canvas = canvases[display], !canvas.marks.isEmpty else {
            return
        }
        invalidateClearAllUndo()
        recordSnapshot(for: display)
        canvas.clear()
        canvases[display] = canvas
    }

    private mutating func undo(on display: DisplayUUID) {
        guard var history = undoHistories[display], let snapshot = history.popLatest() else {
            return
        }
        invalidateClearAllUndo()
        undoHistories[display] = history
        canvases[display] = snapshot
    }

    private mutating func clearAll() {
        guard canvases.values.contains(where: { !$0.marks.isEmpty }) else {
            return
        }
        clearAllSnapshot = ClearAllSnapshot(canvases: canvases, undoHistories: undoHistories)
        for display in canvases.keys {
            canvases[display] = Canvas()
        }
    }

    private mutating func undoClearAll() {
        guard let clearAllSnapshot else {
            return
        }
        canvases = clearAllSnapshot.canvases
        undoHistories = clearAllSnapshot.undoHistories
        self.clearAllSnapshot = nil
    }

    private mutating func recordSnapshot(for display: DisplayUUID) {
        var history = undoHistories[display] ?? UndoHistory()
        history.record(canvas(for: display))
        undoHistories[display] = history
    }

    private mutating func invalidateClearAllUndo() {
        clearAllSnapshot = nil
    }
}

private struct ClearAllSnapshot: Equatable, Sendable {
    let canvases: [DisplayUUID: Canvas]
    let undoHistories: [DisplayUUID: UndoHistory]
}
