import SwiftUI

struct SettingsView: View {
    @Bindable var appState: AppState

    #if canImport(Sparkle)
    @EnvironmentObject private var updater: SparkleUpdater
    #endif

    @State private var showResetConfirm = false
    @State private var publishBumpKind = "patch"
    @State private var publishStatus: String?
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
                updateSection
                if AppPaths.isBeta { publishSection }
                dataSection
                telegramSection
            }
            .padding(.horizontal, AuroraSpacing.mainPaddingH)
            .padding(.vertical, AuroraSpacing.mainPaddingV)
        }
        .scrollIndicators(.hidden)
        .onAppear {
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
        #if canImport(Sparkle) && !DEBUG
        if !AppPaths.isBeta {
            VStack(alignment: .leading, spacing: 6) {
                AuroraPanelHeader(title: "Updates")

                HStack(spacing: 12) {
                    IconChip(systemName: "arrow.down.app.fill", color: .auroraCyan)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Check for Updates")
                            .font(.manrope(13, weight: .bold))
                            .foregroundStyle(Color.auroraTxt)
                        Text("Aurora checks GitHub for a newer version and updates automatically.")
                            .font(.manrope(11, weight: .medium))
                            .foregroundStyle(Color.auroraFaint)
                    }
                    Spacer()
                    Button("Check Now") {
                        updater.checkForUpdates()
                    }
                    .buttonStyle(AuroraGhostButtonStyle())
                    .disabled(!updater.canCheckForUpdates)
                }
                .padding(.horizontal, 6)
            }
            .auroraStaticCard()
        }
        #endif
    }

    // MARK: - Publish (Beta only)

    private var publishSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            AuroraPanelHeader(title: "Publish to Production")

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    IconChip(systemName: "paperplane.fill", color: .auroraViolet)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Release")
                            .font(.manrope(13, weight: .bold))
                            .foregroundStyle(Color.auroraTxt)
                        Text("Bumps the version, archives, signs the DMG and uploads to GitHub Releases. The production app detects the update via Sparkle.")
                            .font(.manrope(11, weight: .medium))
                            .foregroundStyle(Color.auroraFaint)
                    }
                }

                HStack(spacing: 10) {
                    Text("Version bump")
                        .font(.manrope(12, weight: .semibold))
                        .foregroundStyle(Color.auroraTxt)
                    ForEach(["patch", "minor", "major"], id: \.self) { kind in
                        Button(kind.capitalized) { publishBumpKind = kind }
                            .buttonStyle(AuroraGhostButtonStyle(active: publishBumpKind == kind))
                    }
                    Spacer()
                    Button("Publish Now") { launchPublish() }
                        .buttonStyle(AuroraGradientButtonStyle(compact: true))
                }

                if let publishStatus {
                    Text(publishStatus)
                        .font(.manrope(11, weight: .semibold))
                        .foregroundStyle(Color.auroraMuted)
                }
            }
            .padding(.horizontal, 6)
        }
        .auroraStaticCard()
    }

    private func launchPublish() {
        guard let scriptURL = publishScriptURL() else {
            publishStatus = "publish.sh not found. Run manually from scripts/."
            return
        }
        let escaped = scriptURL.path.replacingOccurrences(of: "\"", with: "\\\"")
        let cmd = "cd \"\(scriptURL.deletingLastPathComponent().path)\" && bash \"\(escaped)\" --\(publishBumpKind)"
        let appleScript = "tell application \"Terminal\" to do script \"\(cmd.replacingOccurrences(of: "\"", with: "\\\""))\""
        var error: NSDictionary?
        NSAppleScript(source: appleScript)?.executeAndReturnError(&error)
        if error != nil {
            publishStatus = "Could not open Terminal. Run publish.sh manually."
        } else {
            publishStatus = "Terminal opened — watch the output there."
        }
    }

    private func publishScriptURL() -> URL? {
        let candidate = URL(fileURLWithPath: "/Users/itsmeerror/Desktop/commanderv2/commanderonev2/scripts/publish.sh")
        if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }

        var root = Bundle.main.bundleURL.deletingLastPathComponent()
        for _ in 0..<10 {
            let c = root.appendingPathComponent("commanderonev2/scripts/publish.sh")
            if FileManager.default.isExecutableFile(atPath: c.path) { return c }
            root.deleteLastPathComponent()
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
