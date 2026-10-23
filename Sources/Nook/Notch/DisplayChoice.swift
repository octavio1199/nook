import AppKit

/// Which display Nook lives on (Settings › General › Show Nook on).
nonisolated enum DisplayChoice: Equatable, Hashable {
    /// The built-in display with the camera notch; the main display when there is none
    /// (an external monitor only, or the lid closed).
    case automatic
    /// The display with the menu bar (System Settings › Displays › "Main display").
    case main
    /// The display you're working on: where you last clicked, or where the app you switched to
    /// has its front window. Nook moves there while it is closed (moving the cursor alone doesn't count).
    case activeDisplay
    /// A specific display, by its stable UUID. Falls back to `automatic` while it is disconnected.
    case display(String)

    var storageValue: String {
        switch self {
        case .automatic: "automatic"
        case .main: "main"
        case .activeDisplay: "active"
        case .display(let id): "display:" + id
        }
    }

    init(storageValue: String?) {
        switch storageValue {
        case "main": self = .main
        // "mouse" was the earlier "Follow the mouse"; it became the active display.
        case "active", "mouse": self = .activeDisplay
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
    /// Index into `screens` for `choice`. `activePoint` is where the user is working (last click, or
    /// the middle of the front window), in global coordinates.
    static func choose(_ choice: DisplayChoice, screens: [ScreenInfo], activePoint: NSPoint?) -> Int? {
        guard !screens.isEmpty else { return nil }
        let main = screens.firstIndex { $0.isMain } ?? 0
        let automatic = screens.firstIndex { $0.hasNotch } ?? main
        switch choice {
        case .automatic:
            return automatic
        case .main:
            return main
        case .activeDisplay:
            guard let activePoint else { return automatic }
            return index(containing: activePoint, in: screens) ?? automatic
        case .display(let id):
            return screens.firstIndex { $0.id == id } ?? automatic
        }
    }

    /// The screen under `point`. A point exactly on a top/right edge (which `contains` excludes)
    /// goes to the nearest screen.
    static func index(containing point: NSPoint, in screens: [ScreenInfo]) -> Int? {
        screens.firstIndex { $0.frame.contains(point) } ?? nearest(to: point, in: screens)
    }

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
    static func nook(for choice: DisplayChoice, activePoint: NSPoint?) -> NSScreen? {
        let screens = NSScreen.screens
        return ScreenChooser.choose(choice, screens: screens.map(\.info), activePoint: activePoint).map { screens[$0] }
    }

    static func containing(_ point: NSPoint) -> NSScreen? {
        let screens = NSScreen.screens
        return ScreenChooser.index(containing: point, in: screens.map(\.info)).map { screens[$0] }
    }
}

/// Keeps track of where the user is working, for `DisplayChoice.activeDisplay`.
final class ActiveDisplayTracker {
    /// Global coordinates of the latest click, or of the middle of the front window after an app switch.
    private(set) var activePoint: NSPoint?
    /// Called (debounced) when the active point may be on another display.
    var onChange: (() -> Void)?
    private var observer: NSObjectProtocol?
    private var debounce: Task<Void, Never>?
    private var lastClick = Date.distantPast

    init() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated { self?.appActivated(pid) }
        }
    }

    isolated deinit {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    /// A click anywhere (another app's window, or the desktop).
    func noteClick(at point: NSPoint, now: Date = Date()) {
        activePoint = point
        lastClick = now
        scheduleChange()
    }

    /// ⌘Tab or the Dock: the app's front window is where work continues. An activation that a click
    /// just caused keeps the click (clicking another screen's desktop activates Finder, whose front
    /// window may be elsewhere).
    private func appActivated(_ pid: pid_t?) {
        guard let pid, pid != ProcessInfo.processInfo.processIdentifier else { return }
        noteActivation(frontWindow: Self.frontWindowFrame(of: pid))
    }

    func noteActivation(frontWindow frame: NSRect?, now: Date = Date()) {
        guard now.timeIntervalSince(lastClick) > 0.5, let frame else { return }
        activePoint = NSPoint(x: frame.midX, y: frame.midY)
        scheduleChange()
    }

    private func scheduleChange() {
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.onChange?()
        }
    }

    /// The app's frontmost normal window, converted to AppKit's bottom-left coordinates.
    /// Window bounds need no Screen Recording permission (only titles do).
    static func frontWindowFrame(of pid: pid_t) -> NSRect? {
        guard let primaryHeight = NSScreen.screens.first?.frame.height,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        for window in windows {
            guard (window[kCGWindowOwnerPID as String] as? Int32) == pid,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let dict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict),
                  bounds.width > 40, bounds.height > 40 else { continue }
            return NSRect(x: bounds.minX, y: primaryHeight - bounds.maxY, width: bounds.width, height: bounds.height)
        }
        return nil
    }
}
