import ColorSync
import CoreFoundation
import CoreGraphics
import Foundation
import PointerCore

public enum DisplayUUIDProvider {
    public static func uuid(for displayID: CGDirectDisplayID) -> DisplayUUID? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID) else {
            return nil
        }
        let value = uuid.takeRetainedValue()
        guard let string = CFUUIDCreateString(nil, value) else {
            return nil
        }
        return DisplayUUID(rawValue: string as NSString as String)
    }
}
