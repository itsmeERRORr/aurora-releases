import SwiftUI

struct StatsView: View {
    @Bindable var appState: AppState
    let statsReport: StatsReport?
    let totalStatsReport: StatsReport?

    @State private var selectedStatsTab: StatsTab = .lastImport
    @State private var showResetAlert = false

    enum StatsTab {
        case lastImport
        case total
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(Color.primaryPurple)
                Text("Import Statistics")
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                Spacer()
                if let report = statsReport {
                    Text("\(report.totalFilesAnalyzed) files analyzed")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }

                if selectedStatsTab == .total && totalStatsReport != nil {
                    Button {
                        showResetAlert = true
                    } label: {
                        Label("Reset Total", systemImage: "trash")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.bgMedium)

            Divider()

            // Tab selector
            Picker("Stats Type", selection: $selectedStatsTab) {
                Text("Last Import").tag(StatsTab.lastImport)
                Text("Total").tag(StatsTab.total)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.bgMedium)

            Divider()

            if let report = (selectedStatsTab == .lastImport ? statsReport : totalStatsReport) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Average Settings
                        if report.avgISO != nil || report.avgAperture != nil || report.avgFocalLength != nil {
                            statsSection("Average Settings", icon: "chart.line.uptrend.xyaxis") {
                                VStack(alignment: .leading, spacing: 8) {
                                    if let iso = report.avgISO {
                                        HStack {
                                            Image(systemName: "light.max")
                                            Text("ISO avg:")
                                            Spacer()
                                            Text(String(format: "%.0f", iso))
                                                .font(.system(.body, design: .monospaced))
                                                .fontWeight(.semibold)
                                        }
                                    }
                                    if let aperture = report.avgAperture {
                                        HStack {
                                            Image(systemName: "circle.dotted")
                                            Text("Aperture avg:")
                                            Spacer()
                                            Text(String(format: "f/%.1f", aperture))
                                                .font(.system(.body, design: .monospaced))
                                                .fontWeight(.semibold)
                                        }
                                    }
                                    if let focal = report.avgFocalLength {
                                        HStack {
                                            Image(systemName: "viewfinder")
                                            Text("Focal Length avg:")
                                            Spacer()
                                            Text(String(format: "%.0f mm", focal))
                                                .font(.system(.body, design: .monospaced))
                                                .fontWeight(.semibold)
                                        }
                                    }
                                }
                            }
                        }

                        // Top Lenses
                        if !report.topLenses.isEmpty {
                            statsSection("Top Lenses", icon: "camera.aperture") {
                                ForEach(report.topLenses) { lens in
                                    HStack {
                                        Text(lens.medal)
                                        Text(lens.fullName)
                                            .fontWeight(lens.rank == 1 ? .bold : .regular)
                                        Spacer()
                                        Text("\(lens.count) shots")
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }

                        // Most Used Camera
                        if let camera = report.mostUsedCamera {
                            statsSection("Most Used Camera", icon: "camera.fill") {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(camera.fullName)
                                            .font(.title3.bold())
                                        Text("\(camera.count) photos")
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "camera.fill")
                                        .font(.title)
                                        .foregroundStyle(.blue)
                                }
                            }
                        }

                        // Shutter Speeds
                        if !report.shutterSpeeds.isEmpty {
                            statsSection("Top Shutter Speeds", icon: "timer") {
                                ForEach(report.shutterSpeeds) { shutter in
                                    HStack {
                                        Text(shutter.fractionString)
                                            .font(.system(.body, design: .monospaced))
                                        Spacer()
                                        Text("\(shutter.count) shots")
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                    }
                    .padding(16)
                }
                .background(Color.bgDark)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.textTertiary)
                    Text("No stats yet")
                        .font(.title3)
                        .foregroundStyle(Color.textSecondary)
                    Text("Stats will appear after the first import")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.bgDark)
            }
        }
        .alert("Reset Total Stats?", isPresented: $showResetAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                resetTotalStats()
            }
        } message: {
            Text("This will permanently delete all accumulated statistics. This action cannot be undone.")
        }
    }

    private func resetTotalStats() {
        appState.totalStatsReport = nil
        StatsStorage.clear()
        appState.log("Total stats have been reset")
    }

    @ViewBuilder
    private func statsSection<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline.bold())
                .foregroundStyle(Color.textSecondary)
            content()
                .foregroundColor(.textPrimary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.glassBase)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.glassBorder, lineWidth: 1)
        )
    }
}
