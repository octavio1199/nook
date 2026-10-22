import AppKit

/// Which display Nook lives on (Settings › General › Show Nook on).
nonisolated enum DisplayChoice: Equatable, Hashable {
    /// The built-in display with the camera notch; the main display when there is none
    /// (an external monitor only, or the lid closed).
    case automatic
    /// The display with the menu bar (System Settings › Displays › "Main display").
    case main
    /// Whichever display the pointer is on; Nook moves there while it is closed.
    case followMouse
    /// A specific display, by its stable UUID. Falls back to `automatic` while it is disconnected.
    case display(String)

    var storageValue: String {
        switch self {
        case .automatic: "automatic"
        case .main: "main"
        case .followMouse: "mouse"
        case .display(let id): "display:" + id
        }
    }

    init(storageValue: String?) {
        switch storageValue {
        case "main": self = .main
        case "mouse": self = .followMouse
        case let value? where value.hasPrefix("display:") && value.count > 8: self = .display(String(value.dropFirst(8)))
        default: self = .automatic
        }
    }
}

/// What the chooser needs to know about a screen (kept apart from `NSScreen` so it can be tested).
nonisolated struct ScreenInfo: Equatable {
    var id: String
    var name: String
    var frame: NSRect
    var hasNotch: Bool
    /// The menu-bar display (`NSScreen.screens.first`).
    var isMain: Bool
}

nonisolated enum ScreenChooser {
    /// Index into `screens` for `choice`. `pointer` is the mouse location (global coordinates).
    static func choose(_ choice: DisplayChoice, screens: [ScreenInfo], pointer: NSPoint?) -> Int? {
        guard !screens.isEmpty else { return nil }
        let main = screens.firstIndex { $0.isMain } ?? 0
        let automatic = screens.firstIndex { $0.hasNotch } ?? main
        switch choice {
        case .automatic:
            return automatic
        case .main:
            return main
        case .followMouse:
            guard let pointer else { return automatic }
            return screens.firstIndex { $0.frame.contains(pointer) } ?? nearest(to: pointer, in: screens) ?? automatic
        case .display(let id):
            return screens.firstIndex { $0.id == id } ?? automatic
        }
    }

    /// The pointer can sit exactly on a screen's top/right edge, which `contains` excludes.
    private static func nearest(to point: NSPoint, in screens: [ScreenInfo]) -> Int? {
        screens.indices.min { distance(point, screens[$0].frame) < distance(point, screens[$1].frame) }
    }

    private static func distance(_ p: NSPoint, _ r: NSRect) -> CGFloat {
        let dx = max(r.minX - p.x, 0, p.x - r.maxX)
        let dy = max(r.minY - p.y, 0, p.y - r.maxY)
        return dx * dx + dy * dy
    }
}

extension NSScreen {
    /// Stable across reboots and reconnects (the display number is not).
    var displayUUID: String {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue(),
              let text = CFUUIDCreateString(nil, uuid) as String? else { return localizedName }
        return text
    }

    var info: ScreenInfo {
        ScreenInfo(
            id: displayUUID, name: localizedName, frame: frame,
            hasNotch: safeAreaInsets.top > 0, isMain: self == NSScreen.screens.first
        )
    }

    /// The screen Nook should be on right now.
    static func nook(for choice: DisplayChoice, pointer: NSPoint? = NSEvent.mouseLocation) -> NSScreen? {
        let screens = NSScreen.screens
        return ScreenChooser.choose(choice, screens: screens.map(\.info), pointer: pointer).map { screens[$0] }
    }
}
