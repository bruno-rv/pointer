import Foundation

public struct PointerSession: Equatable, Sendable {
    public private(set) var mode: PointerMode
    public private(set) var toolState: ToolState
    public private(set) var selection: Mark.ID?

    public var canUndoClearAll: Bool {
        clearAllSnapshot != nil
    }

    public func canUndo(on display: DisplayUUID) -> Bool {
        (undoHistories[display]?.count ?? 0) > 0
    }

    public func hasActiveGesture(on display: DisplayUUID) -> Bool {
        activeGesture?.display == display
    }

    private var canvases: [DisplayUUID: Canvas]
    private var undoHistories: [DisplayUUID: UndoHistory]
    private var connectedDisplays: Set<DisplayUUID>
    private var clearAllSnapshot: ClearAllSnapshot?
    private var activeGesture: GestureTransaction?
    private var selectionDisplay: DisplayUUID?

    public init(
        mode: PointerMode = .standby,
        toolState: ToolState = ToolState()
    ) {
        self.mode = mode
        self.toolState = toolState
        selection = nil
        canvases = [:]
        undoHistories = [:]
        connectedDisplays = []
        clearAllSnapshot = nil
        activeGesture = nil
        selectionDisplay = nil
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

    public func previewCanvas(for display: DisplayUUID) -> Canvas {
        if let activeGesture, activeGesture.display == display {
            return activeGesture.previewCanvas
        }
        return canvas(for: display)
    }

    public mutating func beginGesture(
        tool: PointerTool,
        at point: NormalizedPoint,
        on display: DisplayUUID
    ) -> GestureUpdate {
        if activeGesture != nil {
            _ = cancelGesture()
        }

        ensureCanvas(for: display)
        let baseCanvas = canvas(for: display)
        var transaction = GestureTransaction(
            display: display,
            tool: tool,
            baseCanvas: baseCanvas,
            baseSelection: selection,
            baseSelectionDisplay: selectionDisplay,
            previewCanvas: baseCanvas,
            selection: selection,
            startPoint: point,
            previousPoint: point,
            draftMarkID: nil,
            selectionInteraction: nil,
            didErase: false,
            emojiDidDrag: false,
            geometryDidChange: false
        )

        switch tool {
        case .select:
            beginSelect(&transaction, at: point)
        case .eraser:
            transaction.selection = nil
            selection = nil
            selectionDisplay = nil
            transaction.erase(at: point)
        case .arrow, .rectangle, .ellipse, .pen, .emoji, .spotlight:
            transaction.selection = nil
            selection = nil
            selectionDisplay = nil
            beginDraft(&transaction, tool: tool, at: point)
        }

        activeGesture = transaction
        selection = transaction.selection
        if selection != nil {
            selectionDisplay = display
        }

        return makeUpdate(from: transaction, boundaryEvent: .began)
    }

    public mutating func advanceGesture(to point: NormalizedPoint) -> GestureUpdate {
        guard var transaction = activeGesture else {
            return GestureUpdate(
                previewMarks: [],
                selection: selection,
                needsRedraw: false,
                boundaryEvent: nil
            )
        }

        transaction.advance(to: point, style: toolState.style, toolState: toolState)
        activeGesture = transaction
        selection = transaction.selection

        return makeUpdate(from: transaction, boundaryEvent: nil)
    }

    public mutating func commitGesture() -> GestureCommit {
        guard let transaction = activeGesture else {
            return GestureCommit(
                didMutate: false,
                previewMarks: [],
                selection: selection
            )
        }

        let didMutate = transaction.isMeaningfulCommit()
        if didMutate {
            invalidateClearAllUndo()
            recordSnapshot(for: transaction.display, canvas: transaction.baseCanvas)
            canvases[transaction.display] = transaction.previewCanvas
            selection = transaction.selection
            selectionDisplay = transaction.selection == nil ? nil : transaction.display
        } else {
            canvases[transaction.display] = transaction.baseCanvas
            if transaction.tool == .select {
                selection = transaction.selection
                selectionDisplay = selection == nil ? nil : transaction.display
            } else {
                selection = transaction.baseSelection
                selectionDisplay = transaction.baseSelectionDisplay
            }
        }

        activeGesture = nil
        let marks = canvas(for: transaction.display).marks
        return GestureCommit(didMutate: didMutate, previewMarks: marks, selection: selection)
    }

    public mutating func cancelGesture() -> GestureCancellation {
        guard let transaction = activeGesture else {
            return GestureCancellation(previewMarks: [], selection: selection)
        }

        canvases[transaction.display] = transaction.baseCanvas
        selection = transaction.baseSelection
        selectionDisplay = transaction.baseSelectionDisplay
        activeGesture = nil

        let marks = canvas(for: transaction.display).marks
        return GestureCancellation(previewMarks: marks, selection: selection)
    }

    public mutating func apply(_ command: SessionCommand) {
        var selectionForDelete: (id: Mark.ID, display: DisplayUUID)?
        if case .deleteSelected = command,
           let activeGesture,
           let selection = activeGesture.selection
        {
            selectionForDelete = (id: selection, display: activeGesture.display)
        }

        if command.cancelsActiveGesture, activeGesture != nil {
            _ = cancelGesture()
        }

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
        case .deleteSelected:
            deleteSelected(selection: selectionForDelete)
        case let .setMode(mode):
            self.mode = mode
            if mode == .standby {
                selection = nil
                selectionDisplay = nil
            }
        case let .setTool(tool):
            toolState.setTool(tool)
        case let .setStyle(style):
            toolState.setStyle(style)
            updateSelectedStyle { mark in
                Mark(id: mark.id, geometry: mark.geometry, style: style)
            }
        case let .setEmoji(emoji):
            toolState.setEmoji(emoji)
            updateSelectedStyle { mark in
                guard case let .emoji(_, rect) = mark.geometry else { return mark }
                return Mark(id: mark.id, geometry: .emoji(text: emoji, rect: rect), style: mark.style)
            }
        case let .setSpotlight(radius, dimness):
            toolState.setSpotlight(radius: radius, dimness: dimness)
            updateSelectedStyle { mark in
                guard case let .spotlight(center, _, _) = mark.geometry else { return mark }
                return Mark(
                    id: mark.id,
                    geometry: .spotlight(center: center, radius: radius, dimness: dimness),
                    style: mark.style
                )
            }
        }
    }

    private mutating func beginSelect(_ transaction: inout GestureTransaction, at point: NormalizedPoint) {
        let hit = HitTesting.hitTest(
            at: point,
            in: transaction.previewCanvas.marks,
            selectedID: transaction.selection
        )

        switch hit {
        case let .handle(handle):
            guard let selectedID = transaction.selection,
                  let selected = transaction.previewCanvas.marks.first(where: { $0.id == selectedID })
            else {
                transaction.selectionInteraction = .selecting
                return
            }
            transaction.selectionInteraction = .resize(handle: handle, original: selected)
            transaction.geometryDidChange = false
        case let .mark(markID):
            transaction.selection = markID
            if let selected = transaction.previewCanvas.marks.first(where: { $0.id == markID }) {
                transaction.selectionInteraction = .move(original: selected)
            } else {
                transaction.selectionInteraction = .selecting
            }
        case .none:
            transaction.selection = nil
            transaction.selectionInteraction = .selecting
        }
    }

    private mutating func beginDraft(
        _ transaction: inout GestureTransaction,
        tool: PointerTool,
        at point: NormalizedPoint
    ) {
        let style = toolState.style
        let geometry: MarkGeometry
        switch tool {
        case .arrow:
            geometry = .arrow(start: point, end: point)
        case .rectangle:
            geometry = .rectangle(NormalizedRect(x: point.x, y: point.y, width: 0, height: 0))
        case .ellipse:
            geometry = .ellipse(NormalizedRect(x: point.x, y: point.y, width: 0, height: 0))
        case .pen:
            geometry = .freehand([point])
        case .emoji:
            geometry = .emoji(
                text: toolState.emoji,
                rect: ResizeGeometry.clampedSquare(
                    centeredAt: point,
                    side: GestureTransaction.defaultEmojiSide
                )
            )
        case .spotlight:
            geometry = .spotlight(
                center: point,
                radius: toolState.spotlightRadius,
                dimness: toolState.spotlightDimness
            )
        case .select, .eraser:
            return
        }

        let mark = Mark(geometry: geometry, style: style)
        transaction.draftMarkID = mark.id
        transaction.previewCanvas.append(mark)
    }

    private func makeUpdate(
        from transaction: GestureTransaction,
        boundaryEvent: GestureBoundaryEvent?
    ) -> GestureUpdate {
        GestureUpdate(
            previewMarks: transaction.previewCanvas.marks,
            selection: transaction.selection,
            needsRedraw: true,
            boundaryEvent: boundaryEvent
        )
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
        if selection == markID {
            selection = nil
            selectionDisplay = nil
        }
    }

    private mutating func clear(_ display: DisplayUUID) {
        guard var canvas = canvases[display], !canvas.marks.isEmpty else {
            return
        }
        invalidateClearAllUndo()
        recordSnapshot(for: display)
        canvas.clear()
        canvases[display] = canvas
        if selectionDisplay == display {
            selection = nil
            selectionDisplay = nil
        }
    }

    private mutating func undo(on display: DisplayUUID) {
        guard var history = undoHistories[display], let snapshot = history.popLatest() else {
            return
        }
        invalidateClearAllUndo()
        undoHistories[display] = history
        canvases[display] = snapshot
        if selectionDisplay == display,
           let selection,
           !(snapshot.marks.contains { $0.id == selection })
        {
            self.selection = nil
            selectionDisplay = nil
        }
    }

    private mutating func clearAll() {
        guard canvases.values.contains(where: { !$0.marks.isEmpty }) else {
            return
        }
        clearAllSnapshot = ClearAllSnapshot(canvases: canvases, undoHistories: undoHistories)
        for display in canvases.keys {
            canvases[display] = Canvas()
        }
        selection = nil
        selectionDisplay = nil
    }

    private mutating func undoClearAll() {
        guard let clearAllSnapshot else {
            return
        }
        canvases = clearAllSnapshot.canvases
        undoHistories = clearAllSnapshot.undoHistories
        self.clearAllSnapshot = nil
    }

    private mutating func deleteSelected(
        selection pendingSelection: (id: Mark.ID, display: DisplayUUID)? = nil
    ) {
        let selectedID = pendingSelection?.id ?? selection
        let selectedDisplay = pendingSelection?.display ?? selectionDisplay
        guard let selectedID, let selectedDisplay else {
            return
        }
        remove(selectedID, from: selectedDisplay)
    }

    private mutating func updateSelectedStyle(_ transform: (Mark) -> Mark) {
        guard let selection, let selectionDisplay, var canvas = canvases[selectionDisplay],
              let mark = canvas.marks.first(where: { $0.id == selection })
        else {
            return
        }
        let updated = transform(mark)
        guard updated != mark else { return }
        invalidateClearAllUndo()
        recordSnapshot(for: selectionDisplay)
        canvas.replace(updated)
        canvases[selectionDisplay] = canvas
    }

    private mutating func recordSnapshot(for display: DisplayUUID) {
        recordSnapshot(for: display, canvas: canvas(for: display))
    }

    private mutating func recordSnapshot(for display: DisplayUUID, canvas: Canvas) {
        var history = undoHistories[display] ?? UndoHistory()
        history.record(canvas)
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
