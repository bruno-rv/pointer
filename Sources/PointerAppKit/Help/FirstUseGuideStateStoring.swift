@MainActor
public protocol FirstUseGuideStateStoring: AnyObject {
    var hasDismissedFirstUseGuide: Bool { get }
    func markFirstUseGuideDismissed()
}
