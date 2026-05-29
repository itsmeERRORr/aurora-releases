import SwiftUI

/// Hover scale used by EventStatsView lens/camera podium cards.
struct HoverScaleEffect: ViewModifier {
    @State private var hovering = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering ? 1.06 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovering)
            .onHover { hovering = $0 }
    }
}

/// Minimal Aurora-styled monthly bar chart used by EventStatsView. The main
/// PhotosPerMonthChart in Statistics is a separate, fancier component; this
/// one renders the same idea inside the per-event detail view.
struct MonthlyChartView: View {
    let data: [(month: String, count: Int)]

    @State private var animate = false

    var body: some View {
        let chart = Array(data.prefix(12))
        let maxV = max(chart.map(\.count).max() ?? 1, 1)

        return VStack(alignment: .leading, spacing: 14) {
            Text("MOST PHOTOS PER MONTH")
                .font(.auroraSectionLabel)
                .tracking(2)
                .foregroundStyle(Color.auroraFaint)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(chart.indices, id: \.self) { i in
                    let row = chart[i]
                    HStack(spacing: 12) {
                        Text(row.month)
                            .font(.manrope(12, weight: .semibold))
                            .foregroundStyle(Color.auroraMuted)
                            .frame(width: 80, alignment: .leading)
                        StorageBar(
                            fraction: animate ? Double(row.count) / Double(maxV) : 0,
                            height: 20, radius: 6,
                            animateOnAppear: false
                        )
                        Text(AuroraFormat.count(row.count))
                            .font(.sora(11.5, weight: .semibold))
                            .foregroundStyle(Color.auroraMuted)
                            .frame(width: 72, alignment: .trailing)
                    }
                }
            }
        }
        .dashboardPanel()
        .onAppear {
            withAnimation(.easeOut(duration: 0.9).delay(0.05)) { animate = true }
        }
    }
}
