import SwiftUI

/// Light / Dark / System appearance, persisted across launches.
enum AppearanceMode: String, CaseIterable {
    case system, light, dark

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    var next: AppearanceMode {
        switch self {
        case .system: return .light
        case .light: return .dark
        case .dark: return .system
        }
    }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

/// Small button that cycles System → Light → Dark. Bind to an @AppStorage value.
struct AppearanceToggle: View {
    @Binding var mode: AppearanceMode
    @State private var isHovering = false

    var body: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) { mode = mode.next }
        }) {
            Image(systemName: mode.icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.colors.textSecondary)
                .frame(width: 30, height: 30)
                .background(Theme.colors.surface)
                .cornerRadius(Theme.sizes.smallCornerRadius)
                .softShadowSmall()
        }
        .buttonStyle(.plain).handCursor()
        .onHover { isHovering = $0 }
        .help("Appearance: \(mode.label)")
    }
}

/// Subtle diagonal gradient tinted with the accent, used behind whole screens.
struct GradientBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Theme.colors.primary.opacity(0.06),
                Theme.colors.background,
                Theme.colors.background,
                Theme.colors.info.opacity(0.05)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}
