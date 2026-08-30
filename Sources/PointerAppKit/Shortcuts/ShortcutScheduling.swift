import Foundation

public struct ShortcutScheduleToken: Hashable, Sendable {
    let rawValue: UInt64

    init(rawValue: UInt64) {
        self.rawValue = rawValue
    }
}

@MainActor
public protocol ShortcutScheduling: AnyObject {
    /// Number of scheduled actions that can still execute or be cancelled.
    var activeTimerCount: Int { get }

    @discardableResult
    func schedule(after interval: TimeInterval, _ action: @escaping () -> Void) -> ShortcutScheduleToken
    func cancel(_ token: ShortcutScheduleToken)
}

@MainActor
public final class DispatchShortcutScheduler: ShortcutScheduling {
    private var nextToken: UInt64 = 1
    private var workItems: [ShortcutScheduleToken: DispatchWorkItem] = [:]

    public init() {}

    public var activeTimerCount: Int {
        workItems.count
    }

    @discardableResult
    public func schedule(
        after interval: TimeInterval,
        _ action: @escaping () -> Void
    ) -> ShortcutScheduleToken {
        let token = ShortcutScheduleToken(rawValue: nextToken)
        nextToken += 1
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.workItems.removeValue(forKey: token) != nil else {
                    return
                }
                action()
            }
        }
        workItems[token] = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + interval,
            execute: workItem
        )
        return token
    }

    public func cancel(_ token: ShortcutScheduleToken) {
        workItems.removeValue(forKey: token)?.cancel()
    }
}
