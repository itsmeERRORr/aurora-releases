import SwiftUI

// MARK: - Color (hex initializer + Aurora palette)

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }

    // Surfaces
    static let auroraBg       = Color(hex: "0a0a16")
    static let auroraBg2      = Color(hex: "0e0d20")
    static let auroraPanel    = Color.white.opacity(0.035)
    static let auroraPanel2   = Color.white.opacity(0.055)
    static let auroraStroke   = Color.white.opacity(0.08)
    static let auroraStroke2  = Color.white.opacity(0.13)

    // Text
    static let auroraTxt    = Color(hex: "eef0fb")
    static let auroraMuted  = Color(hex: "9aa0c4")
    static let auroraFaint  = Color(hex: "6e739a")

    // Accents
    static let auroraCyan    = Color(hex: "22d3ee")
    static let auroraViolet  = Color(hex: "a78bfa")
    static let auroraMagenta = Color(hex: "f472b6")
    static let auroraAccent  = Color(hex: "8b5cf6")

    // Rankings
    static let auroraGold    = Color(hex: "f5c451")
    static let auroraSilver  = Color(hex: "c7d0dd")
    static let auroraBronze  = Color(hex: "d8965a")

    // Status
    static let auroraHealthy = Color(hex: "34d399")
    static let auroraLive    = Color(hex: "ff5470")
    static let auroraBlue    = Color(hex: "60a5fa")
    static let auroraPurple  = Color(hex: "c084fc")

    // Sparkline / chart secondary stops
    static let auroraCyanDeep    = Color(hex: "06b6d4")
    static let auroraVioletDeep  = Color(hex: "7c3aed")
    static let auroraMagentaDeep = Color(hex: "ec4899")
    static let auroraBlueDeep    = Color(hex: "3b82f6")
    static let auroraPurpleDeep  = Color(hex: "9333ea")
}

// MARK: - Gradients

extension LinearGradient {
    /// Primary Aurora gradient: 120° cyan → violet → magenta
    static let auroraGrad = LinearGradient(
        colors: [.auroraCyan, .auroraViolet, .auroraMagenta],
        startPoint: UnitPoint(x: 0, y: 1),
        endPoint: UnitPoint(x: 1, y: 0)
    )

    static let auroraGradMuted = LinearGradient(
        colors: [.auroraCyan.opacity(0.16), .auroraAccent.opacity(0.2)],
        startPoint: UnitPoint(x: 0, y: 1),
        endPoint: UnitPoint(x: 1, y: 0)
    )

    static let auroraGold = LinearGradient(
        colors: [Color(hex: "ffd874"), Color(hex: "f5c451")],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let auroraSilver = LinearGradient(
        colors: [Color(hex: "e6edf6"), Color(hex: "c7d0dd")],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let auroraBronze = LinearGradient(
        colors: [Color(hex: "f0b079"), Color(hex: "d8965a")],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

// MARK: - Typography

enum AuroraFontFamily {
    static let sora = "Sora"
    static let manrope = "Manrope"
}

extension Font {
    static func sora(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(AuroraFontFamily.sora, size: size).weight(weight)
    }
    static func manrope(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(AuroraFontFamily.manrope, size: size).weight(weight)
    }

    // Named presets from the handoff
    static var auroraBrand: Font     { .sora(16, weight: .bold) }
    static var auroraTopbarH2: Font  { .sora(23, weight: .bold) }
    static var auroraHero: Font      { .sora(30, weight: .heavy) }
    static var auroraStatValue: Font { .sora(28, weight: .bold) }
    static var auroraStatUnit: Font  { .sora(15, weight: .semibold) }
    static var auroraBigNumber: Font { .sora(46, weight: .heavy) }

    static var auroraSectionLabel: Font { .manrope(10.5, weight: .bold) }
    static var auroraNavItem: Font      { .manrope(13.5, weight: .semibold) }
    static var auroraEventName: Font    { .manrope(13, weight: .bold) }
    static var auroraMeta: Font         { .manrope(11.5, weight: .semibold) }
    static var auroraBody: Font         { .manrope(13, weight: .regular) }
    static var auroraButton: Font       { .manrope(13, weight: .bold) }
}

// MARK: - Spacing & radius constants

enum AuroraRadius {
    static let small: CGFloat = 12
    static let medium: CGFloat = 18
    static let large: CGFloat = 22
    static let badge: CGFloat = 11
    static let chip: CGFloat = 9
}

enum AuroraSpacing {
    static let cardPaddingH: CGFloat = 18
    static let cardPaddingV: CGFloat = 17
    static let heroPaddingH: CGFloat = 28
    static let heroPaddingV: CGFloat = 26
    static let mainPaddingH: CGFloat = 30
    static let mainPaddingV: CGFloat = 24
    static let gridGap: CGFloat = 15
    static let sidebarWidth: CGFloat = 252
    static let statusBarHeight: CGFloat = 42
}

// MARK: - Modifiers

struct AuroraCardStyle: ViewModifier {
    var radius: CGFloat = AuroraRadius.medium
    var paddingH: CGFloat = AuroraSpacing.cardPaddingH
    var paddingV: CGFloat = AuroraSpacing.cardPaddingV
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, paddingH)
            .padding(.vertical, paddingV)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(hovering ? Color.auroraPanel2 : Color.auroraPanel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(hovering ? Color.auroraStroke2 : Color.auroraStroke, lineWidth: 1)
            )
            .offset(y: hovering ? -2 : 0)
            .animation(.easeOut(duration: 0.18), value: hovering)
            .onHover { hovering = $0 }
    }
}

struct AuroraStaticCardStyle: ViewModifier {
    var radius: CGFloat = AuroraRadius.medium
    var paddingH: CGFloat = AuroraSpacing.cardPaddingH
    var paddingV: CGFloat = AuroraSpacing.cardPaddingV

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, paddingH)
            .padding(.vertical, paddingV)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.auroraPanel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.auroraStroke, lineWidth: 1)
            )
    }
}

struct AuroraCollapsibleStaticCardStyle: ViewModifier {
    var storageKey: String
    var radius: CGFloat = AuroraRadius.medium
    var paddingH: CGFloat = AuroraSpacing.cardPaddingH
    var paddingV: CGFloat = AuroraSpacing.cardPaddingV
    var collapsedHeight: CGFloat = 56
    var collapsedVisibleHeight: CGFloat

    @State private var hovering = false
    @AppStorage private var isCollapsed: Bool

    init(
        storageKey: String,
        radius: CGFloat = AuroraRadius.medium,
        paddingH: CGFloat = AuroraSpacing.cardPaddingH,
        paddingV: CGFloat = AuroraSpacing.cardPaddingV,
        collapsedHeight: CGFloat = 56,
        collapsedVisibleHeight: CGFloat? = nil
    ) {
        self.storageKey = storageKey
        self.radius = radius
        self.paddingH = paddingH
        self.paddingV = paddingV
        self.collapsedHeight = collapsedHeight
        self.collapsedVisibleHeight = collapsedVisibleHeight ?? (collapsedHeight - 14)
        _isCollapsed = AppStorage(wrappedValue: false, "aurora.collapsedPanel.\(storageKey)")
    }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let collapseAnimation = Animation.easeInOut(duration: 0.22)
        let toggleCollapse = {
            withAnimation(collapseAnimation) {
                isCollapsed.toggle()
            }
        }

        ZStack(alignment: .topLeading) {
            content
                .environment(\.auroraToggleCardCollapse, toggleCollapse)
                .environment(\.auroraCardIsCollapsed, isCollapsed)
                .padding(.leading, paddingH)
                .padding(.trailing, paddingH)
                .padding(.vertical, paddingV)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: isCollapsed ? collapsedVisibleHeight : nil, alignment: .top)
                .clipped()
                .compositingGroup()
        }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: isCollapsed ? collapsedHeight : nil, alignment: .top)
            .contentShape(shape)
            .clipShape(shape)
            .background(
                shape.fill(Color.auroraPanel)
            )
            .overlay(
                shape.strokeBorder(Color.auroraStroke, lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                if hovering {
                    Button {
                        toggleCollapse()
                    } label: {
                        Image(systemName: isCollapsed ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(Color.auroraCyan)
                            .frame(width: 22, height: 22)
                            .background(
                                Circle()
                                    .fill(Color.auroraPanel2.opacity(0.94))
                            )
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.auroraStroke2, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    .help(isCollapsed ? "Expand card" : "Collapse card")
                }
            }
            .animation(collapseAnimation, value: isCollapsed)
            .animation(.easeOut(duration: 0.14), value: hovering)
            .onHover { hovering = $0 }
    }
}

private struct AuroraToggleCardCollapseKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

private struct AuroraCardIsCollapsedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var auroraToggleCardCollapse: (() -> Void)? {
        get { self[AuroraToggleCardCollapseKey.self] }
        set { self[AuroraToggleCardCollapseKey.self] = newValue }
    }

    var auroraCardIsCollapsed: Bool {
        get { self[AuroraCardIsCollapsedKey.self] }
        set { self[AuroraCardIsCollapsedKey.self] = newValue }
    }
}

struct AuroraCollapsibleHeaderTitle: View {
    let title: String
    @Environment(\.auroraToggleCardCollapse) private var toggleCardCollapse

    var body: some View {
        Text(title.uppercased())
            .font(.auroraSectionLabel)
            .tracking(1.6)
            .foregroundStyle(Color.auroraFaint)
            .contentShape(Rectangle())
            .onTapGesture {
                toggleCardCollapse?()
            }
    }
}

extension View {
    func auroraCard(radius: CGFloat = AuroraRadius.medium,
                    paddingH: CGFloat = AuroraSpacing.cardPaddingH,
                    paddingV: CGFloat = AuroraSpacing.cardPaddingV) -> some View {
        modifier(AuroraCardStyle(radius: radius, paddingH: paddingH, paddingV: paddingV))
    }
    func auroraStaticCard(radius: CGFloat = AuroraRadius.medium,
                          paddingH: CGFloat = AuroraSpacing.cardPaddingH,
                          paddingV: CGFloat = AuroraSpacing.cardPaddingV) -> some View {
        modifier(AuroraStaticCardStyle(radius: radius, paddingH: paddingH, paddingV: paddingV))
    }
    func auroraCollapsibleStaticCard(storageKey: String,
                                     radius: CGFloat = AuroraRadius.medium,
                                     paddingH: CGFloat = AuroraSpacing.cardPaddingH,
                                     paddingV: CGFloat = AuroraSpacing.cardPaddingV,
                                     collapsedHeight: CGFloat = 56,
                                     collapsedVisibleHeight: CGFloat? = nil) -> some View {
        modifier(AuroraCollapsibleStaticCardStyle(
            storageKey: storageKey,
            radius: radius,
            paddingH: paddingH,
            paddingV: paddingV,
            collapsedHeight: collapsedHeight,
            collapsedVisibleHeight: collapsedVisibleHeight
        ))
    }
    func auroraGlow(_ color: Color = .auroraAccent, opacity: Double = 0.7) -> some View {
        shadow(color: color.opacity(opacity), radius: 14, x: 0, y: 8)
    }
}

// MARK: - App background

struct AuroraBackground: View {
    var body: some View {
        ZStack {
            Color.auroraBg.ignoresSafeArea()
            // top-right violet radial
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [Color.auroraAccent.opacity(0.22), .clear],
                        center: .center, startRadius: 0, endRadius: 600
                    )
                )
                .frame(width: 1100, height: 600)
                .offset(x: 380, y: -260)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
            // top-left cyan radial
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [Color.auroraCyan.opacity(0.13), .clear],
                        center: .center, startRadius: 0, endRadius: 500
                    )
                )
                .frame(width: 900, height: 500)
                .offset(x: -340, y: -180)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Button styles

struct AuroraGradientButtonStyle: ButtonStyle {
    var compact: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.auroraButton)
            .foregroundStyle(.white)
            .padding(.vertical, compact ? 8 : 11)
            .padding(.horizontal, compact ? 14 : 18)
            .background(
                RoundedRectangle(cornerRadius: AuroraRadius.badge, style: .continuous)
                    .fill(LinearGradient.auroraGrad)
            )
            .shadow(color: Color.auroraAccent.opacity(0.9), radius: 10, x: 0, y: 8)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct AuroraGhostButtonStyle: ButtonStyle {
    var active: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.manrope(12.5, weight: .semibold))
            .foregroundStyle(active ? Color.white : Color.auroraMuted)
            .padding(.vertical, 7)
            .padding(.horizontal, 14)
            .background(
                Group {
                    if active {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(LinearGradient.auroraGrad)
                            .shadow(color: Color.auroraAccent.opacity(0.7), radius: 10, x: 0, y: 6)
                    } else {
                        Color.clear
                    }
                }
            )
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Legacy modifiers (shims to keep older views compiling).
// Adopt `.auroraCard` / `.auroraStaticCard` for new code.

extension View {
    func glassEffect(strong: Bool = false) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: AuroraRadius.small, style: .continuous)
                    .fill(strong ? Color.auroraPanel2 : Color.auroraPanel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AuroraRadius.small, style: .continuous)
                    .strokeBorder(Color.auroraStroke, lineWidth: 1)
            )
    }
    func glassPanel() -> some View {
        self
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: AuroraRadius.medium, style: .continuous)
                    .fill(Color.auroraPanel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AuroraRadius.medium, style: .continuous)
                    .strokeBorder(Color.auroraStroke, lineWidth: 1)
            )
    }
    func dashboardPanel(cornerRadius: CGFloat = AuroraRadius.medium) -> some View {
        self
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.auroraPanel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.auroraStroke, lineWidth: 1)
            )
    }
    func glassToolbar() -> some View {
        self
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.auroraPanel2.background(.ultraThinMaterial))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundStyle(Color.auroraStroke),
                alignment: .bottom
            )
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var isDestructive: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.manrope(13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isDestructive ? AnyShapeStyle(Color.auroraLive) : AnyShapeStyle(LinearGradient.auroraGrad))
            )
            .shadow(color: (isDestructive ? Color.auroraLive : Color.auroraAccent).opacity(0.8), radius: 10, x: 0, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.manrope(12.5, weight: .semibold))
            .foregroundStyle(Color.auroraTxt)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.auroraPanel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.auroraStroke2, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.auroraMuted)
            .frame(width: 28, height: 28)
            .background(Circle().fill(Color.auroraPanel))
            .overlay(Circle().strokeBorder(Color.auroraStroke, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct GlassCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: AuroraRadius.small, style: .continuous)
                    .fill(Color.auroraPanel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AuroraRadius.small, style: .continuous)
                    .strokeBorder(Color.auroraStroke, lineWidth: 1)
            )
    }
}

struct StatusBadge: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.manrope(11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(color))
    }
}

extension Font {
    static func inter(_ size: CGFloat, weight: Weight = .regular) -> Font {
        .manrope(size, weight: weight)
    }
    static func mono(_ size: CGFloat, weight: Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Backwards-compatible legacy aliases (kept temporarily so any
// straggler reference compiles; remove once all views migrated.)

extension Color {
    static var primaryPurple: Color { .auroraAccent }
    static var primaryPurpleLight: Color { .auroraViolet }
    static var primaryPurpleDark: Color { .auroraVioletDeep }
    static var accentGreen: Color { .auroraHealthy }
    static var accentGreenLight: Color { .auroraHealthy.opacity(0.7) }
    static var bgDark: Color { .auroraBg }
    static var bgMedium: Color { .auroraBg2 }
    static var bgLight: Color { .auroraPanel }
    static var glassBase: Color { .auroraPanel }
    static var glassStrong: Color { .auroraPanel2 }
    static var glassBorder: Color { .auroraStroke2 }
    static var textPrimary: Color { .auroraTxt }
    static var textSecondary: Color { .auroraMuted }
    static var textTertiary: Color { .auroraFaint }
    static var importNavy: Color { .auroraBg }
    static var importCard: Color { .auroraPanel }
    static var importCardTop: Color { .auroraPanel2 }
    static var importBorder: Color { .auroraStroke }
    static var importBlue: Color { .auroraBlue }
    static var importCyan: Color { .auroraCyan }
    static var importPurple: Color { .auroraAccent }
    static var importPink: Color { .auroraMagenta }
    static var importAmber: Color { .auroraGold }
    static var importOrange: Color { .auroraBronze }
    static var bgDarkGradientTopLeading: Color { .auroraBg2 }
    static var bgDarkGradientBottomTrailing: Color { .auroraBg }
}
