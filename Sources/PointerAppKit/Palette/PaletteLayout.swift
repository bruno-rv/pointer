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
        let fullWidth = horizontalPadding
            + modeWidth
            + toolWidth * Double(allTools.count)
            + spacing * Double(allTools.count)
        guard availableWidth >= fullWidth else {
            let availableToolsWidth = max(
                toolWidth,
                availableWidth - horizontalPadding - modeWidth - spacing
            )
            let visibleCount = min(
                allTools.count - 1,
                max(1, Int((availableToolsWidth + spacing) / (toolWidth + spacing)))
            )
            let visibleTools = Array(allTools.prefix(visibleCount))
            let overflowTools = Array(allTools.dropFirst(visibleCount))
            return PaletteLayoutPlan(
                rows: [[
                    .tool(visibleTools[0]),
                    .overflow,
                ]],
                overflowTools: overflowTools
            )
        }

        let midpoint = (allTools.count + 1) / 2
        return PaletteLayoutPlan(
            rows: [
                allTools.prefix(midpoint).map(PaletteLayoutItem.tool),
                allTools.dropFirst(midpoint).map(PaletteLayoutItem.tool),
            ],
            overflowTools: []
        )
    }
}
