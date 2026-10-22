import AppKit
import Carbon.HIToolbox

/// A key combination: Carbon key code and modifier mask, plus the key's label for display.
nonisolated struct Shortcut: Codable, Equatable, Hashable {
    var keyCode: Int
    var modifiers: Int
    var key: String

    /// "⌃⌥N", in the order macOS menus use.
    var symbols: String {
        var text = ""
        if modifiers & controlKey != 0 { text += "⌃" }
        if modifiers & optionKey != 0 { text += "⌥" }
        if modifiers & shiftKey != 0 { text += "⇧" }
        if modifiers & cmdKey != 0 { text += "⌘" }
        return text + key
    }

    init(keyCode: Int, modifiers: Int, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    /// A recorded key press. Nil unless it has ⌘, ⌃ or ⌥ (Shift alone would steal plain typing)
    /// and the key has a label.
    init?(keyCode: Int, flags: NSEvent.ModifierFlags, characters: String?) {
        let modifiers = Self.carbonModifiers(flags)
        guard modifiers & (cmdKey | controlKey | optionKey) != 0,
              let key = Self.label(keyCode: keyCode, characters: characters) else { return nil }
        self.init(keyCode: keyCode, modifiers: modifiers, key: key)
    }

    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> Int {
        var mask = 0
        if flags.contains(.command) { mask |= cmdKey }
        if flags.contains(.option) { mask |= optionKey }
        if flags.contains(.control) { mask |= controlKey }
        if flags.contains(.shift) { mask |= shiftKey }
        return mask
    }

    private static let named: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    /// Escape is never a shortcut (it cancels recording); modifier-only presses have no label.
    static func label(keyCode: Int, characters: String?) -> String? {
        if keyCode == kVK_Escape { return nil }
        if let name = named[keyCode] { return name }
        guard let first = characters?.trimmingCharacters(in: .whitespacesAndNewlines).first,
              !first.isWhitespace, first.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return String(first).uppercased()
    }
}

/// Shortcuts that work from any app. Each can be rebound in Settings.
nonisolated enum GlobalAction: String, CaseIterable, Identifiable, Codable {
    case toggle, newTask, pin, focus, moveHere

    var id: Self { self }

    var title: String {
        switch self {
        case .toggle: "Open / close Nook"
        case .newTask: "New task"
        case .pin: "Pin / unpin the panel"
        case .focus: "Start a focus (pick a task)"
        case .moveHere: "Move Nook to the display under the mouse"
        }
    }

    /// ⌥⌘N was Nook's only hotkey and stays "new task". The rest use ⌃⌥, which apps rarely
    /// take and which skips Rectangle's ⌃⌥ D/F/G/E/T/U/I/J/K/C.
    var defaultShortcut: Shortcut {
        switch self {
        case .toggle: Shortcut(keyCode: kVK_ANSI_N, modifiers: controlKey | optionKey, key: "N")
        case .newTask: Shortcut(keyCode: kVK_ANSI_N, modifiers: cmdKey | optionKey, key: "N")
        case .pin: Shortcut(keyCode: kVK_ANSI_P, modifiers: controlKey | optionKey, key: "P")
        case .focus: Shortcut(keyCode: kVK_ANSI_S, modifiers: controlKey | optionKey, key: "S")
        case .moveHere: Shortcut(keyCode: kVK_ANSI_M, modifiers: controlKey | optionKey, key: "M")
        }
    }
}

/// Fixed keys while the panel is open, listed in Settings.
enum PanelShortcuts {
    static let all: [(keys: String, title: String)] = [
        ("⌘1  ⌘2  ⌘3", "Workspace / Day / Insights"),
        ("⌘N", "New task"),
        ("⇥  ⇧⇥", "Next / previous field in the new-task card"),
        ("↩  ⌥↩", "Add the task / add and start focusing"),
        ("← →", "Previous / next day on the Day tab"),
        ("esc", "Close the card, then the panel"),
        ("⌘Z  ⇧⌘Z", "Undo / redo"),
    ]
}
