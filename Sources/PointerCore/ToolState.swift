public enum PointerTool: CaseIterable, Equatable, Sendable {
    case select
    case arrow
    case rectangle
    case ellipse
    case pen
    case eraser
    case emoji
    case spotlight
}

public enum PointerMode: Equatable, Sendable {
    case standby
    case annotation
}

public struct ToolState: Equatable, Sendable {
    public private(set) var tool: PointerTool
    public private(set) var style: MarkStyle
    public private(set) var emoji: String
    public private(set) var spotlightRadius: Double
    public private(set) var spotlightDimness: Double

    public init(
        tool: PointerTool = .arrow,
        style: MarkStyle = .default,
        emoji: String = "👉",
        spotlightRadius: Double = 0.15,
        spotlightDimness: Double = 0.5
    ) {
        precondition(spotlightRadius >= 0, "Spotlight radius must be nonnegative.")
        self.tool = tool
        self.style = style
        self.emoji = emoji
        self.spotlightRadius = spotlightRadius
        self.spotlightDimness = spotlightDimness.clampedToUnitInterval
    }

    mutating func setTool(_ tool: PointerTool) {
        self.tool = tool
    }

    mutating func setStyle(_ style: MarkStyle) {
        self.style = style
    }

    mutating func setEmoji(_ emoji: String) {
        self.emoji = emoji
    }

    mutating func setSpotlight(radius: Double, dimness: Double) {
        precondition(radius >= 0, "Spotlight radius must be nonnegative.")
        spotlightRadius = radius
        spotlightDimness = dimness.clampedToUnitInterval
    }
}
