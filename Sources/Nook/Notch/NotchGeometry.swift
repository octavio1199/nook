// Adapted from Pullo (MIT, (c) 2026 Gabriel Jordan)
import AppKit

struct NotchGeometry: Equatable {
    static let panelSize = CGSize(width: 960, height: 560)

    var screenFrame: NSRect
    var notchSize: CGSize
    var hasNotch: Bool

    var panelFrame: NSRect {
        NSRect(
            x: screenFrame.midX - Self.panelSize.width / 2,
            y: screenFrame.maxY - Self.panelSize.height,
            width: Self.panelSize.width,
            height: Self.panelSize.height
        )
    }

    static var notchedScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
    }

    static let placeholder = NotchGeometry(screenFrame: .zero, notchSize: CGSize(width: 180, height: 24), hasNotch: false)
}

extension NotchGeometry {
    init(screen: NSScreen) {
        let frame = screen.frame
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let width = frame.width - left.width - right.width
            self.init(
                screenFrame: frame,
                notchSize: CGSize(width: width, height: screen.safeAreaInsets.top),
                hasNotch: true
            )
            return
        }
        let menuBarHeight = max(frame.maxY - screen.visibleFrame.maxY, 24)
        self.init(screenFrame: frame, notchSize: CGSize(width: 180, height: menuBarHeight), hasNotch: false)
    }
}
