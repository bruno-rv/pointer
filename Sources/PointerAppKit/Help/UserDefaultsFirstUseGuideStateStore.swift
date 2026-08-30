import Foundation

@MainActor
public final class UserDefaultsFirstUseGuideStateStore: FirstUseGuideStateStoring {
    private let userDefaults: UserDefaults
    private let key: String

    public init(userDefaults: UserDefaults, key: String) {
        self.userDefaults = userDefaults
        self.key = key
    }

    public var hasDismissedFirstUseGuide: Bool {
        userDefaults.bool(forKey: key)
    }

    public func markFirstUseGuideDismissed() {
        userDefaults.set(true, forKey: key)
    }
}
