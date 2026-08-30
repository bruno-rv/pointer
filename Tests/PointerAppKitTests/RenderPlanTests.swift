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
        XCTAssertFalse(annotation.handles.contextualDeleteVisible)
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
