import CoreGraphics
import PointerCore
import XCTest
@testable import PointerAppKit

final class RenderPlanTests: XCTestCase {
    func testStandbyRenderPlanKeepsMarksButClearsSelectionHoverResizeAndDelete() {
        let mark = VisualFixtures.canonicalMark()
        let canvas = VisualFixtures.canonicalCanvas()

        let standby = RenderPlan.make(
            canvas: canvas,
            mode: .standby,
            selectedID: mark.id,
            activeDraft: mark,
            hover: HoverInventory(hoveredMarkID: mark.id, isVisible: true)
        )

        XCTAssertEqual(standby.committedMarks, canvas.marks)
        XCTAssertNil(standby.activeDraft)
        XCTAssertNil(standby.handles.selection.selectedMarkID)
        XCTAssertFalse(standby.handles.selection.isVisible)
        XCTAssertNil(standby.handles.hover.hoveredMarkID)
        XCTAssertFalse(standby.handles.hover.isVisible)
        XCTAssertTrue(standby.handles.resize.handles.isEmpty)
        XCTAssertFalse(standby.handles.resize.isVisible)
        XCTAssertFalse(standby.handles.contextualDeleteVisible)
    }

    func testAnnotationSelectionRestoresSelectionAndResizeInventory() {
        let mark = VisualFixtures.canonicalMark()
        let annotation = RenderPlan.make(
            canvas: VisualFixtures.canonicalCanvas(),
            mode: .annotation,
            selectedID: mark.id,
            activeDraft: nil,
            hover: HoverInventory(hoveredMarkID: mark.id, isVisible: true)
        )

        XCTAssertEqual(annotation.handles.selection.selectedMarkID, mark.id)
        XCTAssertTrue(annotation.handles.selection.isVisible)
        XCTAssertEqual(annotation.handles.hover, HoverInventory(hoveredMarkID: mark.id, isVisible: true))
        XCTAssertFalse(annotation.handles.resize.handles.isEmpty)
        XCTAssertTrue(annotation.handles.resize.isVisible)
        XCTAssertTrue(annotation.handles.contextualDeleteVisible)
    }

    func testAnnotationInventoryFailsClosedForUnknownSelectionAndHover() {
        let unknownSelectionID = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
        let unknownHoverID = UUID(uuidString: "00000000-0000-0000-0000-000000000203")!
        let plan = RenderPlan.make(
            canvas: VisualFixtures.canonicalCanvas(),
            mode: .annotation,
            selectedID: unknownSelectionID,
            activeDraft: nil,
            hover: HoverInventory(hoveredMarkID: unknownHoverID, isVisible: true)
        )

        XCTAssertNil(plan.handles.selection.selectedMarkID)
        XCTAssertFalse(plan.handles.selection.isVisible)
        XCTAssertNil(plan.handles.hover.hoveredMarkID)
        XCTAssertFalse(plan.handles.hover.isVisible)
        XCTAssertTrue(plan.handles.resize.handles.isEmpty)
        XCTAssertFalse(plan.handles.resize.isVisible)
        XCTAssertFalse(plan.handles.contextualDeleteVisible)
    }

    func testPreviewCanvasSourceOfTruthPartitionsActiveDraftWithoutDoubleBlend() throws {
        let display = DisplayUUID(rawValue: "preview-fixture-display")
        let committed = Mark(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000205")!,
            geometry: .rectangle(NormalizedRect(x: 0.05, y: 0.05, width: 0.1, height: 0.1)),
            style: .default
        )
        let draftStyle = MarkStyle(
            color: RGBAColor(red: 0, green: 0, blue: 1),
            strokeWidth: 8,
            opacity: 0.5
        )
        var session = PointerSession()
        session.apply(.setMode(.annotation))
        session.apply(.append(committed, to: display))
        session.apply(.setStyle(draftStyle))
        _ = session.beginGesture(
            tool: .rectangle,
            at: NormalizedPoint(x: 0.25, y: 0.125),
            on: display
        )
        _ = session.advanceGesture(to: NormalizedPoint(x: 0.75, y: 0.375))

        let committedCanvas = session.canvas(for: display)
        let previewCanvas = session.previewCanvas(for: display)
        let draft = try XCTUnwrap(
            previewCanvas.marks.first(where: { mark in
                !committedCanvas.marks.contains(where: { $0.id == mark.id })
            })
        )
        XCTAssertEqual(previewCanvas.marks.count, committedCanvas.marks.count + 1)

        let plan = RenderPlan.make(
            canvas: previewCanvas,
            mode: .annotation,
            selectedID: nil,
            activeDraft: draft,
            hover: HoverInventory(hoveredMarkID: nil, isVisible: false)
        )
        XCTAssertEqual(plan.committedMarks, committedCanvas.marks)
        XCTAssertEqual(plan.activeDraft, draft)
        XCTAssertEqual(plan.activeDraft?.style, draftStyle)

        let pixels = try render(plan: plan, width: 512, height: 512)
        let edge = pixel(in: pixels, width: 512, x: 256, y: 448)
        XCTAssertEqual(edge.alpha, UInt8(128))
        XCTAssertGreaterThan(edge.blue, edge.red)
        XCTAssertGreaterThan(edge.blue, edge.green)
        XCTAssertEqual(pixel(in: pixels, width: 512, x: 256, y: 456).alpha, 0)
        XCTAssertEqual(pixel(in: pixels, width: 512, x: 256, y: 312).alpha, 0)
        XCTAssertEqual(pixel(in: pixels, width: 512, x: 128, y: 384).alpha, 128)
        XCTAssertEqual(pixel(in: pixels, width: 512, x: 120, y: 384).alpha, 0)
        XCTAssertEqual(pixel(in: pixels, width: 512, x: 384, y: 384).alpha, 128)
        XCTAssertEqual(pixel(in: pixels, width: 512, x: 392, y: 384).alpha, 0)
    }

    func testRendererRequiresVisibleSelectionBeforeResizeHandles() throws {
        let mark = VisualFixtures.canonicalMark()
        let handles = ResizeGeometry.handles(for: mark.geometry)
        let plan = RenderPlan(
            committedMarks: [mark],
            activeDraft: nil,
            handles: HandleInventory(
                selection: SelectionInventory(selectedMarkID: mark.id, isVisible: false),
                hover: HoverInventory(hoveredMarkID: nil, isVisible: false),
                resize: ResizeInventory(handles: handles, isVisible: true),
                contextualDeleteVisible: false
            )
        )
        let pixels = try render(plan: plan, width: 512, height: 512)

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

    func testOffscreenAnnotationFixturesCoverAppearanceDensityAndBounds() throws {
        let display = DisplayUUID(rawValue: "bounds-fixture-display")
        var denseSession = PointerSession()
        let canonical = VisualFixtures.canonicalMark()
        denseSession.apply(.append(canonical, to: display))
        for index in 1...8 {
            let mark = Mark(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", 300 + index))!,
                geometry: .arrow(
                    start: NormalizedPoint(x: 0.05, y: 0.75 + Double(index) * 0.02),
                    end: NormalizedPoint(x: 0.15, y: 0.75 + Double(index) * 0.02)
                ),
                style: .default
            )
            denseSession.apply(.append(mark, to: display))
        }
        let denseCanvas = denseSession.canvas(for: display)

        struct Fixture {
            let name: String
            let width: Int
            let height: Int
            let background: (red: UInt8, green: UInt8, blue: UInt8)
            let canvas: Canvas
        }
        let fixtures = [
            Fixture(name: "light", width: 512, height: 512, background: (255, 255, 255), canvas: VisualFixtures.canonicalCanvas()),
            Fixture(name: "dark", width: 512, height: 512, background: (0, 0, 0), canvas: VisualFixtures.canonicalCanvas()),
            Fixture(name: "increase-contrast", width: 320, height: 180, background: (255, 255, 255), canvas: VisualFixtures.canonicalCanvas()),
            Fixture(name: "reduce-transparency", width: 1280, height: 720, background: (32, 32, 32), canvas: VisualFixtures.canonicalCanvas()),
            Fixture(name: "dense-canvas", width: 512, height: 512, background: (255, 255, 255), canvas: denseCanvas),
            Fixture(name: "full-screen-content", width: 1920, height: 1080, background: (0, 0, 0), canvas: VisualFixtures.canonicalCanvas()),
        ]

        for fixture in fixtures {
            let plan = RenderPlan.make(
                canvas: fixture.canvas,
                mode: .annotation,
                selectedID: nil,
                activeDraft: nil,
                hover: HoverInventory(hoveredMarkID: nil, isVisible: false)
            )
            let pixels = try render(
                plan: plan,
                width: fixture.width,
                height: fixture.height,
                background: fixture.background
            )
            let edgeY = fixture.height / 4
            let actualMarkPixel = pixel(in: pixels, width: fixture.width, x: fixture.width / 2, y: edgeY)
            XCTAssertGreaterThanOrEqual(actualMarkPixel.red, UInt8(240), fixture.name)
            XCTAssertLessThan(actualMarkPixel.green, UInt8(64), fixture.name)
            XCTAssertEqual(actualMarkPixel.blue, UInt8(0), fixture.name)
            XCTAssertEqual(actualMarkPixel.alpha, UInt8(255), fixture.name)
            let outsidePixel = pixel(in: pixels, width: fixture.width, x: fixture.width / 2, y: edgeY - 8)
            let emptyPlan = RenderPlan.make(
                canvas: Canvas(),
                mode: .annotation,
                selectedID: nil,
                activeDraft: nil,
                hover: HoverInventory(hoveredMarkID: nil, isVisible: false)
            )
            let backgroundPixels = try render(
                plan: emptyPlan,
                width: fixture.width,
                height: fixture.height,
                background: fixture.background
            )
            let expectedOutsidePixel = pixel(
                in: backgroundPixels,
                width: fixture.width,
                x: fixture.width / 2,
                y: edgeY - 8
            )
            XCTAssertEqual(outsidePixel.red, expectedOutsidePixel.red, fixture.name)
            XCTAssertEqual(outsidePixel.green, expectedOutsidePixel.green, fixture.name)
            XCTAssertEqual(outsidePixel.blue, expectedOutsidePixel.blue, fixture.name)
            XCTAssertEqual(outsidePixel.alpha, expectedOutsidePixel.alpha, fixture.name)
        }
    }

    func testOffscreenAnnotationPixelsDrawCommittedThenDraftThenVisibleHandles() throws {
        let width = 512
        let height = 512
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let committed = VisualFixtures.canonicalMark()
        let draft = Mark(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000204")!,
            geometry: committed.geometry,
            style: MarkStyle(
                color: RGBAColor(red: 0, green: 0, blue: 1),
                strokeWidth: 8,
                opacity: 0.5
            )
        )
        let plan = RenderPlan.make(
            canvas: VisualFixtures.canonicalCanvas(),
            mode: .annotation,
            selectedID: committed.id,
            activeDraft: draft,
            hover: HoverInventory(hoveredMarkID: committed.id, isVisible: true)
        )

        XCTAssertEqual(plan.activeDraft, draft)
        MarkRenderer.draw(plan: plan, in: bounds, context: context)

        let edge = pixel(in: pixels, width: width, x: 200, y: 128)
        XCTAssertGreaterThan(edge.alpha, 0)
        XCTAssertGreaterThan(edge.red, 40)
        XCTAssertLessThan(edge.red, 220)
        XCTAssertLessThan(edge.green, 80)
        XCTAssertGreaterThan(edge.blue, 40)
        XCTAssertLessThan(edge.blue, 220)

        let handleCenter = pixel(in: pixels, width: width, x: 128, y: 128)
        XCTAssertGreaterThanOrEqual(handleCenter.red, 250)
        XCTAssertGreaterThanOrEqual(handleCenter.green, 250)
        XCTAssertGreaterThanOrEqual(handleCenter.blue, 250)
        XCTAssertGreaterThanOrEqual(handleCenter.alpha, 250)
    }

    func testOffscreenStandbyPixelsContainMarkButNoHandleSentinel() throws {
        let width = 512
        let height = 512
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let mark = VisualFixtures.canonicalMark()
        let canvas = VisualFixtures.canonicalCanvas()
        let plan = RenderPlan.make(
            canvas: canvas,
            mode: .standby,
            selectedID: mark.id,
            activeDraft: mark,
            hover: HoverInventory(hoveredMarkID: mark.id, isVisible: true)
        )

        MarkRenderer.draw(plan: plan, in: bounds, context: context)

        XCTAssertGreaterThan(alpha(in: pixels, width: width, x: 256, y: 128), 0)
        XCTAssertGreaterThan(alpha(in: pixels, width: width, x: 128, y: 256), 0)
        XCTAssertEqual(alpha(in: pixels, width: width, x: 256, y: 120), 0)
        XCTAssertEqual(alpha(in: pixels, width: width, x: 120, y: 256), 0)

        for center in [(128, 128), (384, 128), (128, 384), (384, 384)] {
            XCTAssertFalse(
                containsOpaqueWhiteOrBlack(
                    pixels,
                    width: width,
                    height: height,
                    centerX: center.0,
                    centerY: center.1,
                    radius: 9,
                    tolerance: 1
                ),
                "unexpected handle sentinel near (\(center.0), \(center.1))"
            )
        }

        XCTAssertEqual(VisualFixtures.sha256(pixels), VisualFixtures.expectedStandbyDigest)
    }

    private func alpha(in pixels: [UInt8], width: Int, x: Int, y: Int) -> UInt8 {
        pixels[(y * width + x) * 4 + 3]
    }

    private func pixel(in pixels: [UInt8], width: Int, x: Int, y: Int) -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        let offset = (y * width + x) * 4
        return (pixels[offset], pixels[offset + 1], pixels[offset + 2], pixels[offset + 3])
    }

    private func render(
        plan: RenderPlan,
        width: Int,
        height: Int,
        background: (red: UInt8, green: UInt8, blue: UInt8)? = nil
    ) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { rawBuffer in
            let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
            let context = try XCTUnwrap(CGContext(
                data: rawBuffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            if let background {
                context.setFillColor(CGColor(
                    red: CGFloat(background.red) / 255,
                    green: CGFloat(background.green) / 255,
                    blue: CGFloat(background.blue) / 255,
                    alpha: 1
                ))
                context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            }
            MarkRenderer.draw(
                plan: plan,
                in: CGRect(x: 0, y: 0, width: width, height: height),
                context: context
            )
        }
        return pixels
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
}
