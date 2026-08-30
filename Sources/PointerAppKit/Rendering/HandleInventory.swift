import PointerCore

public struct SelectionInventory: Equatable, Sendable {
    public let selectedMarkID: Mark.ID?
    public let isVisible: Bool

    public init(selectedMarkID: Mark.ID?, isVisible: Bool) {
        self.selectedMarkID = selectedMarkID
        self.isVisible = isVisible
    }
}

public struct HoverInventory: Equatable, Sendable {
    public let hoveredMarkID: Mark.ID?
    public let isVisible: Bool

    public init(hoveredMarkID: Mark.ID?, isVisible: Bool) {
        self.hoveredMarkID = hoveredMarkID
        self.isVisible = isVisible
    }
}

public struct ResizeInventory: Equatable, Sendable {
    public let handles: [ResizeHandle]
    public let isVisible: Bool

    public init(handles: [ResizeHandle], isVisible: Bool) {
        self.handles = handles
        self.isVisible = isVisible
    }
}

public struct HandleInventory: Equatable, Sendable {
    public let selection: SelectionInventory
    public let hover: HoverInventory
    public let resize: ResizeInventory
    public let contextualDeleteVisible: Bool

    public init(
        selection: SelectionInventory,
        hover: HoverInventory,
        resize: ResizeInventory,
        contextualDeleteVisible: Bool
    ) {
        self.selection = selection
        self.hover = hover
        self.resize = resize
        self.contextualDeleteVisible = contextualDeleteVisible
    }
}
