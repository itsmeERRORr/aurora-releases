import SwiftUI

struct PhotosPerMonthChart: View {
    @Bindable var appState: AppState

    @State private var animateBars = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AuroraPanelHeader(title: "Most Photos per Month")

            let entries = topMonths()
            let maxValue = max(roundedMax(entries.map { $0.count }), 1)

            if entries.isEmpty {
                empty
            } else {
                VStack(spacing: 11) {
                    ForEach(entries, id: \.month) { row in
                        HStack(spacing: 14) {
                            Text(row.month)
                                .font(.manrope(12, weight: .semibold))
                                .foregroundStyle(Color.auroraMuted)
                                .frame(width: 76, alignment: .leading)
                            StorageBar(
                                fraction: animateBars ? Double(row.count) / Double(maxValue) : 0,
                                height: 22, radius: 7,
                                animateOnAppear: false
                            )
                            Text(AuroraFormat.count(row.count))
                                .font(.sora(11.5, weight: .semibold))
                                .foregroundStyle(Color.auroraMuted)
                                .frame(width: 70, alignment: .trailing)
                        }
                    }
                }

                axis(maxValue: maxValue)
                    .padding(.top, 8)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .auroraStaticCard()
        .onAppear {
            animateBars = false
            withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 1.0)) {
                animateBars = true
            }
        }
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
            Text("After a few imports, monthly totals show up here.")
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
