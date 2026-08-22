import AppKit
import PointerCore

@MainActor
public final class NSScreenProvider: ScreenProviding {
    public init() {}

    public func currentDisplays() -> [DisplayDescriptor] {
        NSScreen.screens.compactMap { screen in
            guard let displayID = Self.displayID(for: screen) else {
                NSLog("PointerAppKit: skipping screen without a CoreGraphics display identifier")
                return nil
            }
            guard let uuid = DisplayUUIDProvider.uuid(for: displayID) else {
                NSLog("PointerAppKit: skipping display without a stable UUID")
                return nil
            }

            return DisplayDescriptor(
                uuid: uuid,
                frame: DisplayFrame(screen.frame),
                visibleFrame: DisplayFrame(screen.visibleFrame),
                scaleFactor: Double(screen.backingScaleFactor)
            )
        }
    }

    public func pointerDisplay() -> DisplayUUID? {
        let location = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(location) } ?? NSScreen.main
        guard let screen,
              let displayID = Self.displayID(for: screen)
        else {
            return nil
        }
        return DisplayUUIDProvider.uuid(for: displayID)
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }
}
