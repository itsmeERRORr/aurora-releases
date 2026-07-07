import SwiftUI

struct PhotosPerMonthChart: View {
    @Bindable var appState: AppState
    var onViewAll: () -> Void = {}

    @State private var animateBars = false
    @State private var hoveredMonth: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AuroraPanelHeader(
                title: "Most Photos per Month",
                actionLabel: appState.photosByMonth.count > 5 ? "View all →" : nil,
                action: onViewAll
            )

            let entries = topMonths()
            let maxValue = max(roundedMax(entries.map { $0.count }), 1)

            if entries.isEmpty {
                empty
            } else {
                VStack(spacing: 11) {
                    ForEach(entries, id: \.month) { row in
                        monthRow(row, maxValue: maxValue)
                    }
                }

                axis(maxValue: maxValue)
                    .padding(.top, 8)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .auroraCollapsibleStaticCard(storageKey: "dashboard.photosPerMonth")
        .onAppear {
            animateBars = true
        }
    }

    private func monthRow(_ row: (month: String, count: Int), maxValue: Int) -> some View {
        let isHighlighted = hoveredMonth == row.month
        return HStack(spacing: 14) {
            Text(row.month)
                .font(.manrope(12, weight: .semibold))
                .foregroundStyle(isHighlighted ? Color.auroraTxt : Color.auroraMuted)
                .frame(width: 76, alignment: .leading)
            timelineStyleBar(
                fraction: animateBars ? Double(row.count) / Double(maxValue) : 0,
                isHighlighted: isHighlighted
            )
            Text(AuroraFormat.count(row.count))
                .font(.sora(11.5, weight: isHighlighted ? .heavy : .semibold))
                .foregroundStyle(isHighlighted ? Color.auroraCyan : Color.auroraMuted)
                .frame(width: 70, alignment: .trailing)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                hoveredMonth = hovering ? row.month : nil
            }
        }
        .help("\(row.month): \(AuroraFormat.count(row.count)) RAWs")
    }

    private func timelineStyleBar(fraction: Double, isHighlighted: Bool) -> some View {
        GeometryReader { geo in
            let width = max(6, geo.size.width * min(max(fraction, 0), 1))
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.auroraPanel2.opacity(0.55))
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: isHighlighted
                                ? [Color.auroraCyan, Color.auroraBlue]
                                : [Color.auroraCyan, Color.auroraViolet, Color.auroraMagenta],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: width)
                    .shadow(color: (isHighlighted ? Color.auroraCyan : Color.auroraMagenta).opacity(isHighlighted ? 0.55 : 0.24), radius: isHighlighted ? 12 : 5, x: 0, y: 0)
            }
        }
        .frame(height: 22)
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.12), value: isHighlighted)
    }

    private func axis(maxValue: Int) -> some View {
        let step = maxValue / 4
        return HStack {
            Spacer().frame(width: 76 + 14)
            ForEach(0..<5) { i in
                Text(formatTick(step * i))
                    .font(.manrope(10, weight: .semibold))
                    .foregroundStyle(Color.auroraFaint)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer().frame(width: 70 + 14)
        }
    }

    private func formatTick(_ value: Int) -> String {
        if value == 0 { return "0" }
        if value >= 1000 {
            return "\(value / 1000)K"
        }
        return "\(value)"
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Text("No monthly data yet")
                .font(.manrope(12, weight: .semibold))
                .foregroundStyle(Color.auroraFaint)
            Text("After imports or Add Folder scans, monthly totals show up here.")
                .font(.manrope(11, weight: .medium))
                .foregroundStyle(Color.auroraFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func topMonths() -> [(month: String, count: Int)] {
        let all = appState.photosByMonth
        return Array(all.sorted { $0.count > $1.count }.prefix(5))
    }

    private func roundedMax(_ values: [Int]) -> Int {
        let m = (values.max() ?? 0)
        guard m > 0 else { return 0 }
        let bumped = Double(m) * 1.1
        let magnitude = pow(10.0, Double(Int(log10(bumped))))
        let rounded = (bumped / magnitude).rounded(.up) * magnitude
        let coarse = Int(rounded)
        // Snap to a multiple of 4 for axis cleanliness.
        let snap = max(4, (coarse / 4) * 4)
        return snap == 0 ? coarse : snap
    }
}
