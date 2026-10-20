import SwiftUI

extension Color {
    static let neuripsAccent = Color(red: 0.30, green: 0.31, blue: 0.82)
    static let neuripsTeal = Color(red: 0.08, green: 0.58, blue: 0.57)
    static let neuripsOrange = Color(red: 0.92, green: 0.48, blue: 0.16)
}

struct AppCard: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.18 : 0.07), radius: 14, y: 5)
    }
}

extension View {
    func appCard() -> some View { modifier(AppCard()) }
}
