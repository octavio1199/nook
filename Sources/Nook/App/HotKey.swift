// From Pullo (MIT, (c) 2026 Gabriel Jordan)
import Carbon.HIToolbox

struct Shortcut {
    let keyCode: Int
    let modifiers: Int
    let symbols: String

    static let togglePanel = Shortcut(keyCode: kVK_ANSI_N, modifiers: cmdKey | optionKey, symbols: "⌥⌘N")
}

final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    init?(_ shortcut: Shortcut, action: @escaping () -> Void) {
        self.action = action
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue().action()
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        let id = EventHotKeyID(signature: OSType(0x4E4F_4F4B), id: 1)
        let registered = RegisterEventHotKey(
            UInt32(shortcut.keyCode), UInt32(shortcut.modifiers), id, GetApplicationEventTarget(), 0, &hotKeyRef
        )
        guard installed == noErr, registered == noErr else { return nil }
    }

    isolated deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
