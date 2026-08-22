@MainActor
public protocol ShortcutStoring: AnyObject {
    func load() -> ShortcutPreset?
    func save(_ preset: ShortcutPreset)
}
