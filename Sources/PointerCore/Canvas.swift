public struct Canvas: Equatable, Sendable {
    public private(set) var marks: [Mark]

    public init() {
        marks = []
    }

    mutating func append(_ mark: Mark) {
        if mark.geometry.isSpotlight {
            marks.removeAll { $0.geometry.isSpotlight }
        }
        marks.append(mark)
    }

    mutating func remove(id: Mark.ID) -> Bool {
        guard let index = marks.firstIndex(where: { $0.id == id }) else {
            return false
        }
        marks.remove(at: index)
        return true
    }

    mutating func clear() {
        marks.removeAll()
    }
}
