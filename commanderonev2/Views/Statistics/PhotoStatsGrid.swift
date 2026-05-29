import SwiftUI

struct PhotoStatsGrid: View {
    @Bindable var appState: AppState
    let mode: StatsMode

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: AuroraSpacing.gridGap), count: 5),
            spacing: AuroraSpacing.gridGap
        ) {
            PhotoStatCard(icon: "photo.stack.fill", accent: .auroraCyan,
                          label: "Photos Added", value: photosAdded)
            PhotoStatCard(icon: "camera.aperture", accent: .auroraBlue,
                          label: "Avg ISO", value: avgISO)
            PhotoStatCard(icon: "circle.dotted", accent: .auroraViolet,
                          label: "Avg Aperture", value: avgAperture)
            PhotoStatCard(icon: "viewfinder", accent: .auroraMagenta,
                          label: "Avg Focal", value: avgFocal)
            PhotoStatCard(icon: "timer", accent: .auroraPurple,
                          label: "Avg Shutter", value: avgShutter)
        }
    }

    private var report: StatsReport? {
        mode == .lastImport ? appState.statsReport : appState.totalStatsReport
    }

    private var photosAdded: String {
        guard let r = report, r.totalFilesAnalyzed > 0 else { return "—" }
        return AuroraFormat.count(r.totalFilesAnalyzed)
    }
    private var avgISO: String {
        guard let r = report, let v = r.avgISO, v > 0 else { return "—" }
        return AuroraFormat.iso(v)
    }
    private var avgAperture: String {
        guard let r = report, let v = r.avgAperture, v > 0 else { return "—" }
        return AuroraFormat.aperture(v)
    }
    private var avgFocal: String {
        guard let r = report, let v = r.avgFocalLength, v > 0 else { return "—" }
        return AuroraFormat.focal(v)
    }
    private var avgShutter: String {
        guard let r = report, let v = r.avgShutterSpeed, v > 0 else { return "—" }
        return AuroraFormat.shutter(v)
    }
}

struct PhotoStatCard: View {
    let icon: String
    let accent: Color
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            IconChip(systemName: icon, color: accent)
            Text(label)
                .font(.manrope(12, weight: .semibold))
                .foregroundStyle(Color.auroraMuted)
            Text(value)
                .font(.auroraStatValue)
                .tracking(-0.5)
                .foregroundStyle(Color.auroraTxt)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .auroraCard()
    }
}
