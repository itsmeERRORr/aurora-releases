import SwiftUI

/// Square accent chip used throughout the Aurora design (general stats,
/// photo stats, hero strip, sidebar brand, etc.).
struct IconChip: View {
    let systemName: String
    var color: Color = .auroraAccent
    var size: CGFloat = 30
    var iconScale: CGFloat = 0.5

    var body: some View {
        RoundedRectangle(cornerRadius: AuroraRadius.chip, style: .continuous)
            .fill(color.opacity(0.15))
            .overlay(
                Image(systemName: systemName)
                    .font(.system(size: size * iconScale, weight: .semibold))
                    .foregroundStyle(color)
            )
            .frame(width: size, height: size)
    }
}

/// Solid gradient chip — used by the sidebar brand logo and a few accents.
struct GradientIconChip: View {
    let systemName: String
    var size: CGFloat = 38
    var iconScale: CGFloat = 0.45

    var body: some View {
        RoundedRectangle(cornerRadius: AuroraRadius.badge, style: .continuous)
            .fill(LinearGradient.auroraGrad)
            .overlay(
                Image(systemName: systemName)
                    .font(.system(size: size * iconScale, weight: .bold))
                    .foregroundStyle(.white)
            )
            .frame(width: size, height: size)
            .shadow(color: .auroraAccent.opacity(0.7), radius: 12, x: 0, y: 8)
    }
}

#Preview {
    HStack(spacing: 16) {
        IconChip(systemName: "chart.bar.fill", color: .auroraCyan)
        IconChip(systemName: "bolt.fill", color: .auroraViolet)
        IconChip(systemName: "clock", color: .auroraMagenta)
        GradientIconChip(systemName: "photo.stack.fill")
    }
    .padding(40)
    .background(Color.auroraBg)
}
