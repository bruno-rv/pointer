import PointerCore
@testable import PointerAppKit

@MainActor
final class DeterministicScreenProvider: ScreenProviding {
    var displays: [DisplayDescriptor]
    var pointerUUID: DisplayUUID?

    init(displays: [DisplayDescriptor] = [], pointerUUID: DisplayUUID? = nil) {
        self.displays = displays
        self.pointerUUID = pointerUUID
    }

    func currentDisplays() -> [DisplayDescriptor] {
        displays
    }

    func pointerDisplay() -> DisplayUUID? {
        pointerUUID
    }
}
