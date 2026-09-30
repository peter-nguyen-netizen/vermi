import SwiftUI

struct Theme {
    /// Recomputed per access from the user's selected accent theme. Views refresh
    /// when the accent changes because MainWindowView keys its subtree on it.
    static var colors: Colors { Colors(accent: .current) }
    static let spacing = Spacing()
    static let sizes = Sizes()
}

// MARK: - Accent themes

/// User-selectable accent. Neutrals tint toward the accent; semantic and
/// type-badge colors stay constant across themes.
enum AccentTheme: String, CaseIterable, Identifiable {
    case vermilion, amber, emerald, teal, indigo, violet, rose

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    /// Accent RGB for light / dark appearance.
    var light: (Double, Double, Double) {
        switch self {
        case .vermilion: return (0.894, 0.314, 0.165)
        case .amber:     return (0.780, 0.467, 0.078)
        case .emerald:   return (0.055, 0.620, 0.388)
        case .teal:      return (0.055, 0.580, 0.533)
        case .indigo:    return (0.322, 0.314, 0.839)
        case .violet:    return (0.506, 0.263, 0.878)
        case .rose:      return (0.839, 0.224, 0.420)
        }
    }
    var dark: (Double, Double, Double) {
        switch self {
        case .vermilion: return (1.000, 0.416, 0.263)
        case .amber:     return (0.929, 0.647, 0.227)
        case .emerald:   return (0.204, 0.769, 0.537)
        case .teal:      return (0.169, 0.745, 0.690)
        case .indigo:    return (0.533, 0.525, 0.949)
        case .violet:    return (0.663, 0.529, 0.949)
        case .rose:      return (0.949, 0.416, 0.588)
        }
    }

    var swatch: Color { Color(light: rgb(light.0, light.1, light.2), dark: rgb(dark.0, dark.1, dark.2)) }

    static var current: AccentTheme {
        AccentTheme(rawValue: UserDefaults.standard.string(forKey: "accentTheme") ?? "") ?? .vermilion
    }
}

extension Color {
    /// A color that resolves to `light` in light appearance and `dark` in dark
    /// appearance. Adapts automatically when the view's colorScheme changes.
    init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(isDark ? dark : light)
        })
    }
}

private func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
    Color(red: r, green: g, blue: b)
}

private typealias RGB = (Double, Double, Double)

/// Linear blend of two RGB colors by fraction `f` (0 = base, 1 = accent).
private func blend(_ base: RGB, _ acc: RGB, _ f: Double) -> Color {
    rgb(base.0 + (acc.0 - base.0) * f,
        base.1 + (acc.1 - base.1) * f,
        base.2 + (acc.2 - base.2) * f)
}

// MARK: - Colors (accent-driven; neutrals tint toward the accent)

struct Colors {
    let primary: Color
    let primaryHover: Color
    let primaryPressed: Color
    let primaryForeground: Color

    // Semantic — constant across themes.
    let success = Color(light: rgb(0.09, 0.56, 0.35), dark: rgb(0.35, 0.80, 0.55))
    let warning = Color(light: rgb(0.82, 0.53, 0.06), dark: rgb(0.96, 0.74, 0.28))
    let error = Color(light: rgb(0.82, 0.18, 0.22), dark: rgb(0.96, 0.44, 0.44))
    let info = Color(light: rgb(0.13, 0.46, 0.80), dark: rgb(0.42, 0.66, 0.96))

    // Surfaces / neutrals — tinted from the accent.
    let background: Color
    let surface: Color
    let surfaceHover: Color
    let surfaceActive: Color
    let sidebarBackground: Color
    let sidebarBorder: Color
    let muted: Color
    let mutedForeground: Color
    let text: Color
    let textSecondary: Color
    let textTertiary: Color
    let border: Color
    let borderSubtle: Color
    let borderStrong: Color
    let ring: Color
    let codeBackground: Color

    // JSON viewer syntax — constant across themes.
    let jsonKey = Color(light: rgb(0.52, 0.30, 0.78), dark: rgb(0.75, 0.58, 0.98))
    let jsonString = Color(light: rgb(0.13, 0.55, 0.30), dark: rgb(0.48, 0.82, 0.56))
    let jsonNumber = Color(light: rgb(0.85, 0.44, 0.10), dark: rgb(0.96, 0.66, 0.34))
    let jsonBool = Color(light: rgb(0.18, 0.45, 0.88), dark: rgb(0.48, 0.68, 0.98))

    init(accent: AccentTheme = .current) {
        let aL = accent.light, aD = accent.dark

        // Tinted neutral = blend(base grey, accent, fraction) per appearance.
        func t(_ baseL: RGB, _ baseD: RGB, _ fL: Double, _ fD: Double) -> Color {
            Color(light: blend(baseL, aL, fL), dark: blend(baseD, aD, fD))
        }

        primary = Color(light: rgb(aL.0, aL.1, aL.2), dark: rgb(aD.0, aD.1, aD.2))
        primaryHover = Color(light: blend(aL, (1, 1, 1), 0.12), dark: blend(aD, (1, 1, 1), 0.15))
        primaryPressed = Color(light: blend(aL, (0, 0, 0), 0.18), dark: blend(aD, (0, 0, 0), 0.15))
        primaryForeground = Color(light: .white, dark: rgb(0.08, 0.07, 0.06))

        // Mix fractions bumped to make the accent tint visible (was 4-6%, too subtle).
        background       = t((0.984, 0.980, 0.976), (0.078, 0.071, 0.063), 0.08, 0.10)
        surface          = t((1.000, 1.000, 1.000), (0.118, 0.106, 0.094), 0.04, 0.08)
        surfaceHover     = t((0.949, 0.941, 0.933), (0.149, 0.133, 0.125), 0.08, 0.10)
        surfaceActive    = t((0.910, 0.894, 0.882), (0.184, 0.165, 0.149), 0.10, 0.12)
        sidebarBackground = t((0.968, 0.960, 0.953), (0.098, 0.090, 0.078), 0.08, 0.10)
        sidebarBorder    = t((0.898, 0.878, 0.859), (0.200, 0.176, 0.157), 0.10, 0.12)
        muted            = t((0.949, 0.941, 0.933), (0.149, 0.133, 0.125), 0.08, 0.10)
        mutedForeground  = t((0.412, 0.373, 0.345), (0.651, 0.616, 0.584), 0.08, 0.07)
        text             = t((0.102, 0.090, 0.078), (0.957, 0.941, 0.925), 0.10, 0.07)
        textSecondary    = t((0.412, 0.373, 0.345), (0.651, 0.616, 0.584), 0.08, 0.07)
        textTertiary     = t((0.612, 0.576, 0.545), (0.431, 0.396, 0.369), 0.07, 0.06)
        border           = t((0.898, 0.878, 0.859), (0.200, 0.176, 0.157), 0.10, 0.12)
        borderSubtle     = t((0.925, 0.915, 0.905), (0.157, 0.141, 0.125), 0.08, 0.10)
        borderStrong     = t((0.835, 0.808, 0.780), (0.243, 0.212, 0.184), 0.12, 0.14)
        codeBackground   = t((0.975, 0.972, 0.968), (0.094, 0.086, 0.078), 0.06, 0.08)
        ring = Color(light: rgb(aL.0, aL.1, aL.2), dark: rgb(aD.0, aD.1, aD.2)).opacity(0.45)
    }

    // Avatar palette (works on both appearances)
    let avatarColors: [Color] = [
        rgb(0.36, 0.36, 0.94),
        rgb(0.13, 0.66, 0.42),
        rgb(0.88, 0.46, 0.12),
        rgb(0.85, 0.25, 0.48),
        rgb(0.52, 0.30, 0.78),
        rgb(0.20, 0.62, 0.80),
    ]

    func typeColor(_ type: String) -> Color {
        switch type.lowercased() {
        case "string": return Color(light: rgb(0.13, 0.55, 0.30), dark: rgb(0.48, 0.82, 0.56))
        case "list": return Color(light: rgb(0.85, 0.44, 0.12), dark: rgb(0.96, 0.66, 0.34))
        case "hash": return Color(light: rgb(0.52, 0.30, 0.78), dark: rgb(0.75, 0.58, 0.98))
        case "set": return Color(light: rgb(0.18, 0.45, 0.88), dark: rgb(0.48, 0.68, 0.98))
        case "zset": return Color(light: rgb(0.85, 0.25, 0.48), dark: rgb(0.95, 0.50, 0.68))
        case "json", "rejson-rl": return Color(light: rgb(0.13, 0.55, 0.55), dark: rgb(0.40, 0.82, 0.82))
        default: return Color(light: rgb(0.45, 0.47, 0.53), dark: rgb(0.62, 0.64, 0.70))
        }
    }

    func avatarColor(for name: String) -> Color {
        let index = abs(name.hashValue) % avatarColors.count
        return avatarColors[index]
    }
}

// MARK: - Spacing (4pt base scale)

struct Spacing {
    let xs: CGFloat = 2
    let sm: CGFloat = 4
    let md: CGFloat = 8
    let lg: CGFloat = 12
    let xl: CGFloat = 16
    let xxl: CGFloat = 24
    let xxxl: CGFloat = 32
}

// MARK: - Sizes

struct Sizes {
    let sidebarWidth: CGFloat = 240
    let detailSidebarWidth: CGFloat = 280
    let tabHeight: CGFloat = 36
    let buttonHeight: CGFloat = 32
    let cornerRadius: CGFloat = 14
    let smallCornerRadius: CGFloat = 10
    let cardCornerRadius: CGFloat = 20
    let iconSize: CGFloat = 12
    /// Left padding for custom titlebar (traffic light buttons width).
    let titlebarLeadingPad: CGFloat = 76
}

// MARK: - Button styles (shadcn variants)

/// Solid primary button — filled accent, white text, hover/press states.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundColor(Theme.colors.primaryForeground)
            .frame(height: Theme.sizes.buttonHeight)
            .padding(.horizontal, Theme.spacing.xl)
            .background(
                RoundedRectangle(cornerRadius: Theme.sizes.smallCornerRadius)
                    .fill(configuration.isPressed ? Theme.colors.primaryPressed : Theme.colors.primary)
            )
            .softShadowSmall()
            .opacity(isEnabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .handCursor(isEnabled)
    }
}

/// Outline/secondary — white surface, soft shadow, subtle hover.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundColor(Theme.colors.text)
            .frame(height: Theme.sizes.buttonHeight)
            .padding(.horizontal, Theme.spacing.xl)
            .background(
                RoundedRectangle(cornerRadius: Theme.sizes.smallCornerRadius)
                    .fill(configuration.isPressed || isHovering ? Theme.colors.surfaceHover : Theme.colors.surface)
            )
            .softShadowSmall()
            .opacity(isEnabled ? 1 : 0.5)
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .handCursor(isEnabled)
    }
}

/// Ghost — transparent, hover fill. For toolbar / low-emphasis actions.
struct GhostButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundColor(Theme.colors.textSecondary)
            .padding(.horizontal, Theme.spacing.lg)
            .frame(height: Theme.sizes.buttonHeight)
            .background(
                RoundedRectangle(cornerRadius: Theme.sizes.smallCornerRadius)
                    .fill(configuration.isPressed || isHovering ? Theme.colors.muted : Color.clear)
            )
            .onHover { isHovering = $0 }
            .handCursor()
    }
}

/// Destructive — red, for delete actions.
struct DestructiveButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundColor(Theme.colors.error)
            .frame(height: Theme.sizes.buttonHeight)
            .padding(.horizontal, Theme.spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: Theme.sizes.smallCornerRadius)
                    .fill(configuration.isPressed || isHovering ? Theme.colors.error.opacity(0.1) : Color.clear)
            )
            .onHover { isHovering = $0 }
            .handCursor()
    }
}

// MARK: - View Modifiers

extension View {
    func cardStyle() -> some View {
        self
            .padding(Theme.spacing.xl)
            .background(Theme.colors.surface)
            .cornerRadius(Theme.sizes.cardCornerRadius)
            .softShadow()
    }

    /// Claymorphism-style dual-direction soft shadow.
    func softShadow() -> some View {
        self
            .shadow(color: Color(light: .black.opacity(0.07), dark: .black.opacity(0.30)),
                    radius: 10, x: 4, y: 4)
            .shadow(color: Color(light: .white.opacity(0.75), dark: .white.opacity(0.04)),
                    radius: 6, x: -2, y: -2)
    }

    /// Smaller soft shadow for inline elements (badges, pills, buttons).
    func softShadowSmall() -> some View {
        self
            .shadow(color: Color(light: .black.opacity(0.06), dark: .black.opacity(0.25)),
                    radius: 5, x: 2, y: 2)
            .shadow(color: Color(light: .white.opacity(0.65), dark: .white.opacity(0.03)),
                    radius: 4, x: -1, y: -1)
    }

    /// Inset-style background (for search fields, input areas).
    func insetField() -> some View {
        self
            .background(Theme.colors.surfaceHover)
            .cornerRadius(Theme.sizes.smallCornerRadius)
            .shadow(color: Color(light: .black.opacity(0.06), dark: .black.opacity(0.20)),
                    radius: 3, x: 1, y: 1)
    }

    /// Conditional modifier — apply transform only when condition is true.
    @ViewBuilder
    func `if`<T: View>(_ condition: Bool, transform: (Self) -> T) -> some View {
        if condition { transform(self) } else { self }
    }

    // Legacy modifiers, now backed by the shadcn button styles above.
    func buttonPrimary() -> some View {
        buttonStyle(PrimaryButtonStyle())
    }

    func buttonSecondary() -> some View {
        buttonStyle(SecondaryButtonStyle())
    }

    func inputField() -> some View {
        modifier(InputFieldModifier())
    }

    func sectionHeader() -> some View {
        self
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundColor(Theme.colors.textSecondary)
            .textCase(.uppercase)
    }
}

/// shadcn-style input: bordered, focus ring on edit.
struct InputFieldModifier: ViewModifier {
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(.system(size: 14, design: .rounded))
            .padding(.horizontal, Theme.spacing.lg)
            .frame(height: Theme.sizes.buttonHeight)
            .background(Theme.colors.surfaceHover)
            .cornerRadius(Theme.sizes.smallCornerRadius)
            .shadow(color: Color(light: .black.opacity(0.05), dark: .black.opacity(0.18)),
                    radius: 3, x: 1, y: 1)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.sizes.smallCornerRadius)
                    .stroke(isFocused ? Theme.colors.primary.opacity(0.6) : Color.clear,
                            lineWidth: 1.5)
            )
            .focused($isFocused)
            .animation(.easeOut(duration: 0.12), value: isFocused)
    }
}

// MARK: - Components

/// Small colored pill showing a Redis key type (string/list/hash/set/zset)
struct TypeBadge: View {
    let type: String

    var body: some View {
        Text(type.uppercased())
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundColor(.white)
            .background(Theme.colors.typeColor(type))
            .cornerRadius(8)
            .softShadowSmall()
    }
}

/// Neutral outline badge — soft pill style.
struct Badge: View {
    let text: String
    var color: Color = Theme.colors.textSecondary

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundColor(color)
            .background(color.opacity(0.1))
            .cornerRadius(8)
            .softShadowSmall()
    }
}

/// Connection status indicator dot
struct StatusIndicator: View {
    let isConnected: Bool

    var body: some View {
        Circle()
            .fill(isConnected ? Theme.colors.success : Theme.colors.error)
            .frame(width: 6, height: 6)
            .help(isConnected ? "Connected" : "Disconnected — last ping failed")
    }
}

/// Section divider with optional label
struct SectionDivider: View {
    let label: String?

    init(label: String? = nil) {
        self.label = label
    }

    var body: some View {
        HStack(spacing: Theme.spacing.md) {
            if let label = label {
                Text(label.uppercased())
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.colors.textTertiary)
            }
            Rectangle()
                .fill(Theme.colors.borderSubtle)
                .frame(height: 0.5)
        }
    }
}
