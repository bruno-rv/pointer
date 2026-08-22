import CoreGraphics
import PointerCore
import XCTest
@testable import PointerAppKit

final class MarkRendererTests: XCTestCase {
    func testSpotlightDimsOutsideFocusCircle() throws {
        let width = 100
        let height = 100
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let mark = Mark(
            geometry: .spotlight(
                center: NormalizedPoint(x: 0.5, y: 0.5),
                radius: 0.2,
                dimness: 0.75
            ),
            style: .default
        )

        MarkRenderer.draw(marks: [mark], in: CGRect(x: 0, y: 0, width: width, height: height), context: context)

        let outside = pixels[(25 * width + 25) * 4]
        let inside = pixels[(50 * width + 50) * 4]
        XCTAssertLessThan(outside, inside)
    }
}
