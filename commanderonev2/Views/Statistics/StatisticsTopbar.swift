import SwiftUI

struct StatisticsTopbar: View {
    @Binding var mode: StatsMode
    @Bindable var appState: AppState
    @Binding var isComparing: Bool

    @State private var isFilterPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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

            if mode == .total {
                HStack(spacing: 10) {
                    filterByButton
                    compareButton
                }
            }
        }
        .padding(.bottom, 20)
    }

    // MARK: - Compare

    private var compareButton: some View {
        Button {
            isComparing.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isComparing ? "xmark" : "arrow.left.arrow.right")
                    .font(.system(size: 10.5, weight: .bold))
                Text(isComparing ? "Exit Compare" : "Compare")
                    .font(.manrope(12, weight: .semibold))
            }
            .foregroundStyle(isComparing ? Color.auroraTxt : Color.auroraMuted)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(isComparing ? Color.auroraPanel2 : Color.clear)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(isComparing ? Color.auroraCyan.opacity(0.4) : Color.auroraStroke2, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var activeFilterCount: Int {
        (appState.dashboardTagFilter != nil ? 1 : 0) + (appState.dashboardYearFilter != nil ? 1 : 0)
    }

    private var filterByButton: some View {
        Button {
            isFilterPresented = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 10.5, weight: .bold))
                Text("Filter by")
                    .font(.manrope(12, weight: .semibold))
                if activeFilterCount > 0 {
                    Text("\(activeFilterCount)")
                        .font(.manrope(10, weight: .bold))
                        .foregroundStyle(Color.auroraBg)
                        .padding(.horizontal, 5.5)
                        .padding(.vertical, 1.5)
                        .background(Capsule(style: .continuous).fill(Color.auroraCyan))
                }
            }
            .foregroundStyle(activeFilterCount > 0 ? Color.auroraTxt : Color.auroraMuted)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(activeFilterCount > 0 ? Color.auroraPanel2 : Color.clear)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(activeFilterCount > 0 ? Color.auroraCyan.opacity(0.4) : Color.auroraStroke2, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isFilterPresented, arrowEdge: .bottom) {
            filterPopoverContent
        }
    }

    private var filterPopoverContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Filter by")
                    .font(.manrope(13, weight: .bold))
                    .foregroundStyle(Color.auroraTxt)
                Spacer()
                if activeFilterCount > 0 {
                    Button("Clear") {
                        appState.dashboardTagFilter = nil
                        appState.dashboardYearFilter = nil
                    }
                    .buttonStyle(.plain)
                    .font(.manrope(11.5, weight: .semibold))
                    .foregroundStyle(Color.auroraCyan)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("YEAR")
                    .font(.manrope(10, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(Color.auroraFaint)
                FlowLayout(spacing: 6) {
                    filterChip(label: "All", isSelected: appState.dashboardYearFilter == nil) {
                        appState.dashboardYearFilter = nil
                    }
                    ForEach(appState.availableYears, id: \.self) { year in
                        filterChip(label: String(year), isSelected: appState.dashboardYearFilter == year) {
                            appState.dashboardYearFilter = (appState.dashboardYearFilter == year) ? nil : year
                        }
                    }
                }
            }

            if isComparing {
                Text("Comparing two tags — exit Compare to filter by a single tag instead.")
                    .font(.manrope(11, weight: .medium))
                    .foregroundStyle(Color.auroraFaint)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("TAG")
                        .font(.manrope(10, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(Color.auroraFaint)
                    FlowLayout(spacing: 6) {
                        filterChip(label: "All", isSelected: appState.dashboardTagFilter == nil) {
                            appState.dashboardTagFilter = nil
                        }
                        ForEach(EventTag.allCases) { tag in
                            filterChip(label: tag.rawValue, tint: tag.tint, isSelected: appState.dashboardTagFilter == tag) {
                                appState.dashboardTagFilter = (appState.dashboardTagFilter == tag) ? nil : tag
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 280)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.large, style: .continuous)
                .fill(Color.auroraBg2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AuroraRadius.large, style: .continuous)
                .strokeBorder(Color.auroraStroke2, lineWidth: 1)
        )
    }

    private func filterChip(label: String, tint: Color = .auroraTxt, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.manrope(11.5, weight: .semibold))
                .foregroundStyle(isSelected ? tint : Color.auroraMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? tint.opacity(0.16) : Color.clear)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(isSelected ? tint.opacity(0.5) : Color.auroraStroke2, lineWidth: isSelected ? 1.5 : 1)
                )
        }
        .buttonStyle(.plain)
    }
}
