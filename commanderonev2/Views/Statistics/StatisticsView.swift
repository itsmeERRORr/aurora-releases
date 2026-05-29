import SwiftUI

struct StatisticsView: View {
    @Bindable var appState: AppState
    let statsRunner: StatsRunner?

    @State private var mode: StatsMode = .total

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                StatisticsTopbar(mode: $mode)

                GeneralStatsGrid(appState: appState, mode: mode)

                HeroEventCard(appState: appState) {
                    // TODO: navigate to the matched event detail view
                }

                PhotoStatsGrid(appState: appState, mode: mode)

                threeColumnRow

                twoColumnRow
            }
            .padding(.horizontal, AuroraSpacing.mainPaddingH)
            .padding(.vertical, AuroraSpacing.mainPaddingV)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }

    // 1 : 1 : 1.04 — approximated via weighted GeometryReader
    private var threeColumnRow: some View {
        GeometryReader { geo in
            let gap = AuroraSpacing.gridGap
            let totalGap = gap * 2
            let totalWeight: CGFloat = 1 + 1 + 1.04
            let unit = (geo.size.width - totalGap) / totalWeight
            HStack(alignment: .top, spacing: gap) {
                TopEventsPanel(appState: appState).frame(width: unit * 1)
                TopCamerasPanel(appState: appState).frame(width: unit * 1)
                TopLensesPanel(appState: appState).frame(width: unit * 1.04)
            }
        }
        .frame(minHeight: 320)
    }

    // 1 : 1.18
    private var twoColumnRow: some View {
        GeometryReader { geo in
            let gap = AuroraSpacing.gridGap
            let totalWeight: CGFloat = 1 + 1.18
            let unit = (geo.size.width - gap) / totalWeight
            HStack(alignment: .top, spacing: gap) {
                PhotosPerMonthChart(appState: appState).frame(width: unit * 1)
                PhotosPerEventChart(appState: appState).frame(width: unit * 1.18)
            }
        }
        .frame(minHeight: 360)
    }
}
