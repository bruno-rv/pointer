import AppKit

@MainActor
public protocol LocalKeyRouting: AnyObject {
    @discardableResult
    func routeLocalKeyEvent(_ event: NSEvent) -> Bool
}

@MainActor
public final class PointerApplication: NSApplication {
    public override init() {
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PointerApplication does not support storyboards.")
    }

    public weak var commandRouter: CommandRouter?
    public weak var localKeyRouter: (any LocalKeyRouting)?
    public weak var firstUseGuide: (any FirstUseGuidePresenting)?

    @discardableResult
    internal static func routeLocalEvent(
        _ event: NSEvent,
        guide: (any FirstUseGuidePresenting)?,
        localRouter: (any LocalKeyRouting)?,
        commandRouter: CommandRouter?
    ) -> Bool {
        if guide?.consumeEscape() == true {
            return true
        }
        if localRouter?.routeLocalKeyEvent(event) == true {
            return true
        }
        return localRouter == nil
            && commandRouter?.routeLocalKeyEvent(event) == true
    }

    public override func sendEvent(_ event: NSEvent) {
        if Self.routeLocalEvent(
            event,
            guide: firstUseGuide,
            localRouter: localKeyRouter,
            commandRouter: commandRouter
        ) {
            return
        }
        super.sendEvent(event)
    }
}

extension CommandRouter: LocalKeyRouting {}
