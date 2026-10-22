import SwiftUI

extension Color {
    static let surface = Color.white.opacity(0.07)
    static let surfaceRaised = Color.white.opacity(0.11)
    static let hairline = Color.white.opacity(0.09)
    static let textPrimary = Color.white.opacity(0.94)
    static let textSecondary = Color.white.opacity(0.58)
    static let textTertiary = Color.white.opacity(0.36)
    static let accent = Color(red: 1.0, green: 0.62, blue: 0.24)
    static let focus = Color(red: 0.98, green: 0.42, blue: 0.36)
    static let rest = Color(red: 0.36, green: 0.82, blue: 0.62)
}

enum Typography {
    static let title = Font.system(size: 13, weight: .semibold)
    static let body = Font.system(size: 12.5)
    static let caption = Font.system(size: 11, weight: .medium)
    static let micro = Font.system(size: 10, weight: .semibold)
    static let timer = Font.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit()
}

struct Card<Content: View>: View {
    var title: String
    var symbol: String
    var trailing: AnyView?
    @ViewBuilder var content: Content

    init(_ title: String, symbol: String, trailing: AnyView? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.trailing = trailing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(Typography.micro).foregroundStyle(Color.textSecondary)
                Text(title.uppercased()).font(Typography.micro).tracking(0.8).foregroundStyle(Color.textSecondary)
                Spacer(minLength: 0)
                if let trailing { trailing }
            }
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.surface))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.hairline))
    }
}
