public struct NormalizedPoint: Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x.clampedToUnitInterval
        self.y = y.clampedToUnitInterval
    }

    public func denormalized(width: Double, height: Double) -> DenormalizedPoint {
        DenormalizedPoint(x: x * width, y: y * height)
    }
}

public struct NormalizedSize: Equatable, Sendable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = width.clampedToUnitInterval
        self.height = height.clampedToUnitInterval
    }

    public func denormalized(width: Double, height: Double) -> DenormalizedSize {
        DenormalizedSize(width: self.width * width, height: self.height * height)
    }
}

public struct NormalizedRect: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x.clampedToUnitInterval
        self.y = y.clampedToUnitInterval
        self.width = min(width.clampedToUnitInterval, 1 - self.x)
        self.height = min(height.clampedToUnitInterval, 1 - self.y)
    }

    public func denormalized(width: Double, height: Double) -> DenormalizedRect {
        DenormalizedRect(
            x: x * width,
            y: y * height,
            width: self.width * width,
            height: self.height * height
        )
    }
}

public struct DenormalizedPoint: Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct DenormalizedSize: Equatable, Sendable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct DenormalizedRect: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

extension Double {
    var clampedToUnitInterval: Double {
        guard !isNaN else {
            return 0
        }
        return min(max(self, 0), 1)
    }
}
