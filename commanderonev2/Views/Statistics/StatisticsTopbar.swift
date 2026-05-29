import SwiftUI

struct StatisticsTopbar: View {
    @Binding var mode: StatsMode

    var body: some View {
        HStack(spacing: 14) {
            IconChip(systemName: "chart.bar.fill", color: .auroraViolet, size: 36, iconScale: 0.5)
            Text("Statistics")
                .font(.auroraTopbarH2)
                .tracking(-0.4)
                .foregroundStyle(Color.auroraTxt)
            Spacer()
            SegmentedToggle(
                options: [(.total, "Total"), (.lastImport, "Last Import")],
                selection: $mode
            )
        }
        .padding(.bottom, 20)
    }
}
