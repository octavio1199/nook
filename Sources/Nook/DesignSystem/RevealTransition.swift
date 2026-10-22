// From Pullo (MIT, (c) 2026 Gabriel Jordan)
import SwiftUI

struct RevealModifier: ViewModifier {
    let progress: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .blur(radius: (1 - progress) * 8)
            .scaleEffect(0.96 + 0.04 * progress, anchor: .top)
            .offset(y: (1 - progress) * -6)
    }
}

extension AnyTransition {
    static func reveal(delay: Double) -> AnyTransition {
        .asymmetric(
            insertion: .modifier(active: RevealModifier(progress: 0), identity: RevealModifier(progress: 1))
                .animation(Motion.reveal.delay(delay)),
            removal: .modifier(active: RevealModifier(progress: 0), identity: RevealModifier(progress: 1))
                .animation(Motion.hover)
        )
    }
}
