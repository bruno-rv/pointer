import XCTest
@testable import PointerCore

final class GestureTransactionTests: XCTestCase {
    private let display = DisplayUUID(rawValue: "gesture-display")

    /// Cancel must restore the exact pre-gesture canvas and must not push undo.
    func testCancelledShapeRestoresCanvasWithoutUndoEntry() {
        var session = PointerSession()
        session.apply(.setMode(.annotation))
        session.apply(.setTool(.rectangle))

        let existing = Mark(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
            geometry: .arrow(
                start: NormalizedPoint(x: 0.1, y: 0.1),
                end: NormalizedPoint(x: 0.2, y: 0.2)
            ),
            style: .default
        )
        session.apply(.append(existing, to: display))

        _ = session.beginGesture(tool: .rectangle, at: NormalizedPoint(x: 0.3, y: 0.3), on: display)
        _ = session.advanceGesture(to: NormalizedPoint(x: 0.6, y: 0.7))

        XCTAssertEqual(session.previewCanvas(for: display).marks.count, 2)

        let cancellation = session.cancelGesture()

        XCTAssertEqual(cancellation.boundaryEvent, .cancelled)
        XCTAssertEqual(session.canvas(for: display).marks, [existing])
        XCTAssertEqual(session.previewCanvas(for: display).marks, [existing])

        // Cancel must not push undo; the only snapshot is from append, so undo clears.
        session.apply(.undo(on: display))
        XCTAssertTrue(session.canvas(for: display).marks.isEmpty)
    }

    /// Zero-length commits are discarded and create no undo entry.
    func testZeroLengthShapeCommitIsDiscardedWithoutUndoEntry() {
        var session = PointerSession()
        session.apply(.setMode(.annotation))

        let start = NormalizedPoint(x: 0.4, y: 0.4)
        _ = session.beginGesture(tool: .arrow, at: start, on: display)
        let commit = session.commitGesture()

        XCTAssertFalse(commit.didMutate)
        XCTAssertEqual(commit.boundaryEvent, .committed)
        XCTAssertTrue(session.canvas(for: display).marks.isEmpty)

        session.apply(.undo(on: display))
        XCTAssertTrue(session.canvas(for: display).marks.isEmpty)

        _ = session.beginGesture(tool: .rectangle, at: start, on: display)
        XCTAssertFalse(session.commitGesture().didMutate)
        XCTAssertTrue(session.canvas(for: display).marks.isEmpty)

        _ = session.beginGesture(tool: .pen, at: start, on: display)
        XCTAssertFalse(session.commitGesture().didMutate)
        XCTAssertTrue(session.canvas(for: display).marks.isEmpty)
    }

    func testSamePointPenAdvanceIsDiscardedWithoutUndoEntry() {
        var session = PointerSession()
        session.apply(.setMode(.annotation))

        let start = NormalizedPoint(x: 0.4, y: 0.4)
        _ = session.beginGesture(tool: .pen, at: start, on: display)
        _ = session.advanceGesture(to: start)

        let commit = session.commitGesture()

        XCTAssertFalse(commit.didMutate)
        XCTAssertTrue(session.canvas(for: display).marks.isEmpty)
        XCTAssertFalse(session.canUndo(on: display))
    }

    /// Freehand points accumulate on the gesture-local draft only until commit.
    func testFreehandAdvanceAppendsToGestureLocalDraft() {
        var session = PointerSession()
        session.apply(.setMode(.annotation))

        let p0 = NormalizedPoint(x: 0.1, y: 0.1)
        let p1 = NormalizedPoint(x: 0.2, y: 0.25)
        let p2 = NormalizedPoint(x: 0.35, y: 0.2)

        _ = session.beginGesture(tool: .pen, at: p0, on: display)
        _ = session.advanceGesture(to: p1)
        _ = session.advanceGesture(to: p2)

        XCTAssertTrue(session.canvas(for: display).marks.isEmpty)

        let preview = session.previewCanvas(for: display).marks
        XCTAssertEqual(preview.count, 1)
        guard case let .freehand(points) = preview[0].geometry else {
            return XCTFail("Expected freehand draft")
        }
        XCTAssertEqual(points, [p0, p1, p2])

        let commit = session.commitGesture()
        XCTAssertTrue(commit.didMutate)
        XCTAssertEqual(session.canvas(for: display).marks.count, 1)
        guard case let .freehand(committed) = session.canvas(for: display).marks[0].geometry else {
            return XCTFail("Expected committed freehand")
        }
        XCTAssertEqual(committed, [p0, p1, p2])
    }

    /// Begin and commit/cancel publish boundary events; advance does not.
    func testBeginAndCommitReturnBoundaryEventsButAdvanceDoesNot() {
        var session = PointerSession()
        session.apply(.setMode(.annotation))

        let began = session.beginGesture(
            tool: .ellipse,
            at: NormalizedPoint(x: 0.2, y: 0.2),
            on: display
        )
        XCTAssertEqual(began.boundaryEvent, .began)
        XCTAssertTrue(began.needsRedraw)

        let advanced = session.advanceGesture(to: NormalizedPoint(x: 0.5, y: 0.4))
        XCTAssertNil(advanced.boundaryEvent)
        XCTAssertTrue(advanced.needsRedraw)

        let commit = session.commitGesture()
        XCTAssertEqual(commit.boundaryEvent, .committed)

        let began2 = session.beginGesture(
            tool: .ellipse,
            at: NormalizedPoint(x: 0.1, y: 0.1),
            on: display
        )
        XCTAssertEqual(began2.boundaryEvent, .began)
        let cancellation = session.cancelGesture()
        XCTAssertEqual(cancellation.boundaryEvent, .cancelled)
    }

    /// Eraser uses the swept segment between samples, not only discrete hits.
    func testSparseEraserSamplesRemoveMarkCrossedBySweptSegment() {
        var session = PointerSession()
        session.apply(.setMode(.annotation))

        let blocking = Mark(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000020")!,
            geometry: .arrow(
                start: NormalizedPoint(x: 0.5, y: 0.35),
                end: NormalizedPoint(x: 0.5, y: 0.65)
            ),
            style: .default
        )
        session.apply(.append(blocking, to: display))

        let begin = session.beginGesture(
            tool: .eraser,
            at: NormalizedPoint(x: 0.1, y: 0.5),
            on: display
        )
        XCTAssertEqual(begin.previewMarks.map(\.id), [blocking.id])

        let advanced = session.advanceGesture(to: NormalizedPoint(x: 0.9, y: 0.5))
        XCTAssertTrue(advanced.previewMarks.isEmpty)
        XCTAssertTrue(session.canvas(for: display).marks.map(\.id) == [blocking.id])

        let commit = session.commitGesture()
        XCTAssertTrue(commit.didMutate)
        XCTAssertTrue(session.canvas(for: display).marks.isEmpty)
    }

    /// Emoji click uses the 0.08 default square; drag grows a square extent.
    func testEmojiClickUsesDefaultSquareAndDragUsesSquareExtent() {
        var session = PointerSession()
        session.apply(.setMode(.annotation))
        session.apply(.setEmoji("⭐️"))

        let click = NormalizedPoint(x: 0.5, y: 0.5)
        _ = session.beginGesture(tool: .emoji, at: click, on: display)
        let clickCommit = session.commitGesture()
        XCTAssertTrue(clickCommit.didMutate)

        guard case let .emoji(text, clickRect) = session.canvas(for: display).marks[0].geometry else {
            return XCTFail("Expected emoji mark")
        }
        XCTAssertEqual(text, "⭐️")
        XCTAssertEqual(clickRect.width, 0.08, accuracy: 1e-9)
        XCTAssertEqual(clickRect.height, 0.08, accuracy: 1e-9)
        XCTAssertEqual(clickRect.x, 0.46, accuracy: 1e-9)
        XCTAssertEqual(clickRect.y, 0.46, accuracy: 1e-9)

        session.apply(.clear(display))

        let start = NormalizedPoint(x: 0.4, y: 0.4)
        _ = session.beginGesture(tool: .emoji, at: start, on: display)
        _ = session.advanceGesture(to: NormalizedPoint(x: 0.55, y: 0.5))
        let dragCommit = session.commitGesture()
        XCTAssertTrue(dragCommit.didMutate)

        guard case let .emoji(_, dragRect) = session.canvas(for: display).marks[0].geometry else {
            return XCTFail("Expected dragged emoji mark")
        }
        XCTAssertEqual(dragRect.width, dragRect.height, accuracy: 1e-9)
        XCTAssertEqual(dragRect.width, 0.3, accuracy: 1e-9)
        XCTAssertEqual(dragRect.x, 0.25, accuracy: 1e-9)
        XCTAssertEqual(dragRect.y, 0.25, accuracy: 1e-9)
    }

    /// One eraser drag records a single undo snapshot for every removal.
    func testEraserDragCreatesOneUndoSnapshot() {
        var session = PointerSession()
        session.apply(.setMode(.annotation))

        let first = Mark(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000030")!,
            geometry: .rectangle(NormalizedRect(x: 0.1, y: 0.1, width: 0.1, height: 0.1)),
            style: .default
        )
        let second = Mark(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000031")!,
            geometry: .rectangle(NormalizedRect(x: 0.4, y: 0.1, width: 0.1, height: 0.1)),
            style: .default
        )
        session.apply(.append(first, to: display))
        session.apply(.append(second, to: display))

        _ = session.beginGesture(tool: .eraser, at: NormalizedPoint(x: 0.15, y: 0.15), on: display)
        _ = session.advanceGesture(to: NormalizedPoint(x: 0.45, y: 0.15))
        XCTAssertTrue(session.commitGesture().didMutate)
        XCTAssertTrue(session.canvas(for: display).marks.isEmpty)

        session.apply(.undo(on: display))
        XCTAssertEqual(session.canvas(for: display).marks.map(\.id), [first.id, second.id])

        session.apply(.undo(on: display))
        XCTAssertEqual(session.canvas(for: display).marks.map(\.id), [first.id])
    }

    /// Entering standby cancels an open gesture before changing mode.
    func testModeChangeCancelsActiveGestureBeforeStandby() {
        var session = PointerSession()
        session.apply(.setMode(.annotation))

        let existing = Mark(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000040")!,
            geometry: .ellipse(NormalizedRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)),
            style: .default
        )
        session.apply(.append(existing, to: display))

        _ = session.beginGesture(tool: .rectangle, at: NormalizedPoint(x: 0.5, y: 0.5), on: display)
        _ = session.advanceGesture(to: NormalizedPoint(x: 0.8, y: 0.9))
        XCTAssertEqual(session.previewCanvas(for: display).marks.count, 2)

        session.apply(.setMode(.standby))

        XCTAssertEqual(session.mode, .standby)
        XCTAssertEqual(session.canvas(for: display).marks, [existing])
        XCTAssertEqual(session.previewCanvas(for: display).marks, [existing])

        // Standby cancel must not push undo; undoing only reverses the append.
        session.apply(.undo(on: display))
        XCTAssertTrue(session.canvas(for: display).marks.isEmpty)
    }

    /// GestureUpdate exposes preview marks and selection for renderers.
    func testSelectHitTestsTopmostAndClearsOnEmptyCanvasClick() {
        var session = PointerSession()
        session.apply(.setMode(.annotation))

        let bottom = Mark(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000050")!,
            geometry: .rectangle(NormalizedRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)),
            style: .default
        )
        let top = Mark(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000051")!,
            geometry: .rectangle(NormalizedRect(x: 0.3, y: 0.3, width: 0.2, height: 0.2)),
            style: .default
        )
        session.apply(.append(bottom, to: display))
        session.apply(.append(top, to: display))

        let selectTop = session.beginGesture(
            tool: .select,
            at: NormalizedPoint(x: 0.4, y: 0.4),
            on: display
        )
        XCTAssertEqual(selectTop.selection, top.id)
        _ = session.commitGesture()
        XCTAssertEqual(session.selection, top.id)

        let clear = session.beginGesture(
            tool: .select,
            at: NormalizedPoint(x: 0.05, y: 0.05),
            on: display
        )
        XCTAssertNil(clear.selection)
        _ = session.commitGesture()
        XCTAssertNil(session.selection)
    }

    /// Non-meaningful draw commit must restore selectionDisplay with selection,
    /// or deleteSelected / style-on-selection silently no-op.
    func testDiscardedDrawCommitRestoresSelectionDisplayForDeleteAndStyle() {
        var session = PointerSession()
        session.apply(.setMode(.annotation))

        let existing = Mark(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000080")!,
            geometry: .rectangle(NormalizedRect(x: 0.2, y: 0.2, width: 0.3, height: 0.3)),
            style: .default
        )
        session.apply(.append(existing, to: display))

        _ = session.beginGesture(tool: .select, at: NormalizedPoint(x: 0.35, y: 0.35), on: display)
        _ = session.commitGesture()
        XCTAssertEqual(session.selection, existing.id)

        let start = NormalizedPoint(x: 0.7, y: 0.7)
        _ = session.beginGesture(tool: .arrow, at: start, on: display)
        let commit = session.commitGesture()
        XCTAssertFalse(commit.didMutate)
        XCTAssertEqual(session.selection, existing.id)

        session.apply(.setStyle(MarkStyle(color: .red, strokeWidth: 8, opacity: 0.5)))
        guard let styled = session.canvas(for: display).marks.first(where: { $0.id == existing.id }) else {
            return XCTFail("Expected selected mark to remain")
        }
        XCTAssertEqual(styled.style.strokeWidth, 8)
        XCTAssertEqual(styled.style.opacity, 0.5)

        session.apply(.deleteSelected)
        XCTAssertTrue(session.canvas(for: display).marks.isEmpty)
        XCTAssertNil(session.selection)
    }

    /// Cancel must restore selectionDisplay from the pre-gesture display,
    /// not the gesture's display, when selection lived elsewhere.
    func testCancelRestoresSelectionDisplayFromPriorDisplay() {
        let other = DisplayUUID(rawValue: "other-display")
        var session = PointerSession()
        session.apply(.setMode(.annotation))

        let selected = Mark(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000081")!,
            geometry: .rectangle(NormalizedRect(x: 0.2, y: 0.2, width: 0.2, height: 0.2)),
            style: .default
        )
        session.apply(.append(selected, to: other))

        _ = session.beginGesture(tool: .select, at: NormalizedPoint(x: 0.3, y: 0.3), on: other)
        _ = session.commitGesture()
        XCTAssertEqual(session.selection, selected.id)

        _ = session.beginGesture(tool: .rectangle, at: NormalizedPoint(x: 0.1, y: 0.1), on: display)
        _ = session.advanceGesture(to: NormalizedPoint(x: 0.4, y: 0.4))
        _ = session.cancelGesture()

        XCTAssertEqual(session.selection, selected.id)

        session.apply(.deleteSelected)
        XCTAssertTrue(session.canvas(for: other).marks.isEmpty)
        XCTAssertEqual(session.canvas(for: display).marks.count, 0)
        XCTAssertNil(session.selection)
    }

    /// Handle press + advance to the same point must not create a no-op undo entry.
    func testNoOpResizeAdvanceDoesNotCreateUndoSnapshot() {
        var session = PointerSession()
        session.apply(.setMode(.annotation))

        let mark = Mark(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000082")!,
            geometry: .rectangle(NormalizedRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)),
            style: .default
        )
        session.apply(.append(mark, to: display))

        _ = session.beginGesture(tool: .select, at: NormalizedPoint(x: 0.4, y: 0.4), on: display)
        _ = session.commitGesture()
        XCTAssertEqual(session.selection, mark.id)

        let handle = NormalizedPoint(x: 0.2, y: 0.2)
        _ = session.beginGesture(tool: .select, at: handle, on: display)
        _ = session.advanceGesture(to: handle)
        let commit = session.commitGesture()
        XCTAssertFalse(commit.didMutate)
        XCTAssertEqual(session.canvas(for: display).marks[0].geometry, mark.geometry)

        session.apply(.undo(on: display))
        XCTAssertTrue(session.canvas(for: display).marks.isEmpty)
    }
}
