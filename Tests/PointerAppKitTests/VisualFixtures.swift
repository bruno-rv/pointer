import CryptoKit
import Foundation
import PointerCore

enum VisualFixtures {
    static let canonicalMarkID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!

    static let expectedStandbyDigest = "049d2e0cfbdd8f6c02f4db31955dc408f6eda47ad93f2e4bf50516acfd4d5771"

    static func canonicalMark() -> Mark {
        Mark(
            id: canonicalMarkID,
            geometry: .rectangle(NormalizedRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)),
            style: .default
        )
    }

    static func canonicalCanvas() -> Canvas {
        let display = DisplayUUID(rawValue: "visual-fixture-display")
        var session = PointerSession()
        session.apply(.append(canonicalMark(), to: display))
        return session.canvas(for: display)
    }

    static func sha256(_ bytes: [UInt8]) -> String {
        SHA256.hash(data: Data(bytes)).map { String(format: "%02x", $0) }.joined()
    }
}
