// From Pullo (MIT, (c) 2026 Gabriel Jordan)
import Carbon.HIToolbox
import Observation

final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let id: UInt32
    private let action: () -> Void

    /// `id` tells hot keys apart: every handler sees every press and passes on the ones that aren't its own.
    init?(_ shortcut: Shortcut, id: UInt32, action: @escaping () -> Void) {
        self.id = id
        self.action = action
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData, let event else { return OSStatus(eventNotHandledErr) }
                var pressed = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed
                )
                let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
                guard status == noErr, pressed.id == hotKey.id else { return OSStatus(eventNotHandledErr) }
                hotKey.action()
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        let hotKeyID = EventHotKeyID(signature: OSType(0x4E4F_4F4B), id: id)
        let registered = RegisterEventHotKey(
            UInt32(shortcut.keyCode), UInt32(shortcut.modifiers), hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef
        )
        guard installed == noErr, registered == noErr else {
            if let handlerRef { RemoveEventHandler(handlerRef) }
            handlerRef = nil
            return nil
        }
    }

    isolated deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}

/// Registers the global shortcuts from the settings and runs their actions.
@Observable
final class HotKeyCenter {
    /// Actions whose shortcut could not be registered (taken by the system or another app).
    private(set) var unavailable: Set<GlobalAction> = []
    @ObservationIgnored var handlers: [GlobalAction: () -> Void] = [:]
    @ObservationIgnored private var hotKeys: [GlobalAction: HotKey] = [:]
    @ObservationIgnored private var suspended = false

    func apply(_ settings: AppSettings) {
        hotKeys.removeAll()
        guard !suspended else { return }
        var failed: Set<GlobalAction> = []
        for (index, action) in GlobalAction.allCases.enumerated() {
            let shortcut = settings.shortcut(for: action)
            let hotKey = HotKey(shortcut, id: UInt32(index + 1)) { [weak self] in
                MainActor.assumeIsolated { self?.handlers[action]?() }
            }
            if let hotKey { hotKeys[action] = hotKey } else { failed.insert(action) }
        }
        if unavailable != failed { unavailable = failed }
    }

    /// While a shortcut is being recorded, the current ones must not fire (or swallow the keys).
    func suspend() {
        suspended = true
        hotKeys.removeAll()
    }

    func resume(_ settings: AppSettings) {
        suspended = false
        apply(settings)
    }
}
