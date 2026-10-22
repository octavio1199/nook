// Adapted from Pullo (MIT, (c) 2026 Gabriel Jordan)
import SwiftUI

enum PanelStyle: String, CaseIterable, Identifiable {
    case solid, glass, glassDarkTop

    var id: Self { self }

    var title: String {
        switch self {
        case .solid: "Solid"
        case .glass: "Liquid Glass"
        case .glassDarkTop: "Glass, dark top"
        }
    }

    func usesGlass(reduceTransparency: Bool) -> Bool {
        guard self != .solid, !reduceTransparency else { return false }
        if #available(macOS 26, *) { return true }
        return false
    }
}

struct NotchBackground<S: Shape>: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let state: NotchState
    let shape: S
    let notchWidth: CGFloat
    let height: CGFloat

    var body: some View {
        if settings.panelStyle.usesGlass(reduceTransparency: reduceTransparency), #available(macOS 26, *) {
            ZStack {
                Color.clear.glassEffect(.regular, in: shape)
                if settings.panelStyle == .glassDarkTop { darkTop }
                Color.black.opacity(state == .closed ? 1 : 0)
            }
        } else {
            Color.black
        }
    }

    private var darkTop: some View {
        let black = notchWidth / 2 + 24
        let fade = max(black + 120, height * 1.2)
        return RadialGradient(
            stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: black / fade),
                .init(color: .black.opacity(0), location: 1),
            ],
            center: .top,
            startRadius: 0,
            endRadius: fade
        )
    }
}
