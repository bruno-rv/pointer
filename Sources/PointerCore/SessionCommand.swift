public enum SessionCommand: Equatable, Sendable {
    case append(Mark, to: DisplayUUID)
    case remove(Mark.ID, from: DisplayUUID)
    case clear(DisplayUUID)
    case undo(on: DisplayUUID)
    case clearAll
    case undoClearAll
    case setMode(PointerMode)
    case setTool(PointerTool)
    case setStyle(MarkStyle)
    case setEmoji(String)
    case setSpotlight(radius: Double, dimness: Double)
}
