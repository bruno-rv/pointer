@MainActor
public protocol HotKeyRegistering: AnyObject {
    var onEvent: ((HotKeyToken) -> Void)? { get set }
    func register(_ preset: ShortcutPreset) throws -> HotKeyToken
    func unregister(_ token: HotKeyToken)
}
