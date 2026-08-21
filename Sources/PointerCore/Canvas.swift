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

    mutating func replace(_ mark: Mark) {
        guard let index = marks.firstIndex(where: { $0.id == mark.id }) else {
            return
        }
        if mark.geometry.isSpotlight {
            marks.removeAll { $0.geometry.isSpotlight && $0.id != mark.id }
        }
        marks[index] = mark
    }

    mutating func setMarks(_ newMarks: [Mark]) {
        marks = newMarks
    }
}
