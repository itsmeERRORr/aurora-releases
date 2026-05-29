import SwiftUI

// MARK: - Color System (HSL Dark Theme)

extension Color {
    // Hex initializer
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    // Primary Colors
    static let primaryPurple = Color(hex: "4E79D1") // Azul claro dos gráficos
    static let primaryPurpleLight = Color(hue: 250/360, saturation: 0.9, brightness: 0.75)
    static let primaryPurpleDark = Color(hue: 250/360, saturation: 1.0, brightness: 0.55)

    // Accent Colors
    static let accentGreen = Color(hue: 142/360, saturation: 0.76, brightness: 0.45)
    static let accentGreenLight = Color(hue: 142/360, saturation: 0.7, brightness: 0.55)

    // Background Colors
    static let bgDark = Color(hex: "282F4B") // Fundo azul escuro
    static let bgDarkGradientTopLeading = Color(hex: "4A5680")   // Azul mais claro (topo) — gradiente mais visível
    static let bgDarkGradientBottomTrailing = Color(hex: "222840") // Escuro (fundo-direita)
    static let bgMedium = Color(hue: 250/360, saturation: 0.12, brightness: 0.12)
    static let bgLight = Color(hue: 250/360, saturation: 0.1, brightness: 0.16)

    // Glass Colors
    static let glassBase = Color.white.opacity(0.05)
    static let glassStrong = Color.white.opacity(0.1)
    static let glassBorder = Color.white.opacity(0.15)

    // Text Colors
    static let textPrimary = Color.white.opacity(0.95)
    static let textSecondary = Color.white.opacity(0.6)
    static let textTertiary = Color.white.opacity(0.4)

    // Import statistics dashboard accents
    static let importNavy = Color(hex: "031528")
    static let importCard = Color(hex: "061D35")
    static let importCardTop = Color(hex: "0A2746")
    static let importBorder = Color(hex: "2D4268").opacity(0.58)
    static let importBlue = Color(hex: "2F7DFF")
    static let importCyan = Color(hex: "00A6FF")
    static let importPurple = Color(hex: "7C3AED")
    static let importPink = Color(hex: "F12D74")
    static let importAmber = Color(hex: "F59E0B")
    static let importOrange = Color(hex: "FF6A00")
}

// MARK: - Glassmorphism Modifiers

extension View {
    func glassEffect(strong: Bool = false) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(strong ? Color.glassStrong : Color.glassBase)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.glassBorder, lineWidth: 1)
            )
    }

    func glassPanel() -> some View {
        self
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.glassBase)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.ultraThinMaterial)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.glassBorder, lineWidth: 1)
            )
    }

    func dashboardPanel(cornerRadius: CGFloat = 16) -> some View {
        self
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [Color.importCardTop.opacity(0.82), Color.importCard.opacity(0.92)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.importBorder, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.22), radius: 20, x: 0, y: 12)
    }

    func glassToolbar() -> some View {
        self
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Rectangle()
                    .fill(Color.glassStrong)
                    .background(.ultraThinMaterial)
            )
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color.glassBorder),
                alignment: .bottom
            )
    }
}

// MARK: - Button Styles

struct PrimaryButtonStyle: ButtonStyle {
    var isDestructive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isDestructive ? Color.red.opacity(0.9) : Color.primaryPurple)
                    .shadow(color: (isDestructive ? Color.red : Color.primaryPurple).opacity(0.3), radius: 8, y: 4)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.glassBase)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.ultraThinMaterial)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.glassBorder, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14))
            .foregroundColor(.textSecondary)
            .frame(width: 28, height: 28)
            .background(
                Circle()
                    .fill(Color.glassBase)
            )
            .overlay(
                Circle()
                    .strokeBorder(Color.glassBorder.opacity(0.5), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Custom Components

struct GlassCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.glassBase)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.glassBorder, lineWidth: 1)
            )
    }
}

struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(color)
                    .shadow(color: color.opacity(0.3), radius: 4, y: 2)
            )
    }
}

// MARK: - Typography Extensions

extension Font {
    static func inter(_ size: CGFloat, weight: Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func mono(_ size: CGFloat, weight: Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
