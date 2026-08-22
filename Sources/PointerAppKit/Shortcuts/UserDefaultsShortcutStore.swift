import Foundation

@MainActor
public final class UserDefaultsShortcutStore: ShortcutStoring {
    private let defaults: UserDefaults
    private let key: String

    public init(
        userDefaults: UserDefaults = .standard,
        key: String = "pointer.shortcut-preset"
    ) {
        self.defaults = userDefaults
        self.key = key
    }

    public func load() -> ShortcutPreset? {
        guard let rawValue = defaults.string(forKey: key) else {
            return nil
        }
        return ShortcutPreset(rawValue: rawValue)
    }

    public func save(_ preset: ShortcutPreset) {
        defaults.set(preset.rawValue, forKey: key)
    }
}
