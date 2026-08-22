public enum PalettePlacement {
    public static func nearTopCenter(
        paletteSize: DenormalizedSize,
        in visibleFrame: DenormalizedRect,
        margin: Double = 16
    ) -> DenormalizedRect {
        let origin = DenormalizedRect(
            x: visibleFrame.x + (visibleFrame.width - paletteSize.width) / 2,
            y: visibleFrame.y + visibleFrame.height - paletteSize.height - margin,
            width: paletteSize.width,
            height: paletteSize.height
        )
        return clamped(origin, to: visibleFrame, margin: margin)
    }

    public static func clamped(
        _ palette: DenormalizedRect,
        to visibleFrame: DenormalizedRect,
        margin: Double = 16
    ) -> DenormalizedRect {
        let minX = visibleFrame.x + margin
        let minY = visibleFrame.y + margin
        let maxX = max(minX, visibleFrame.x + visibleFrame.width - palette.width - margin)
        let maxY = max(minY, visibleFrame.y + visibleFrame.height - palette.height - margin)

        return DenormalizedRect(
            x: min(max(palette.x, minX), maxX),
            y: min(max(palette.y, minY), maxY),
            width: palette.width,
            height: palette.height
        )
    }
}
