import Carbon

public enum CarbonHotKeyRegistrationError: Error, Equatable {
    case eventHandlerUnavailable(OSStatus)
    case registrationFailed(OSStatus)
    case missingRegistrationReference
}

@MainActor
public final class CarbonHotKeyRegistrar: HotKeyRegistering {
    public var onEvent: ((HotKeyToken) -> Void)?

    private static let signature: OSType = 0x5054_5253

    private struct Registration {
        let reference: EventHotKeyRef
        let eventID: EventHotKeyID
    }

    private var eventHandler: EventHandlerRef?
    private var eventHandlerStatus: OSStatus = noErr
    private var nextToken: UInt64 = 1
    private var nextEventID: UInt32 = 1
    private var registrations: [HotKeyToken: Registration] = [:]
    private var tokensByEventID: [UInt32: HotKeyToken] = [:]

    public init() {
        installEventHandler()
    }

    public func register(_ preset: ShortcutPreset) throws -> HotKeyToken {
        guard eventHandlerStatus == noErr else {
            throw CarbonHotKeyRegistrationError.eventHandlerUnavailable(eventHandlerStatus)
        }

        let token = HotKeyToken(rawValue: nextToken)
        nextToken += 1
        let eventID = EventHotKeyID(
            signature: Self.signature,
            id: nextEventID
        )
        nextEventID += 1

        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            preset.keyCode,
            preset.modifiers,
            eventID,
            GetApplicationEventTarget(),
            OptionBits(kEventHotKeyNoOptions),
            &reference
        )
        guard status == noErr else {
            throw CarbonHotKeyRegistrationError.registrationFailed(status)
        }
        guard let reference else {
            throw CarbonHotKeyRegistrationError.missingRegistrationReference
        }

        registrations[token] = Registration(reference: reference, eventID: eventID)
        tokensByEventID[eventID.id] = token
        return token
    }

    public func unregister(_ token: HotKeyToken) {
        guard let registration = registrations.removeValue(forKey: token) else {
            return
        }
        UnregisterEventHotKey(registration.reference)
        tokensByEventID.removeValue(forKey: registration.eventID.id)
    }

    public func terminate() {
        for registration in registrations.values {
            UnregisterEventHotKey(registration.reference)
        }
        registrations.removeAll()
        tokensByEventID.removeAll()

        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        onEvent = nil
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let context = Unmanaged.passUnretained(self).toOpaque()
        eventHandlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHotKeyEventHandler,
            1,
            &eventType,
            context,
            &eventHandler
        )
    }

    fileprivate func receive(_ event: EventRef) -> OSStatus {
        var eventID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &eventID
        )
        guard status == noErr,
              eventID.signature == Self.signature,
              let token = tokensByEventID[eventID.id] else {
            return OSStatus(eventNotHandledErr)
        }

        onEvent?(token)
        return noErr
    }

    deinit {
        for registration in registrations.values {
            UnregisterEventHotKey(registration.reference)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }
}

private let carbonHotKeyEventHandler: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else {
        return OSStatus(eventNotHandledErr)
    }
    let registrar = Unmanaged<CarbonHotKeyRegistrar>
        .fromOpaque(userData)
        .takeUnretainedValue()
    return MainActor.assumeIsolated {
        registrar.receive(event)
    }
}
