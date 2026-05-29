import SwiftUI

/// Minimal Aurora-styled replacements for the original `StatCard` and
/// `StackableStatCard` used by EventStatsView. Kept simple — same API as the
/// pre-redesign call sites.
struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            IconChip(systemName: icon, color: color)
            Text(title)
                .font(.manrope(12, weight: .semibold))
                .foregroundStyle(Color.auroraMuted)
            Text(value)
                .font(.auroraStatValue)
                .tracking(-0.4)
                .foregroundStyle(Color.auroraTxt)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .auroraStaticCard()
    }
}

struct StackableStatCard: View {
    struct CardData: Identifiable {
        let id = UUID()
        let title: String
        let value: String
    }

    let cards: [CardData]
    let icon: String
    let color: Color

    @State private var index = 0
    @State private var hovering = false

    var body: some View {
        let current = cards.indices.contains(index) ? cards[index] : cards.first
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                IconChip(systemName: icon, color: color)
                Spacer()
                if cards.count > 1 {
                    HStack(spacing: 4) {
                        ForEach(cards.indices, id: \.self) { i in
                            Circle()
                                .fill(i == index ? color : Color.auroraStroke2)
                                .frame(width: 5, height: 5)
                        }
                    }
                }
            }
            Text(current?.title ?? "")
                .font(.manrope(12, weight: .semibold))
                .foregroundStyle(Color.auroraMuted)
            Text(current?.value ?? "—")
                .font(.auroraStatValue)
                .tracking(-0.4)
                .foregroundStyle(Color.auroraTxt)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .auroraStaticCard()
        .onHover { hovering = $0 }
        .onTapGesture {
            if cards.count > 1 { index = (index + 1) % cards.count }
        }
    }
}
