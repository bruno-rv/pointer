import AppKit
import XCTest
@testable import MarkRenderingPrototype

@MainActor
final class CanvasViewTests: XCTestCase {
    func testSharedGestureMethodsPreserveFreehandGeometryAndUndo() {
        _ = NSApplication.shared
        let canvas = CanvasView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600)
        )
        canvas.tool = .freehand

        var states: [String] = []
        canvas.onStateChange = { states.append($0) }

        canvas.beginGesture(at: NSPoint(x: 10, y: 10))
        canvas.continueGesture(to: NSPoint(x: 20, y: 20))
        canvas.continueGesture(to: NSPoint(x: 40, y: 35))
        canvas.endGesture()

        XCTAssertEqual(canvas.marks.count, 1)
        XCTAssertTrue(states.last!.contains("marks: 1"))
        XCTAssertTrue(
            states.last!.contains("freehand 3 points, bounds [10, 10, 30×25]")
        )

        canvas.undo()
        XCTAssertEqual(canvas.marks.count, 0)
        XCTAssertTrue(states.last!.contains("marks: 0"))
        XCTAssertTrue(states.last!.contains("  (none)"))
    }

    func testMouseDownMakesCanvasFirstResponder() {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let root = NSView(frame: window.contentView!.bounds)
        let canvas = CanvasView(frame: root.bounds)
        let otherResponder = NSTextView(frame: .zero)
        root.addSubview(canvas)
        root.addSubview(otherResponder)
        window.contentView = root

        XCTAssertTrue(window.makeFirstResponder(otherResponder))
        XCTAssertTrue(window.firstResponder === otherResponder)

        let event = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 20, y: 20),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )!
        canvas.mouseDown(with: event)

        XCTAssertTrue(window.firstResponder === canvas)
    }

    func testDragBenchmarkSmokeRunExercisesRealGesturePath() throws {
        let report = DragPublicationBenchmark.run(
            configuration: .smoke,
            label: "test"
        )

        XCTAssertEqual(report.label, "test")
        XCTAssertEqual(report.fixtureID, "freehand-12-basic-240-drag")
        XCTAssertEqual(report.trials.count, 1)
        XCTAssertEqual(report.samplesPerGesture, 240)
        XCTAssertEqual(report.gesturesPerTrial, 1)
        XCTAssertFalse(report.renderTimed)
        XCTAssertFalse(report.gridTimed)
        XCTAssertFalse(report.eventDispatchTimed)
        XCTAssertTrue(report.finalStateValid)
        XCTAssertFalse(report.modelChecksum.isEmpty)
        XCTAssertFalse(report.inspectorChecksum.isEmpty)
    }

    func testDragBenchmarkTrialFlagsHeterogeneousPublicationCounts() {
        let heterogeneous = DragPublicationBenchmark.makeTrial(
            wholeGestureNanoseconds: [100, 200],
            continuationLoopNanoseconds: [80, 160],
            publications: [241, 243],
            samplesPerGesture: 240
        )
        XCTAssertFalse(heterogeneous.publicationCountsUniform)
        XCTAssertEqual(heterogeneous.publicationsPerGesture, 0)

        let task2Uniform = DragPublicationBenchmark.makeTrial(
            wholeGestureNanoseconds: [100, 200],
            continuationLoopNanoseconds: [80, 160],
            publications: [2, 2],
            samplesPerGesture: 240
        )
        XCTAssertTrue(task2Uniform.publicationCountsUniform)
        XCTAssertEqual(task2Uniform.publicationsPerGesture, 2)
    }

    func testFreehandGesturePublishesInspectorOnlyAtBoundaries() {
        _ = NSApplication.shared
        let canvas = CanvasView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600)
        )
        let window = NSWindow(
            contentRect: canvas.bounds,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = canvas
        canvas.tool = .freehand

        var states: [String] = []
        canvas.onStateChange = { states.append($0) }

        canvas.beginGesture(at: NSPoint(x: 10, y: 10))
        let publicationsAfterBegin = states.count

        canvas.needsDisplay = false
        canvas.continueGesture(to: NSPoint(x: 20, y: 20))
        XCTAssertEqual(states.count, publicationsAfterBegin)
        XCTAssertTrue(canvas.needsDisplay)

        canvas.needsDisplay = false
        canvas.continueGesture(to: NSPoint(x: 40, y: 35))
        XCTAssertEqual(states.count, publicationsAfterBegin)
        XCTAssertTrue(canvas.needsDisplay)

        canvas.endGesture()

        XCTAssertEqual(states.count, publicationsAfterBegin + 1)
        XCTAssertEqual(canvas.marks.count, 1)
        XCTAssertTrue(states.last!.contains("marks: 1"))
        XCTAssertTrue(
            states.last!.contains("freehand 3 points, bounds [10, 10, 30×25]")
        )

        canvas.undo()
        XCTAssertEqual(canvas.marks.count, 0)
        XCTAssertTrue(states.last!.contains("marks: 0"))
    }
}
