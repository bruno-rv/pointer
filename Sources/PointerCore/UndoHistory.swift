public struct UndoHistory: Equatable, Sendable {
    public static let capacity = 100

    private var snapshots: [Canvas] = []

    public init() {}

    public var count: Int {
        snapshots.count
    }

    mutating func record(_ snapshot: Canvas) {
        snapshots.append(snapshot)
        if snapshots.count > Self.capacity {
            snapshots.removeFirst(snapshots.count - Self.capacity)
        }
    }

    mutating func popLatest() -> Canvas? {
        snapshots.popLast()
    }
}
