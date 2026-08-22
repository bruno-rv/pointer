import PointerCore

@MainActor
public final class DisplayCoordinator {
    public typealias OverlayFactory = @MainActor (DisplayDescriptor) -> any OverlayPresenting

    private let screenProvider: any ScreenProviding
    private let overlayFactory: OverlayFactory
    public private(set) var session: PointerSession
    public private(set) var overlays: [DisplayUUID: any OverlayPresenting] = [:]
    public var onBoundaryEvent: ((DisplayUUID, GestureBoundaryEvent) -> Void)?
    public var onSessionUpdate: ((PointerSession) -> Void)?

    public init(
        screenProvider: any ScreenProviding,
        session: PointerSession = PointerSession(),
        overlayFactory: @escaping OverlayFactory
    ) {
        self.screenProvider = screenProvider
        self.session = session
        self.overlayFactory = overlayFactory
    }

    public convenience init(screenProvider: any ScreenProviding) {
        self.init(screenProvider: screenProvider, overlayFactory: { descriptor in
            OverlayPanel(descriptor: descriptor)
        })
    }

    public func synchronize() {
        let displays = screenProvider.currentDisplays()
        let connected = Set(displays.map(\.uuid))

        for descriptor in displays where !descriptor.uuid.rawValue.isEmpty {
            session.ensureCanvas(for: descriptor.uuid)
            if let overlay = overlays[descriptor.uuid] {
                configure(overlay, for: descriptor.uuid)
                overlay.update(display: descriptor)
                overlay.update(session: session)
                overlay.setMode(session.mode)
            } else {
                let overlay = overlayFactory(descriptor)
                configure(overlay, for: descriptor.uuid)
                overlay.update(session: session)
                overlay.setMode(session.mode)
                overlay.show()
                overlays[descriptor.uuid] = overlay
            }
        }

        let disconnected = overlays.filter { !connected.contains($0.key) }
        for (uuid, overlay) in disconnected {
            overlay.close()
            overlays.removeValue(forKey: uuid)
            session.disconnect(uuid)
        }
    }

    public func apply(_ command: SessionCommand) {
        session.apply(command)
        updateOverlays()
        onSessionUpdate?(session)
    }

    public func cancelActiveGestures() {
        for overlay in overlays.values {
            overlay.cancelActiveGesture()
        }
    }

    public func descriptor(for uuid: DisplayUUID) -> DisplayDescriptor? {
        screenProvider.currentDisplays().first { $0.uuid == uuid }
    }

    private func updateOverlays() {
        for overlay in overlays.values {
            overlay.update(session: session)
            overlay.setMode(session.mode)
        }
    }

    private func configure(_ overlay: any OverlayPresenting, for display: DisplayUUID) {
        overlay.setEventHandlers(
            onSessionUpdate: { [weak self] updatedSession in
                self?.sessionChanged(to: updatedSession)
            },
            onBoundaryEvent: { [weak self] event in
                self?.onBoundaryEvent?(display, event)
            }
        )
    }

    private func sessionChanged(to updatedSession: PointerSession) {
        session = updatedSession
        updateOverlays()
        onSessionUpdate?(session)
    }
}
