import SwiftUI
import AppKit

struct SettingsView: View {
    @Bindable var appState: AppState

    @State private var showResetConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                topbar
                importSection
                destinationSection
                dataSection
            }
            .padding(.horizontal, AuroraSpacing.mainPaddingH)
            .padding(.vertical, AuroraSpacing.mainPaddingV)
        }
        .scrollIndicators(.hidden)
        .alert("Reset all stats?", isPresented: $showResetConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                appState.totalStatsReport = nil
                appState.statsReport = nil
                appState.log("Stats reset by user", level: .warning)
            }
        } message: {
            Text("Total stats and last-import stats will be cleared. Import history is preserved.")
        }
    }

    private var topbar: some View {
        HStack(spacing: 14) {
            IconChip(systemName: "gearshape.fill", color: .auroraBlue, size: 36, iconScale: 0.5)
            Text("Settings")
                .font(.auroraTopbarH2)
                .tracking(-0.4)
                .foregroundStyle(Color.auroraTxt)
            Spacer()
        }
        .padding(.bottom, 6)
    }

    // MARK: - Import section

    private var importSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            AuroraPanelHeader(title: "Import")

            VStack(alignment: .leading, spacing: 14) {
                toggleRow(label: "Auto-import",
                          help: "Start the import automatically when a card is detected.",
                          binding: $appState.autoImport)
                toggleRow(label: "Auto-eject",
                          help: "Eject the card once the import finishes.",
                          binding: $appState.autoEject)
                modePicker
            }
            .padding(.horizontal, 6)
        }
        .auroraStaticCard()
    }

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Import mode")
                .font(.manrope(12, weight: .semibold))
                .foregroundStyle(Color.auroraTxt)
            HStack(spacing: 10) {
                ForEach(ImportMode.allCases, id: \.self) { mode in
                    Button {
                        appState.importMode = mode
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 11, weight: .bold))
                            Text(mode.label)
                        }
                    }
                    .buttonStyle(AuroraGhostButtonStyle(active: appState.importMode == mode))
                }
                Text(appState.importMode == .move
                     ? "Files are moved off the card after copying."
                     : "Files stay on the card after copying.")
                    .font(.manrope(11, weight: .medium))
                    .foregroundStyle(Color.auroraFaint)
            }
        }
    }

    private func toggleRow(label: String, help: String, binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.manrope(13, weight: .bold))
                    .foregroundStyle(Color.auroraTxt)
                Text(help)
                    .font(.manrope(11, weight: .medium))
                    .foregroundStyle(Color.auroraFaint)
            }
        }
        .toggleStyle(.switch)
        .tint(Color.auroraCyan)
    }

    // MARK: - Destination

    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            AuroraPanelHeader(title: "Default Destination")

            HStack(spacing: 12) {
                IconChip(systemName: "folder.fill", color: .auroraViolet)
                VStack(alignment: .leading, spacing: 2) {
                    Text(appState.destinationURL?.lastPathComponent ?? "Not set")
                        .font(.manrope(13, weight: .bold))
                        .foregroundStyle(Color.auroraTxt)
                    Text(appState.destinationURL?.path ?? "Choose a folder for imports")
                        .font(.manrope(11, weight: .medium))
                        .foregroundStyle(Color.auroraFaint)
                        .lineLimit(1)
                }
                Spacer()
                Button(action: chooseDestination) {
                    Text("Choose…")
                }
                .buttonStyle(AuroraGhostButtonStyle())
            }
            .padding(.horizontal, 6)
        }
        .auroraStaticCard()
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose the default destination folder"
        panel.prompt = "Select"
        guard panel.runModal() == .OK, let url = panel.url,
              let data = BookmarkManager.saveBookmark(for: url) else { return }
        appState.destinationURL = url
        appState.destinationBookmarkData = data
        appState.log("Destination set to \(url.path)")
    }

    // MARK: - Data

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            AuroraPanelHeader(title: "Data")

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    IconChip(systemName: "trash.fill", color: .auroraLive)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reset stats")
                            .font(.manrope(13, weight: .bold))
                            .foregroundStyle(Color.auroraTxt)
                        Text("Clears Last Import and Total stats. Import history is preserved.")
                            .font(.manrope(11, weight: .medium))
                            .foregroundStyle(Color.auroraFaint)
                    }
                    Spacer()
                    Button("Reset") { showResetConfirm = true }
                        .buttonStyle(AuroraGhostButtonStyle())
                }
            }
            .padding(.horizontal, 6)
        }
        .auroraStaticCard()
    }
}
