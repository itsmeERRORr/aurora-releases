import SwiftUI

struct TopLensesPanel: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AuroraPanelHeader(title: "Top Lenses", actionLabel: "View all →")

            let lenses = (appState.totalStatsReport?.allLenses ?? []).prefix(4)

            if lenses.isEmpty {
                emptyState
            } else {
                VStack(spacing: 4) {
                    ForEach(Array(lenses), id: \.id) { lens in
                        TopLensRow(lens: lens)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .auroraStaticCard()
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("No lens data yet")
                .font(.manrope(12, weight: .semibold))
                .foregroundStyle(Color.auroraFaint)
            Text("Lenses detected from EXIF appear here.")
                .font(.manrope(11, weight: .medium))
                .foregroundStyle(Color.auroraFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

struct TopLensRow: View {
    let lens: StatsReport.LensStat

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            RankBadge(rank: lens.rank)

            IconChip(systemName: "camera.aperture", color: accentForRank(lens.rank), size: 34, iconScale: 0.5)

            VStack(alignment: .leading, spacing: 2) {
                Text(lens.fullName)
                    .font(.auroraEventName)
                    .foregroundStyle(Color.auroraTxt)
                    .lineLimit(1)
                Text(lens.make.isEmpty ? "Lens" : lens.make)
                    .font(.manrope(11, weight: .semibold))
                    .foregroundStyle(Color.auroraFaint)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            SpeedPill(text: "\(AuroraFormat.count(lens.count))", tint: accentForRank(lens.rank))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(hovering ? Color.auroraPanel2 : Color.clear)
        )
        .onHover { hovering = $0 }
    }

    private func accentForRank(_ rank: Int) -> Color {
        switch rank {
        case 1: return .auroraCyan
        case 2: return .auroraViolet
        case 3: return .auroraMagenta
        default: return .auroraBlue
        }
    }
}
