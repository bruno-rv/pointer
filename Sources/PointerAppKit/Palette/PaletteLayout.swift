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
    public static let minimumToolWidth = 76.0
    public static let overflowWidth = 120.0
    public static let toolSpacing = 6.0
    public static let horizontalPadding = 24.0
    public static let modeWidth = 92.0
    public static let minimumSupportedWidth = horizontalPadding
        + modeWidth
        + overflowWidth
        + toolSpacing * 2
        + width(for: .select)
    public static let minimumAllToolsWidth = horizontalPadding
        + modeWidth
        + allTools.reduce(0) { $0 + width(for: $1) }
        + toolSpacing * Double(allTools.count)

    public static func plan(
        availableWidth: Double,
        toolWidth: Double = minimumToolWidth,
        spacing: Double = toolSpacing
    ) -> PaletteLayoutPlan {
        let safeWidth = availableWidth.isFinite ? max(0, availableWidth) : 0
        let safeToolWidth = toolWidth.isFinite && toolWidth > 0 ? toolWidth : minimumToolWidth
        let safeSpacing = spacing.isFinite && spacing >= 0 ? spacing : toolSpacing
        let toolWidths = allTools.map { tool in
            toolWidth == minimumToolWidth ? width(for: tool) : safeToolWidth
        }
        let fullWidth = horizontalPadding + modeWidth
            + toolWidths.reduce(0, +)
            + safeSpacing * Double(allTools.count)
        guard safeWidth >= fullWidth else {
            var visibleCount = 0
            var visibleWidth = horizontalPadding + modeWidth + overflowWidth
                + (safeSpacing * 2)
            for toolWidth in toolWidths where visibleCount < allTools.count - 1 {
                let candidate = visibleWidth + toolWidth
                    + (visibleCount == 0 ? 0 : safeSpacing)
                guard candidate <= safeWidth else { break }
                visibleWidth = candidate
                visibleCount += 1
            }
            visibleCount = max(1, visibleCount)
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

    public static func width(for tool: PointerTool) -> Double {
        switch tool {
        case .select, .arrow: return 77
        case .rectangle: return 107
        case .ellipse: return 86
        case .pen: return 61
        case .eraser: return 82
        case .emoji: return 75
        case .spotlight: return 93
        }
    }
}
