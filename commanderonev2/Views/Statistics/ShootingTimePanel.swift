import SwiftUI

struct ShootingTimePanel: View {
    let report: StatsReport?
    var title: String = "Shooting Time"
    var subtitle: String = "Working hours and active shooting time from RAW capture timestamps"
    var sourceNamesByDay: [String: String] = [:]

    private var metrics: ShootingTimeMetrics? {
        report?.shootingTimeMetrics
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let metrics {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                    spacing: 10
                ) {
                    metricCard(
                        icon: "clock.fill",
                        label: "Total Working Hours",
                        value: formatDuration(metrics.totalCoverageSeconds),
                        detail: "Hours with at least one photo",
                        tint: .auroraCyan
                    )
                    metricCard(
                        icon: "camera.aperture",
                        label: "Shooting Time",
                        value: formatDuration(metrics.totalShootingSeconds),
                        detail: "Time actually shooting photos",
                        tint: .auroraMagenta
                    )
                    metricCard(
                        icon: "speedometer",
                        label: "Avg Pace",
                        value: formatPace(metrics.averagePhotosPerCoverageHour),
                        detail: "Photos per working hour",
                        tint: .auroraViolet
                    )
                    metricCard(
                        icon: "sun.max.fill",
                        label: "Longest Active Day",
                        value: formatDuration(metrics.longestCoverageDay?.coverageSeconds ?? 0),
                        detail: metrics.longestCoverageDay.map { detailForDay($0.dayKey) } ?? "-",
                        tint: .auroraBlue
                    )
                    metricCard(
                        icon: "bolt.fill",
                        label: "Longest Shooting Day",
                        value: formatDuration(metrics.longestShootingDay?.shootingSeconds ?? 0),
                        detail: metrics.longestShootingDay.map { detailForDay($0.dayKey) } ?? "-",
                        tint: .auroraLive
                    )
                    metricCard(
                        icon: "photo.stack.fill",
                        label: "Most RAW Photos in a Day",
                        value: metrics.busiestPhotoDay.map { AuroraFormat.count($0.photoCount) } ?? "-",
                        detail: metrics.busiestPhotoDay.map { detailForDay($0.dayKey) } ?? "-",
                        tint: .auroraHealthy
                    )
                }
            } else {
                emptyState
            }
        }
        .auroraCollapsibleStaticCard(storageKey: "shootingTime.\(title)", collapsedVisibleHeight: 31)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                AuroraCollapsibleHeaderTitle(title: title)
                Text(subtitle)
                    .font(.manrope(11, weight: .semibold))
                    .foregroundStyle(Color.auroraMuted)
            }
            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("No shooting-time data yet")
                .font(.manrope(12, weight: .semibold))
                .foregroundStyle(Color.auroraFaint)
            Text("Run a fresh EXIF scan/import so Aurora can read capture timestamps.")
                .font(.manrope(11, weight: .medium))
                .foregroundStyle(Color.auroraFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private func metricCard(icon: String, label: String, value: String, detail: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            IconChip(systemName: icon, color: tint, size: 34, iconScale: 0.48)
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(.manrope(9.5, weight: .heavy))
                    .tracking(1.1)
                    .foregroundStyle(Color.auroraFaint)
                Text(value)
                    .font(.sora(20, weight: .heavy))
                    .tracking(-0.5)
                    .foregroundStyle(Color.auroraTxt)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                detailText(detail, tint: tint)
                    .font(.manrope(11, weight: .semibold))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .auroraCard(paddingH: 13, paddingV: 13)
        .overlay(
            RoundedRectangle(cornerRadius: AuroraRadius.medium, style: .continuous)
                .strokeBorder(tint.opacity(0.2), lineWidth: 1)
        )
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 { return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(secs)s" }
        return "\(secs)s"
    }

    private func formatPace(_ value: Double?) -> String {
        guard let value, value.isFinite, value > 0 else { return "-" }
        if value >= 100 { return "\(Int(value.rounded())) /h" }
        return String(format: "%.1f /h", value)
    }

    @ViewBuilder
    private func detailText(_ detail: String, tint: Color) -> some View {
        if let range = detail.range(of: " @ ") {
            HStack(spacing: 0) {
                Text(String(detail[..<range.lowerBound]))
                    .foregroundStyle(Color.auroraMuted)
                Text(" @ ")
                    .foregroundStyle(Color.auroraFaint)
                Text(String(detail[range.upperBound...]))
                    .foregroundStyle(tint.opacity(0.95))
            }
        } else {
            Text(detail)
                .foregroundStyle(Color.auroraMuted)
        }
    }

    private func formatDay(_ dayKey: String) -> String {
        guard let date = Self.dayKeyFormatter.date(from: dayKey) else { return dayKey }
        return AuroraFormat.dateMedium(date)
    }

    private func detailForDay(_ dayKey: String) -> String {
        let day = formatDay(dayKey)
        guard let source = sourceNamesByDay[dayKey], !source.isEmpty else { return day }
        return "\(day) @ \(source)"
    }

    private static let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
