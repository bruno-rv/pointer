import AppKit
import XCTest

enum GUIHostTestSupport {
    static func skipReason(
        for activationPolicy: NSApplication.ActivationPolicy,
        isActive: Bool
    ) -> String? {
        guard activationPolicy != .prohibited else {
            let policyName: String
            switch activationPolicy {
            case .regular:
                policyName = "regular"
            case .accessory:
                policyName = "accessory"
            case .prohibited:
                policyName = "prohibited"
            @unknown default:
                policyName = "unknown"
            }
            return "Requires an AppKit application that can host windows for key-window and key-equivalent assertions (activation policy: \(policyName), application active: \(isActive)). SwiftPM headless hosts use activation policy prohibited."
        }
        return nil
    }

    @MainActor
    static func requireGUIHost(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let application = NSApplication.shared
        if let reason = skipReason(
            for: application.activationPolicy(),
            isActive: application.isActive
        ) {
            throw XCTSkip(reason, file: file, line: line)
        }
    }
}
