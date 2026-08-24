import PointerCore

public enum PaletteLayoutItem: Equatable, Sendable {
    case tool(PointerTool)
    case overflow
}

public struct PaletteLayoutPlan: Equatable, Sendable {
    public let rows: [[PaletteLayoutItem]]
    public let overflowTools: [PointerTool]

    public init(rows: [[PaletteLayoutItem]], overflowTools: [PointerTool]) {
        self.rows = rows
        self.overflowTools = overflowTools
    }

    public var usesOverflow: Bool {
        !overflowTools.isEmpty
    }
}

public enum PaletteLayout {
    public static let allTools = PointerTool.allCases
    public static let minimumToolWidth = 44.0
    public static let toolSpacing = 8.0
    public static let horizontalPadding = 32.0
    public static let modeWidth = 92.0

    public static func plan(
        availableWidth: Double,
        toolWidth: Double = minimumToolWidth,
        spacing: Double = toolSpacing
    ) -> PaletteLayoutPlan {
        let safeWidth = availableWidth.isFinite ? max(0, availableWidth) : 0
        let safeToolWidth = toolWidth.isFinite && toolWidth > 0
            ? toolWidth
            : minimumToolWidth
        let safeSpacing = spacing.isFinite && spacing >= 0 ? spacing : toolSpacing
        let fullWidth = horizontalPadding
            + modeWidth
            + safeToolWidth * Double(allTools.count)
            + safeSpacing * Double(allTools.count)
        guard safeWidth >= fullWidth else {
            let availableToolsWidth = max(
                safeToolWidth,
                safeWidth - horizontalPadding - modeWidth - safeSpacing
            )
            let visibleCount = min(
                allTools.count - 1,
                max(1, Int((availableToolsWidth + safeSpacing) / (safeToolWidth + safeSpacing)))
            )
            let visibleTools = Array(allTools.prefix(visibleCount))
            let overflowTools = Array(allTools.dropFirst(visibleCount))
            return PaletteLayoutPlan(
                rows: [visibleTools.map(PaletteLayoutItem.tool) + [.overflow]],
                overflowTools: overflowTools
            )
        }

        return PaletteLayoutPlan(
            rows: [allTools.map(PaletteLayoutItem.tool)],
            overflowTools: []
        )
    }
}
