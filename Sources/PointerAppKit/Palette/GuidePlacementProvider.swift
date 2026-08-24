import PointerCore

@MainActor
public final class GuidePlacementProvider: GuidePlacementProviding {
    public init() {}

    public func context(
        for display: DisplayDescriptor,
        paletteFrame: DisplayFrame
    ) -> GuidePlacementContext? {
        guard isValid(display.visibleFrame),
              !display.uuid.rawValue.isEmpty,
              isValid(paletteFrame)
        else {
            return nil
        }

        return GuidePlacementContext(
            display: display,
            visibleFrame: display.visibleFrame,
            paletteFrame: paletteFrame,
            avoidanceFrames: [paletteFrame]
        )
    }

    private func isValid(_ frame: DisplayFrame) -> Bool {
        frame.x.isFinite && frame.y.isFinite
            && frame.width.isFinite && frame.width > 0
            && frame.height.isFinite && frame.height > 0
    }
}
