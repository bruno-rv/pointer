import AppKit
import CoreGraphics
import CryptoKit
import PointerCore
import XCTest
@testable import PointerAppKit

@MainActor
final class CanvasViewRenderIntegrationTests: XCTestCase {
    private let display = DisplayUUID(rawValue: "render-integration-display")

    func testSelectedRectangleCachesVisibleResizeHandlesAndRendersThem() throws {
        let mark = VisualFixtures.canonicalMark()
        var session = annotationSession()
        session.apply(.append(mark, to: display))
        let view = CanvasView(
            frame: CGRect(x: 0, y: 0, width: 512, height: 512),
            display: display,
            session: session,
            tool: .select
        )
        let window = attachNonVisibleWindow(to: view)

        XCTAssertFalse(window.isVisible)
        XCTAssertNil(view.renderPlan.activeDraft)
        XCTAssertFalse(view.renderPlan.handles.selection.isVisible)

        view.beginGesture(at: CGPoint(x: 256, y: 256))
        view.endGesture()

        XCTAssertEqual(view.renderPlan.handles.selection.selectedMarkID, mark.id)
        XCTAssertTrue(view.renderPlan.handles.selection.isVisible)
        XCTAssertEqual(
            view.renderPlan.handles.resize.handles,
            ResizeGeometry.handles(for: mark.geometry)
        )
        XCTAssertTrue(view.renderPlan.handles.resize.isVisible)
        let pixels = try render(view)
        for center in [(128, 128), (384, 128), (128, 384), (384, 384)] {
            XCTAssertTrue(
                containsOpaqueWhiteOrBlack(
                    pixels,
                    width: 512,
                    height: 512,
                    centerX: center.0,
                    centerY: center.1,
                    radius: 9,
                    tolerance: 1
                ),
                "missing handle sentinel near (\(center.0), \(center.1))"
            )
        }
        XCTAssertFalse(window.isVisible)
    }

    func testSelectedRectangleEnteringStandbyKeepsOnlyCommittedPixelsAndDigest() throws {
        let mark = VisualFixtures.canonicalMark()
        var session = annotationSession()
        session.apply(.append(mark, to: display))
        let view = CanvasView(
            frame: CGRect(x: 0, y: 0, width: 512, height: 512),
            display: display,
            session: session,
            tool: .select
        )
        _ = attachNonVisibleWindow(to: view)
        view.beginGesture(at: CGPoint(x: 256, y: 256))
        view.endGesture()

        var standby = view.session
        standby.apply(.setMode(.standby))
        view.update(session: standby)

        XCTAssertEqual(view.renderPlan.committedMarks, [mark])
        XCTAssertNil(view.renderPlan.activeDraft)
        XCTAssertFalse(view.renderPlan.handles.selection.isVisible)
        XCTAssertFalse(view.renderPlan.handles.resize.isVisible)
        XCTAssertFalse(view.renderPlan.handles.hover.isVisible)
        XCTAssertFalse(view.renderPlan.handles.contextualDeleteVisible)
        let pixels = try render(view)
        XCTAssertGreaterThan(alpha(in: pixels, width: 512, x: 256, y: 128), 0)
        XCTAssertGreaterThan(alpha(in: pixels, width: 512, x: 128, y: 256), 0)
        XCTAssertEqual(VisualFixtures.sha256(pixels), VisualFixtures.expectedStandbyDigest)
        for center in [(128, 128), (384, 128), (128, 384), (384, 384)] {
            XCTAssertFalse(
                containsOpaqueWhiteOrBlack(
                    pixels,
                    width: 512,
                    height: 512,
                    centerX: center.0,
                    centerY: center.1,
                    radius: 9,
                    tolerance: 1
                ),
                "unexpected handle sentinel near (\(center.0), \(center.1))"
            )
        }
    }

    func testAnnotationReentryIsUnselectedUntilExplicitReselect() throws {
        let mark = VisualFixtures.canonicalMark()
        var session = annotationSession()
        session.apply(.append(mark, to: display))
        let view = CanvasView(
            frame: CGRect(x: 0, y: 0, width: 512, height: 512),
            display: display,
            session: session,
            tool: .select
        )
        _ = attachNonVisibleWindow(to: view)
        view.beginGesture(at: CGPoint(x: 256, y: 256))
        view.endGesture()

        var standby = view.session
        standby.apply(.setMode(.standby))
        view.update(session: standby)
        var reentered = view.session
        reentered.apply(.setMode(.annotation))
        view.update(session: reentered)

        XCTAssertEqual(view.renderPlan.committedMarks, [mark])
        XCTAssertNil(view.renderPlan.handles.selection.selectedMarkID)
        XCTAssertFalse(view.renderPlan.handles.selection.isVisible)
        XCTAssertFalse(view.renderPlan.handles.resize.isVisible)
        let reentryPixels = try render(view)
        XCTAssertFalse(
            containsOpaqueWhiteOrBlack(
                reentryPixels,
                width: 512,
                height: 512,
                centerX: 128,
                centerY: 128,
                radius: 9,
                tolerance: 1
            )
        )

        view.beginGesture(at: CGPoint(x: 256, y: 256))
        view.endGesture()

        XCTAssertEqual(view.renderPlan.handles.selection.selectedMarkID, mark.id)
        XCTAssertTrue(view.renderPlan.handles.selection.isVisible)
        XCTAssertTrue(view.renderPlan.handles.resize.isVisible)
    }

    func testActiveDraftIsCachedOncePerRedrawAndRemovedOnCommitOrCancel() throws {
        let view = CanvasView(
            frame: CGRect(x: 0, y: 0, width: 512, height: 512),
            display: display,
            session: annotationSession(),
            tool: .rectangle
        )
        _ = attachNonVisibleWindow(to: view)
        var observedPlans: [RenderPlan] = []
        var observedSessionPlans: [RenderPlan] = []
        var observedBoundaryEvents: [GestureBoundaryEvent] = []
        var observedBoundaryPlans: [RenderPlan] = []
        var callbackOrder: [String] = []
        view.onRedrawRequested = {
            callbackOrder.append("redraw")
            observedPlans.append(view.renderPlan)
        }
        view.onSessionUpdate = { _ in
            callbackOrder.append("session")
            observedSessionPlans.append(view.renderPlan)
        }
        view.onBoundaryEvent = { event in
            callbackOrder.append("boundary")
            observedBoundaryEvents.append(event)
            observedBoundaryPlans.append(view.renderPlan)
        }

        view.beginGesture(at: CGPoint(x: 128, y: 128))
        view.continueGesture(to: CGPoint(x: 384, y: 384))

        XCTAssertEqual(observedPlans.count, 2)
        XCTAssertEqual(observedPlans.compactMap(\.activeDraft).count, 2)
        XCTAssertTrue(observedPlans.allSatisfy { $0.committedMarks.isEmpty })
        XCTAssertEqual(Set(observedPlans.compactMap(\.activeDraft).map(\.id)).count, 1)
        XCTAssertEqual(observedSessionPlans.count, 1)
        XCTAssertNotNil(observedSessionPlans[0].activeDraft)
        XCTAssertEqual(observedBoundaryEvents, [.began])
        XCTAssertNotNil(observedBoundaryPlans[0].activeDraft)
        XCTAssertEqual(callbackOrder, ["redraw", "session", "boundary", "redraw"])
        XCTAssertEqual(view.renderPlan.committedMarks, [])
        XCTAssertNotNil(view.renderPlan.activeDraft)

        view.endGesture()

        XCTAssertEqual(observedSessionPlans.count, 2)
        XCTAssertNil(observedSessionPlans[1].activeDraft)
        XCTAssertEqual(observedSessionPlans[1].committedMarks.count, 1)
        XCTAssertEqual(observedBoundaryEvents, [.began, .committed])
        XCTAssertNil(observedBoundaryPlans[1].activeDraft)
        XCTAssertEqual(observedBoundaryPlans[1].committedMarks.count, 1)
        XCTAssertEqual(
            callbackOrder,
            ["redraw", "session", "boundary", "redraw", "redraw", "session", "boundary"]
        )
        XCTAssertNil(view.renderPlan.activeDraft)
        XCTAssertEqual(view.renderPlan.committedMarks.count, 1)

        view.beginGesture(at: CGPoint(x: 100, y: 100))
        view.continueGesture(to: CGPoint(x: 200, y: 200))
        XCTAssertNotNil(view.renderPlan.activeDraft)
        view.cancelGesture()

        XCTAssertEqual(observedSessionPlans.count, 4)
        XCTAssertNil(observedSessionPlans[3].activeDraft)
        XCTAssertEqual(observedSessionPlans[3].committedMarks.count, 1)
        XCTAssertEqual(observedBoundaryEvents, [.began, .committed, .began, .cancelled])
        XCTAssertNil(observedBoundaryPlans[3].activeDraft)
        XCTAssertEqual(observedBoundaryPlans[3].committedMarks.count, 1)
        XCTAssertEqual(observedPlans.count, 6)
        XCTAssertEqual(
            callbackOrder,
            [
                "redraw", "session", "boundary", "redraw", "redraw", "session", "boundary",
                "redraw", "session", "boundary", "redraw", "redraw", "session", "boundary",
            ]
        )
        XCTAssertNil(view.renderPlan.activeDraft)
        XCTAssertEqual(view.renderPlan.committedMarks.count, 1)
    }

    func testExternalSessionUpdateRecomputesCommittedRenderPlan() {
        let view = CanvasView(
            frame: CGRect(x: 0, y: 0, width: 512, height: 512),
            display: display,
            session: annotationSession(),
            tool: .arrow
        )
        _ = attachNonVisibleWindow(to: view)
        let mark = VisualFixtures.canonicalMark()
        var updated = view.session
        updated.apply(.append(mark, to: display))

        view.update(session: updated)

        XCTAssertEqual(view.renderPlan.committedMarks, [mark])
        XCTAssertNil(view.renderPlan.activeDraft)
        XCTAssertEqual(view.session, updated)
    }

    func testCanvasViewUsesCachedPlanRendererAndNoLegacyCanvasOverload() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = root.appendingPathComponent("Sources/PointerAppKit/CanvasView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        let planCallPattern = #"MarkRenderer\s*\.\s*draw\s*\(\s*plan\s*:"#
        let legacyCallPattern = #"MarkRenderer\s*\.\s*draw\s*\(\s*canvas\s*:"#
        XCTAssertNotNil(source.range(of: planCallPattern, options: .regularExpression))
        XCTAssertNil(source.range(of: legacyCallPattern, options: .regularExpression))
    }

    private func annotationSession() -> PointerSession {
        var session = PointerSession()
        session.apply(.setMode(.annotation))
        return session
    }

    @discardableResult
    private func attachNonVisibleWindow(to view: CanvasView) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: view.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        return window
    }

    private func render(_ view: CanvasView) throws -> [UInt8] {
        let width = Int(view.bounds.width.rounded())
        let height = Int(view.bounds.height.rounded())
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { rawBuffer in
            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                      data: rawBuffer.baseAddress,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: width * 4,
                      space: colorSpace,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  )
            else {
                throw BitmapError.cannotCreateContext
            }

            let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphicsContext
            view.draw(view.bounds)
            NSGraphicsContext.restoreGraphicsState()
        }
        return pixels
    }

    private func alpha(in pixels: [UInt8], width: Int, x: Int, y: Int) -> UInt8 {
        pixels[(y * width + x) * 4 + 3]
    }

    private func containsOpaqueWhiteOrBlack(
        _ pixels: [UInt8],
        width: Int,
        height: Int,
        centerX: Int,
        centerY: Int,
        radius: Int,
        tolerance: Int
    ) -> Bool {
        let minX = max(0, centerX - radius - tolerance)
        let maxX = min(width - 1, centerX + radius + tolerance)
        let minY = max(0, centerY - radius - tolerance)
        let maxY = min(height - 1, centerY + radius + tolerance)
        for y in minY...maxY {
            for x in minX...maxX {
                let offset = (y * width + x) * 4
                let red = pixels[offset]
                let green = pixels[offset + 1]
                let blue = pixels[offset + 2]
                let alpha = pixels[offset + 3]
                let opaque = alpha >= 250
                let white = red >= 250 && green >= 250 && blue >= 250
                let black = red <= 5 && green <= 5 && blue <= 5
                if opaque && (white || black) {
                    return true
                }
            }
        }
        return false
    }

    private enum BitmapError: Error {
        case cannotCreateContext
    }
}
