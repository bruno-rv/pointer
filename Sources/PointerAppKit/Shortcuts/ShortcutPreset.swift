import Carbon

public enum ShortcutPreset: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case controlOptionCommandP = "control-option-command-p"
    case controlOptionCommandO = "control-option-command-o"

    public static let defaultPreset: ShortcutPreset = .controlOptionCommandP

    public var keyCode: UInt32 {
        switch self {
        case .controlOptionCommandP:
            return UInt32(kVK_ANSI_P)
        case .controlOptionCommandO:
            return UInt32(kVK_ANSI_O)
        }
    }

    public var modifiers: UInt32 {
        UInt32(controlKey | optionKey | cmdKey)
    }

    public var displayName: String {
        switch self {
        case .controlOptionCommandP:
            return "Control-Option-Command-P"
        case .controlOptionCommandO:
            return "Control-Option-Command-O"
        }
    }
}

public struct HotKeyToken: Hashable, Sendable {
    let rawValue: UInt64

    init(rawValue: UInt64) {
        self.rawValue = rawValue
    }
}
