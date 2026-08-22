import Foundation
import PointerCore

public enum SmokeRunner {
    public enum Display: String, Equatable, Sendable {
        case builtIn = "built-in"
        case external
    }

    public struct Report: Equatable, Encodable, Sendable {
        public let paletteCount: Int
        public let overlayCount: Int
        public let mode: PointerMode
        public let shortcutID: String

        fileprivate init(overlayCount: Int) {
            paletteCount = 1
            self.overlayCount = overlayCount
            mode = .standby
            shortcutID = ShortcutPreset.defaultPreset.rawValue
        }

        private enum CodingKeys: String, CodingKey {
            case mode
            case overlayCount
            case paletteCount
            case shortcutID
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("standby", forKey: .mode)
            try container.encode(overlayCount, forKey: .overlayCount)
            try container.encode(paletteCount, forKey: .paletteCount)
            try container.encode(shortcutID, forKey: .shortcutID)
        }
    }

    public static let defaultDisplays: [Display] = [.builtIn]

    public static func report(displays: [Display]) -> Report {
        Report(overlayCount: displays.count)
    }

    public static func json(displays: [Display]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(report(displays: displays))
    }
}
