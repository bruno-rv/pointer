import Foundation

public struct RGBAColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red.clampedToUnitInterval
        self.green = green.clampedToUnitInterval
        self.blue = blue.clampedToUnitInterval
        self.alpha = alpha.clampedToUnitInterval
    }

    public static let red = RGBAColor(red: 1, green: 0, blue: 0)
}

public struct MarkStyle: Equatable, Sendable {
    public let color: RGBAColor
    public let strokeWidth: Double
    public let opacity: Double

    public init(color: RGBAColor, strokeWidth: Double, opacity: Double) {
        precondition(strokeWidth >= 0, "Stroke width must be nonnegative.")
        self.color = color
        self.strokeWidth = strokeWidth
        self.opacity = opacity.clampedToUnitInterval
    }

    public static let `default` = MarkStyle(color: .red, strokeWidth: 4, opacity: 1)
}

public enum MarkGeometry: Equatable, Sendable {
    case arrow(start: NormalizedPoint, end: NormalizedPoint)
    case rectangle(NormalizedRect)
    case ellipse(NormalizedRect)
    case freehand([NormalizedPoint])
    case emoji(text: String, rect: NormalizedRect)
    case spotlight(center: NormalizedPoint, radius: Double, dimness: Double)
}

public struct Mark: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let geometry: MarkGeometry
    public let style: MarkStyle

    public init(id: UUID = UUID(), geometry: MarkGeometry, style: MarkStyle) {
        self.id = id
        self.geometry = geometry.sanitized
        self.style = style
    }
}

extension MarkGeometry {
    var isSpotlight: Bool {
        if case .spotlight = self {
            return true
        }
        return false
    }

    var sanitized: MarkGeometry {
        switch self {
        case let .spotlight(center, radius, dimness):
            precondition(radius >= 0, "Spotlight radius must be nonnegative.")
            return .spotlight(
                center: center,
                radius: radius,
                dimness: dimness.clampedToUnitInterval
            )
        default:
            return self
        }
    }
}
