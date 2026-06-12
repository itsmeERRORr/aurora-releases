import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var appState: AppState

    @State private var showResetConfirm = false
    @State private var updateStatus: String?
    @State private var hasLocalUpdate = false
    @State private var telegramEnabled = false
    @State private var telegramBotToken = ""
    @State private var telegramChatID = ""
    @State private var hasSavedTelegramBotToken = false
    @State private var telegramStatus: String?
    @State private var isSendingTelegramTest = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                topbar
                importSection
                lightroomSection
                updateSection
                dataSection
                telegramSection
            }
            .padding(.horizontal, AuroraSpacing.mainPaddingH)
            .padding(.vertical, AuroraSpacing.mainPaddingV)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            refreshLocalUpdateAvailability()
            loadTelegramSettings()
        }
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

    // MARK: - Lightroom

    private var lightroomSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            AuroraPanelHeader(title: "Lightroom Integration")

            VStack(alignment: .leading, spacing: 14) {
                toggleRow(
                    label: "Request Lightroom sync after import",
                    help: "Creates a pending sync request for the Aurora Sync Lightroom Classic plugin.",
                    binding: $appState.lightroomSyncEnabled
                )
                toggleRow(
                    label: "Open Lightroom Classic after import",
                    help: "Opens Lightroom Classic after Aurora writes the sync request.",
                    binding: $appState.lightroomOpenAfterImport
                )

                HStack(spacing: 12) {
                    IconChip(systemName: "camera.viewfinder", color: .auroraViolet)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Lightroom Classic app")
                            .font(.manrope(13, weight: .bold))
                            .foregroundStyle(Color.auroraTxt)
                        Text(lightroomAppLabel)
                            .font(.manrope(11, weight: .medium))
                            .foregroundStyle(Color.auroraFaint)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button("Choose…", action: chooseLightroomApp)
                        .buttonStyle(AuroraGhostButtonStyle())
                    if !appState.lightroomAppPath.isEmpty {
                        Button("Clear") { appState.lightroomAppPath = "" }
                            .buttonStyle(AuroraGhostButtonStyle())
                    }
                }
            }
            .padding(.horizontal, 6)
        }
        .auroraStaticCard()
    }

    private var lightroomAppLabel: String {
        if !appState.lightroomAppPath.isEmpty { return appState.lightroomAppPath }
        if let defaultURL = LightroomSyncService.defaultLightroomURL() {
            return "Auto-detected: \(defaultURL.path)"
        }
        return "No app selected. Aurora will try the default Lightroom Classic paths."
    }

    private func chooseLightroomApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.message = "Choose Lightroom Classic.app"
        panel.prompt = "Choose"

        if panel.runModal() == .OK, let url = panel.url {
            appState.lightroomAppPath = url.path
        }
    }

    // MARK: - Telegram

    private var telegramSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            AuroraPanelHeader(title: "Telegram Notification")

            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: $telegramEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Daily summary")
                            .font(.manrope(13, weight: .bold))
                            .foregroundStyle(Color.auroraTxt)
                        Text("Send a Telegram summary at 22:00 when Aurora imported photos that day.")
                            .font(.manrope(11, weight: .medium))
                            .foregroundStyle(Color.auroraFaint)
                    }
                }
                .toggleStyle(.switch)
                .tint(Color.auroraCyan)
                .onChange(of: telegramEnabled) { _, _ in saveTelegramSettings(showSuccess: false) }

                if telegramEnabled {
                    VStack(alignment: .leading, spacing: 10) {
                        settingsField(label: "Bot Token") {
                            SecureField(hasSavedTelegramBotToken ? "Saved token — leave blank to keep it" : "123456789:ABCDEF...", text: $telegramBotToken)
                        }
                        settingsField(label: "Chat ID") {
                            TextField("123456789", text: $telegramChatID)
                        }

                        HStack(spacing: 10) {
                            Button("Save Data", action: { saveTelegramSettings(showSuccess: true) })
                                .buttonStyle(AuroraGradientButtonStyle(compact: true))
                            Button(isSendingTelegramTest ? "Sending…" : "Send Test Message", action: sendTelegramTestMessage)
                                .buttonStyle(AuroraGhostButtonStyle())
                                .disabled(isSendingTelegramTest || !currentTelegramSettings.canUseSavedToken)
                                .opacity(isSendingTelegramTest || !currentTelegramSettings.canUseSavedToken ? 0.45 : 1)
                            if let telegramStatus {
                                Text(telegramStatus)
                                    .font(.manrope(11, weight: .semibold))
                                    .foregroundStyle(Color.auroraMuted)
                            }
                            Spacer()
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, 6)
        }
        .auroraStaticCard()
        .animation(.easeOut(duration: 0.16), value: telegramEnabled)
    }

    private func settingsField<Field: View>(label: String, @ViewBuilder field: () -> Field) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.manrope(11, weight: .bold))
                .foregroundStyle(Color.auroraFaint)
            field()
                .textFieldStyle(.plain)
                .font(.manrope(12, weight: .semibold))
                .foregroundStyle(Color.auroraTxt)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(
                    RoundedRectangle(cornerRadius: AuroraRadius.small, style: .continuous)
                        .fill(Color.auroraPanel2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AuroraRadius.small, style: .continuous)
                        .strokeBorder(Color.auroraStroke, lineWidth: 1)
                )
        }
    }

    private func loadTelegramSettings() {
        let settings = TelegramNotificationSettingsStore.load(includeToken: false)
        telegramChatID = settings.chatID
        telegramBotToken = ""
        hasSavedTelegramBotToken = settings.hasSavedBotToken
        telegramEnabled = settings.isEnabled
        telegramStatus = nil
    }

    private var currentTelegramSettings: TelegramNotificationSettings {
        TelegramNotificationSettings(
            isEnabled: telegramEnabled,
            chatID: telegramChatID,
            botToken: telegramBotToken,
            hasSavedBotToken: hasSavedTelegramBotToken
        )
    }

    private func saveTelegramSettings(showSuccess: Bool) {
        let settings = currentTelegramSettings
        TelegramNotificationSettingsStore.save(settings)

        if !telegramEnabled {
            telegramStatus = showSuccess ? "Disabled" : nil
        } else if !settings.canUseSavedToken {
            telegramStatus = "Add Bot Token and Chat ID to enable summaries."
        } else if showSuccess {
            hasSavedTelegramBotToken = true
            telegramBotToken = ""
            telegramStatus = "Saved."
        }
    }

    private func sendTelegramTestMessage() {
        var settings = currentTelegramSettings
        TelegramNotificationSettingsStore.save(settings)
        if settings.botToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, settings.hasSavedBotToken {
            settings = TelegramNotificationSettingsStore.load(includeToken: true)
        }
        guard settings.isConfigured else {
            telegramStatus = "Add Bot Token and Chat ID before testing."
            return
        }

        isSendingTelegramTest = true
        telegramStatus = "Sending test message…"
        Task {
            do {
                try await TelegramDailySummaryService.sendTestMessage(settings: settings)
                await MainActor.run {
                    isSendingTelegramTest = false
                    telegramStatus = "Test message sent."
                }
            } catch {
                await MainActor.run {
                    isSendingTelegramTest = false
                    telegramStatus = "Test failed: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Update

    @ViewBuilder
    private var updateSection: some View {
        if hasLocalUpdate {
            VStack(alignment: .leading, spacing: 6) {
                AuroraPanelHeader(title: "Update")

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        IconChip(systemName: "arrow.down.app.fill", color: .auroraCyan)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Update Now")
                                .font(.manrope(13, weight: .bold))
                                .foregroundStyle(Color.auroraTxt)
                            Text("Builds the latest local Xcode project, replaces this app, and relaunches it.")
                                .font(.manrope(11, weight: .medium))
                                .foregroundStyle(Color.auroraFaint)
                        }
                        Spacer()
                        Button("Update Now", action: launchLocalUpdate)
                            .buttonStyle(AuroraGradientButtonStyle(compact: true))
                    }

                    if let updateStatus {
                        Text(updateStatus)
                            .font(.manrope(11, weight: .semibold))
                            .foregroundStyle(Color.auroraMuted)
                    }
                }
                .padding(.horizontal, 6)
            }
            .auroraStaticCard()
        }
    }

    private func launchLocalUpdate() {
        guard let scriptURL = localUpdaterScriptURL() else {
            updateStatus = "Updater script not found next to the Commanderv2 project folder."
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [scriptURL.path]
        process.currentDirectoryURL = scriptURL.deletingLastPathComponent()

        do {
            try process.run()
            updateStatus = "Updater launched. Aurora will close and reopen when the build finishes."
            appState.log("Local updater launched")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                NSApp.terminate(nil)
            }
        } catch {
            updateStatus = "Could not launch updater: \(error.localizedDescription)"
            appState.log("Could not launch updater: \(error.localizedDescription)", level: .error)
        }
    }

    private func refreshLocalUpdateAvailability() {
        guard let scriptURL = localUpdaterScriptURL() else {
            hasLocalUpdate = false
            return
        }

        let projectURL = scriptURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let rootURL = projectURL.deletingLastPathComponent()
        let installedAppURL = rootURL
            .appendingPathComponent("JoaoPhotos")
            .appendingPathComponent("Aurora.app")
        let legacyInstalledAppURL = rootURL
            .appendingPathComponent("JoaoPhotos")
            .appendingPathComponent("JoaoPhotos.app")

        guard let projectDate = latestProjectModificationDate(in: projectURL),
              let appDate = latestModificationDate(in: installedAppURL) ?? latestModificationDate(in: legacyInstalledAppURL) else {
            hasLocalUpdate = false
            return
        }

        hasLocalUpdate = projectDate.timeIntervalSince(appDate) > 1
    }

    private func latestProjectModificationDate(in projectURL: URL) -> Date? {
        let fm = FileManager.default
        let includedExtensions: Set<String> = [
            "swift", "plist", "pbxproj", "entitlements", "json", "xcassets", "icns", "sh"
        ]
        var latest: Date?

        guard let enumerator = fm.enumerator(
            at: projectURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return nil }

        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if name == ".git" || name == ".build" || name == "DerivedData" {
                enumerator.skipDescendants()
                continue
            }

            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey])
            if values?.isDirectory == true, url.pathExtension != "xcassets" { continue }
            let ext = url.pathExtension.lowercased()
            guard includedExtensions.contains(ext) else { continue }
            guard let date = values?.contentModificationDate else { continue }
            if latest == nil || date > latest! { latest = date }
        }

        return latest
    }

    private func latestModificationDate(in url: URL) -> Date? {
        let fm = FileManager.default
        var latest = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)

        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return latest }

        for case let itemURL as URL in enumerator {
            guard let date = try? itemURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { continue }
            if latest == nil || date > latest! { latest = date }
        }

        return latest
    }

    private func localUpdaterScriptURL() -> URL? {
        let appURL = Bundle.main.bundleURL
        var root = appURL.deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = root.appendingPathComponent("commanderonev2/scripts/update-local-app.sh")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
            root.deleteLastPathComponent()
        }

        let developmentCandidate = URL(fileURLWithPath: "/Users/itsmeerror/Desktop/commanderv2/commanderonev2/scripts/update-local-app.sh")
        if FileManager.default.isExecutableFile(atPath: developmentCandidate.path) {
            return developmentCandidate
        }
        return nil
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
