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
    @Environment(FocusTimer.self) private var focus
    @Environment(NotchInteraction.self) private var notch
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let state: NotchState
    let shape: S
    let notchWidth: CGFloat
    let height: CGFloat

    private var onBreak: Bool { focus.phase?.isBreak == true }
    /// Closed notch with the live-activity wings showing during a break.
    private var greenNotch: Bool { onBreak && state == .closed && notch.liveActivity == .focus }
    /// Open or peeking panel during a break.
    private var greenPanel: Bool { onBreak && state != .closed }

    var body: some View {
        Group {
            if settings.panelStyle.usesGlass(reduceTransparency: reduceTransparency), #available(macOS 26, *) {
                ZStack {
                    Color.clear.glassEffect(.regular, in: shape)
                    if settings.panelStyle == .glassDarkTop { darkTop }
                    Color.black.opacity(state == .closed ? 1 : 0)
                    // Glass: a green wash over the (opaque black) closed notch.
                    BreakGreen.closedFill.opacity(greenNotch ? 1 : 0)
                    BreakGreen.panelWash.opacity(greenPanel ? 1 : 0)
                }
            } else {
                ZStack {
                    Color.black
                    BreakGreen.closedFill.opacity(greenNotch ? 1 : 0)
                    BreakGreen.panelWash.opacity(greenPanel ? 1 : 0)
                }
            }
        }
        .overlay {
            // Soft inner glow along the edge of the closed notch.
            shape.stroke(BreakGreen.rim, lineWidth: 2)
                .opacity(greenNotch ? 1 : 0)
        }
        .animation(Motion.peek, value: greenNotch)
        .animation(Motion.peek, value: greenPanel)
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

/// Calm break palette derived from `Color.rest` (0.36, 0.82, 0.62).
enum BreakGreen {
    /// Closed notch: ~40% brightness of `rest` easing to a darker green.
    static let closedFill = LinearGradient(
        colors: [Color(red: 0.14, green: 0.33, blue: 0.25), Color(red: 0.05, green: 0.17, blue: 0.12)],
        startPoint: .top, endPoint: .bottom
    )
    static let rim = LinearGradient(
        colors: [Color.rest.opacity(0.34), Color.rest.opacity(0.10)],
        startPoint: .top, endPoint: .bottom
    )
    /// Open panel: a faint green light from the top.
    static let panelWash = LinearGradient(
        stops: [
            .init(color: Color.rest.opacity(0.16), location: 0),
            .init(color: Color.rest.opacity(0.05), location: 0.45),
            .init(color: Color.rest.opacity(0), location: 1),
        ],
        startPoint: .top, endPoint: .bottom
    )
    /// Outer glow color for the panel shadow (core change request).
    static let glow = Color.rest.opacity(0.35)
}
