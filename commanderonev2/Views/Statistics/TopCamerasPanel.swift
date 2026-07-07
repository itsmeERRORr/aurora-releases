import SwiftUI

struct TopCamerasPanel: View {
    @Bindable var appState: AppState
    var report: StatsReport?
    var onViewAll: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let allCameras = report?.allCameras ?? []
            AuroraPanelHeader(title: "Top Cameras", actionLabel: allCameras.count > 5 ? "View all →" : nil, action: onViewAll)

            let cameras = allCameras.prefix(5)

            if cameras.isEmpty {
                emptyState
            } else {
                VStack(spacing: 4) {
                    ForEach(Array(cameras.enumerated()), id: \.offset) { idx, camera in
                        TopCameraRow(rank: idx + 1, camera: camera)
                    }
                }
                .frame(minHeight: 266, alignment: .top)
            }
        }
        .auroraCollapsibleStaticCard(storageKey: "dashboard.topCameras")
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
    @State private var showInfo = false

    var body: some View {
        HStack(spacing: 12) {
            RankBadge(rank: rank)

            IconChip(systemName: "camera.fill", color: accentForRank(rank), size: 34, iconScale: 0.5)

            HStack(spacing: 4) {
                Text(displayName)
                    .font(.auroraEventName)
                    .foregroundStyle(Color.auroraTxt)
                    .lineLimit(1)

                if hasCameraInfo {
                    Button {
                        showInfo.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(hovering ? Color.auroraMuted.opacity(0.7) : Color.clear)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showInfo, arrowEdge: .trailing) {
                        cameraInfoPopover
                    }
                }
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

    @ViewBuilder
    private var cameraInfoPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let date = camera.lastSeenDate {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.auroraMuted)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Last photo date")
                            .font(.manrope(10, weight: .medium))
                            .foregroundStyle(Color.auroraFaint)
                        Text(date, format: .dateTime.day().month(.defaultDigits).year())
                            .font(.manrope(12, weight: .semibold))
                            .foregroundStyle(Color.auroraTxt)
                    }
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "camera.shutter.button")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.auroraMuted)
                VStack(alignment: .leading, spacing: 1) {
                    if let count = camera.maxShutterCount {
                        Text("Mechanical shutter count")
                            .font(.manrope(10, weight: .medium))
                            .foregroundStyle(Color.auroraFaint)
                        Text("~\(AuroraFormat.count(count))")
                            .font(.manrope(12, weight: .semibold))
                            .foregroundStyle(Color.auroraTxt)
                    } else {
                        Text("Shutter count")
                            .font(.manrope(10, weight: .medium))
                            .foregroundStyle(Color.auroraFaint)
                        Text("Electronic shutter detected. Mechanical shutter count unavailable.")
                            .font(.manrope(11, weight: .medium))
                            .foregroundStyle(Color.auroraMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var hasCameraInfo: Bool {
        camera.lastSeenDate != nil || camera.maxShutterCount != nil
    }

    private var displayName: String {
        camera.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
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
