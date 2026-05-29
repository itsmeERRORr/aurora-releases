import SwiftUI

struct TopCamerasPanel: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AuroraPanelHeader(title: "Top Cameras", actionLabel: "View all →")

            let cameras = (appState.totalStatsReport?.allCameras ?? []).prefix(4)

            if cameras.isEmpty {
                emptyState
            } else {
                VStack(spacing: 4) {
                    ForEach(Array(cameras.enumerated()), id: \.offset) { idx, camera in
                        TopCameraRow(rank: idx + 1, camera: camera)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .auroraStaticCard()
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("No camera data yet")
                .font(.manrope(12, weight: .semibold))
                .foregroundStyle(Color.auroraFaint)
            Text("Cameras detected from EXIF appear here.")
                .font(.manrope(11, weight: .medium))
                .foregroundStyle(Color.auroraFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

struct TopCameraRow: View {
    let rank: Int
    let camera: StatsReport.CameraStat

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            RankBadge(rank: rank)

            IconChip(systemName: "camera.fill", color: accentForRank(rank), size: 34, iconScale: 0.5)

            VStack(alignment: .leading, spacing: 2) {
                Text(camera.fullName)
                    .font(.auroraEventName)
                    .foregroundStyle(Color.auroraTxt)
                    .lineLimit(1)
                Text(camera.make.isEmpty ? "Camera body" : camera.make)
                    .font(.manrope(11, weight: .semibold))
                    .foregroundStyle(Color.auroraFaint)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            SpeedPill(text: "\(AuroraFormat.count(camera.count))", tint: accentForRank(rank))
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
