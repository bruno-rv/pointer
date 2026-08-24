import AppKit

@MainActor
public protocol FirstUseGuideStateStoring: AnyObject {
    var hasDismissedFirstUseGuide: Bool { get }
    func markFirstUseGuideDismissed()
}

@MainActor
public protocol FirstUseGuidePresenting: AnyObject {
    var isVisible: Bool { get }
    var placementProvider: any GuidePlacementProviding { get }
    func showIfNeeded(in context: GuidePlacementContext)
    func show(in context: GuidePlacementContext)
    func dismiss()
    func hideForDisplayLoss()
    func restoreAfterDisplayLoss(in context: GuidePlacementContext)
    func hideForApplicationStop()
    func consumeEscape() -> Bool
}
