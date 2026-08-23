import PointerCore

@MainActor
public final class DisplayCoordinator {
    public typealias OverlayFactory = @MainActor (DisplayDescriptor) -> any OverlayPresenting

    private let screenProvider: any ScreenProviding
    private let overlayFactory: OverlayFactory
    public private(set) var session: PointerSession
    public private(set) var overlays: [DisplayUUID: any OverlayPresenting] = [:]
    private var connectedUUIDs: Set<DisplayUUID> = []
    private var retainedUUIDs: Set<DisplayUUID> = []
    private var hasSynchronized = false
    public var onBoundaryEvent: ((DisplayUUID, GestureBoundaryEvent) -> Void)?
    public var onSessionUpdate: ((PointerSession) -> Void)?
    public var onDisplaySync: ((DisplaySyncResult) -> Void)?

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

    @discardableResult
    public func synchronize() -> DisplaySyncResult {
        let previousConnectedUUIDs = connectedUUIDs
        let displays = screenProvider.currentDisplays()
        let connected = Set(
            displays
                .map(\.uuid)
                .filter { !$0.rawValue.isEmpty }
        )
        let enteredZeroDisplayState = !previousConnectedUUIDs.isEmpty && connected.isEmpty
        let reconnected = hasSynchronized
            && previousConnectedUUIDs.isEmpty
            && !connected.isEmpty
            && connected.contains { retainedUUIDs.contains($0) }

        if enteredZeroDisplayState {
            cancelActiveGestures()
            apply(.setMode(.standby), cancellingActiveGestures: false)
        }

        for descriptor in displays where !descriptor.uuid.rawValue.isEmpty {
            session.ensureCanvas(for: descriptor.uuid)
            retainedUUIDs.insert(descriptor.uuid)
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

        connectedUUIDs = connected
        hasSynchronized = true
        let result = DisplaySyncResult(
            connectedUUIDs: connected,
            addedUUIDs: connected.subtracting(previousConnectedUUIDs),
            removedUUIDs: previousConnectedUUIDs.subtracting(connected),
            pointerDisplay: screenProvider.pointerDisplay().flatMap { pointer in
                connected.contains(pointer) ? pointer : nil
            },
            hasConnectedDisplays: !connected.isEmpty,
            enteredZeroDisplayState: enteredZeroDisplayState,
            reconnected: reconnected
        )
        onDisplaySync?(result)
        return result
    }

    public func apply(_ command: SessionCommand) {
        apply(command, cancellingActiveGestures: true)
    }

    public func apply(_ command: SessionCommand, cancellingActiveGestures: Bool) {
        if cancellingActiveGestures {
            cancelActiveGestures()
        }
        session.apply(command)
        updateOverlays()
        onSessionUpdate?(session)
    }

    public func stop() -> DisplayStopResult {
        var closedOverlayCount = 0
        var activeGestureCount = 0
        var clearedHandlerCount = 0
        var boundHandlerCount = 0

        for (uuid, overlay) in Array(overlays) {
            let cleanup = overlay.stopAndClear()
            activeGestureCount += cleanup.cancelledActiveGesture ? 1 : 0
            clearedHandlerCount += cleanup.clearedHandlerCount
            boundHandlerCount += cleanup.remainingHandlerCount
            overlay.setMode(.standby)
            if !cleanup.didClose {
                overlay.close()
            }
            closedOverlayCount += 1
            overlays.removeValue(forKey: uuid)
        }

        return DisplayStopResult(
            closedOverlayCount: closedOverlayCount,
            remainingOverlayCount: overlays.count,
            activeGestureCount: activeGestureCount,
            clearedHandlerCount: clearedHandlerCount,
            boundHandlerCount: boundHandlerCount
        )
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
