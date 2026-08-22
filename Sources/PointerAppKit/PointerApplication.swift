import AppKit

@MainActor
public final class PointerApplication: NSApplication {
    public weak var commandRouter: CommandRouter?

    public override func sendEvent(_ event: NSEvent) {
        if commandRouter?.routeLocalKeyEvent(event) == true {
            return
        }
        super.sendEvent(event)
    }
}
