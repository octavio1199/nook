// Adapted from Pullo (MIT, (c) 2026 Gabriel Jordan)
import AppKit

struct NotchLayout {
    static let switcherSpace: CGFloat = 52
    static let wingWidth: CGFloat = 78

    let geometry: NotchGeometry
    var closedWings: CGFloat = 0

    func size(for state: NotchState) -> CGSize {
        let notch = geometry.notchSize
        switch state {
        case .closed:
            return CGSize(width: notch.width + closedWings * 2, height: notch.height)
        case .peek:
            return CGSize(width: max(notch.width + 200, 420), height: notch.height + 56)
        case .open:
            return CGSize(width: max(notch.width + 560, 780), height: notch.height + 380)
        }
    }

    func radii(for state: NotchState) -> (top: CGFloat, bottom: CGFloat) {
        switch state {
        case .closed: (6, 10)
        case .peek: (9, 20)
        case .open: (12, 30)
        }
    }

    func hitRect(for state: NotchState) -> NSRect {
        let size = size(for: state)
        let width = size.width + radii(for: state).top * 2
        let rect = NSRect(
            x: geometry.screenFrame.midX - width / 2,
            y: geometry.screenFrame.maxY - size.height,
            width: width,
            height: size.height
        )
        switch state {
        case .closed:
            return NSRect(x: rect.minX - 10, y: rect.minY - 4, width: rect.width + 20, height: rect.height + 6)
        case .peek:
            return rect.insetBy(dx: 0, dy: -2)
        case .open:
            let withSwitcher = NSRect(
                x: rect.minX,
                y: rect.minY - Self.switcherSpace,
                width: rect.width,
                height: rect.height + Self.switcherSpace
            )
            return withSwitcher.insetBy(dx: -16, dy: -16)
        }
    }
}
