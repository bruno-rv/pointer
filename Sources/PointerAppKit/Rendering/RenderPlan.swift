import PointerCore

public struct RenderPlan: Equatable, Sendable {
    public let committedMarks: [Mark]
    public let activeDraft: Mark?
    public let handles: HandleInventory

    public init(committedMarks: [Mark], activeDraft: Mark?, handles: HandleInventory) {
        self.committedMarks = committedMarks
        self.activeDraft = activeDraft
        self.handles = handles
    }

    public static func make(
        canvas: Canvas,
        mode: PointerMode,
        selectedID: Mark.ID?,
        activeDraft: Mark?,
        hover: HoverInventory
    ) -> RenderPlan {
        guard mode == .annotation else {
            return RenderPlan(
                committedMarks: canvas.marks,
                activeDraft: nil,
                handles: HandleInventory(
                    selection: SelectionInventory(selectedMarkID: nil, isVisible: false),
                    hover: HoverInventory(hoveredMarkID: nil, isVisible: false),
                    resize: ResizeInventory(handles: [], isVisible: false),
                    contextualDeleteVisible: false
                )
            )
        }

        let resizeHandles = canvas.marks
            .first(where: { $0.id == selectedID })
            .map { ResizeGeometry.handles(for: $0.geometry) } ?? []
        return RenderPlan(
            committedMarks: canvas.marks,
            activeDraft: activeDraft,
            handles: HandleInventory(
                selection: SelectionInventory(
                    selectedMarkID: selectedID,
                    isVisible: selectedID != nil
                ),
                hover: hover,
                resize: ResizeInventory(
                    handles: resizeHandles,
                    isVisible: !resizeHandles.isEmpty
                ),
                contextualDeleteVisible: false
            )
        )
    }
}
