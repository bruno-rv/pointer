import PointerCore

public struct GuidePlacementContext: Equatable, Sendable {
    public let display: DisplayDescriptor
    public let visibleFrame: DisplayFrame
    public let paletteFrame: DisplayFrame
    public let avoidanceFrames: [DisplayFrame]

    public init(
        display: DisplayDescriptor,
        visibleFrame: DisplayFrame,
        paletteFrame: DisplayFrame,
        avoidanceFrames: [DisplayFrame]
    ) {
        self.display = display
        self.visibleFrame = visibleFrame
        self.paletteFrame = paletteFrame
        self.avoidanceFrames = avoidanceFrames
    }
}

@MainActor
public protocol GuidePlacementProviding: AnyObject {
    func context(
        for display: DisplayDescriptor,
        paletteFrame: DisplayFrame
    ) -> GuidePlacementContext?
}
