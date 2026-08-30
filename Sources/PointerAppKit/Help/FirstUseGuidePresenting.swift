import AppKit

@MainActor
public protocol FirstUseGuideStateStoring: AnyObject {
    var hasDismissedFirstUseGuide: Bool { get }
    func markFirstUseGuideDismissed()
}

public enum GuidePresentationResult: Equatable, Sendable {
    case shown
    case notNeeded
    case failed(String)
}

@MainActor
public protocol FirstUseGuidePresenting: AnyObject {
    var isVisible: Bool { get }
    var placementProvider: any GuidePlacementProviding { get }
    @discardableResult
    func showIfNeeded(in context: GuidePlacementContext) -> GuidePresentationResult
    @discardableResult
    func show(in context: GuidePlacementContext) -> GuidePresentationResult
    func dismiss()
    func hideForDisplayLoss()
    @discardableResult
    func restoreAfterDisplayLoss(in context: GuidePlacementContext) -> GuidePresentationResult
    func hideForApplicationStop()
    func consumeEscape() -> Bool
}
