import SwiftUI

struct SettingsView: View {
    @Bindable var appState: AppState
    @Binding var showLicenseOverlay: Bool

    #if canImport(Sparkle)
    @EnvironmentObject private var updater: SparkleUpdater
    #endif

    @State private var showResetConfirm = false
    @State private var showCopyDataConfirm = false
    @State private var showDeleteEventsConfirm = false
    @State private var showResetDashboardConfirm = false
    @State private var deleteEventsStatus: String?
    @State private var copyDataStatus: String?
    @State private var publishBumpKind = "patch"
    @State private var publishStatus: String?
    @State private var publishProgress: Double?
    @State private var publishProcess: Process?
    @State private var telegramEnabled = false
    @State private var telegramBotToken = ""
    @State private var telegramChatID = ""
    @State private var hasSavedTelegramBotToken = false
    @State private var telegramStatus: String?
    @State private var isSendingTelegramTest = false
    @State private var licenseKey = ""
    @State private var licenseStatus: String?
    @State private var licenseIsActive = LicensingService.isActivated()
    @State private var betaGenExpiryDays = 0
    @State private var betaGenResult: String?
    @State private var betaGenCopied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                topbar
                licenseSection
                importSection
                updateSection
                if AppPaths.isBeta { publishSection }
                if AppPaths.isBeta { betaKeyGenSection }
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

    // MARK: - License

    private var licenseSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            AuroraPanelHeader(title: "License")

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    IconChip(systemName: "key.fill", color: licenseIsActive ? .auroraHealthy : .auroraLive)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(licenseIsActive ? "Activated" : "Not Activated")
                            .font(.manrope(13, weight: .bold))
                            .foregroundStyle(Color.auroraTxt)
                        Text("Enter an activation code to activate Aurora.")
                            .font(.manrope(11, weight: .medium))
                            .foregroundStyle(Color.auroraFaint)
                    }
                    Spacer()
                    if licenseIsActive {
                        Button("Deactivate") {
                            LicensingService.deactivate()
                            licenseIsActive = false
                            licenseStatus = "Deactivated."
                            showLicenseOverlay = true
                        }
                        .buttonStyle(AuroraGhostButtonStyle())
                    }
                }

                if !licenseIsActive {
                    HStack(spacing: 10) {
                        TextField("AURORA-XXXX-XXXX-XXXX", text: $licenseKey)
                            .textFieldStyle(.plain)
                            .font(.manrope(12, weight: .medium))
                            .foregroundStyle(Color.auroraTxt)
                            .padding(8)
                            .background(Color.auroraPanel)
                            .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.small))
                        Button("Activate") {
                            let code = licenseKey.trimmingCharacters(in: .whitespaces)
                            guard !code.isEmpty else { return }
                            if LicensingService.activate(with: code) {
                                licenseIsActive = true
                                licenseStatus = nil
                                licenseKey = ""
                            } else {
                                licenseStatus = "Invalid or expired code."
                            }
                        }
                        .buttonStyle(AuroraGradientButtonStyle(compact: true))
                        .disabled(licenseKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                if let status = licenseStatus {
                    Text(status)
                        .font(.manrope(11, weight: .semibold))
                        .foregroundStyle(status.contains("Invalid") || status.contains("Deactivated") ? .red : .green)
                }
            }
            .padding(.horizontal, 6)
        }
        .auroraStaticCard()
    }

    // MARK: - Beta Key Generator

    private var betaKeyGenSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            AuroraPanelHeader(title: "Key Generator (Beta)")

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    IconChip(systemName: "wand.and.stars", color: .auroraViolet)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Generate Activation Code")
                            .font(.manrope(13, weight: .bold))
                            .foregroundStyle(Color.auroraTxt)
                        Text("Generate a code anyone can use to activate Aurora on their Mac.")
                            .font(.manrope(11, weight: .medium))
                            .foregroundStyle(Color.auroraFaint)
                    }
                }

                if let activation = LicensingService.storedActivation() {
                    HStack(spacing: 8) {
                        Text("UUID: \(activation.uuid)")
                            .font(.manrope(10, weight: .medium))
                            .foregroundStyle(Color.auroraFaint)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(activation.uuid, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 9))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.auroraMuted)
                    }
                }

                HStack(spacing: 10) {
                    Text("Expiry")
                        .font(.manrope(12, weight: .semibold))
                        .foregroundStyle(Color.auroraTxt)
                    ForEach([0, 7, 30, 90, 365], id: \.self) { days in
                        Button(days == 0 ? "None" : "\(days)d") { betaGenExpiryDays = days }
                            .buttonStyle(AuroraGhostButtonStyle(active: betaGenExpiryDays == days))
                    }
                    Spacer()
                    Button("Generate") {
                        let code = LicensingService.generateActivationCode(expiryDays: betaGenExpiryDays)
                        betaGenResult = code
                        betaGenCopied = false
                    }
                    .buttonStyle(AuroraGradientButtonStyle(compact: true))
                    .disabled(!LicensingService.keyPairExists())
                }

                if !LicensingService.keyPairExists() {
                    Text("No key pair found. Run: python3 scripts/generate-license-key.py --gen-key")
                        .font(.manrope(11, weight: .semibold))
                        .foregroundStyle(.orange)
                }

                if let result = betaGenResult {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(result)
                                .font(.manrope(10, weight: .medium))
                                .foregroundStyle(Color.auroraTxt)
                                .lineLimit(3)
                                .textSelection(.enabled)
                            Spacer()
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(result, forType: .string)
                                betaGenCopied = true
                            }
                            .buttonStyle(AuroraGhostButtonStyle())
                        }
                        if betaGenCopied {
                            Text("Copied to clipboard!")
                                .font(.manrope(11, weight: .semibold))
                                .foregroundStyle(.green)
                        }
                    }
                }
            }
            .padding(.horizontal, 6)
        }
        .auroraStaticCard()
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
                        .disabled(publishProcess != nil)
                }

                if let publishProgress {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(publishStatus ?? "")
                                .font(.manrope(11, weight: .semibold))
                                .foregroundStyle(Color.auroraMuted)
                            Spacer()
                            Text("\(Int(publishProgress * 100))%")
                                .font(.manrope(11, weight: .bold))
                                .foregroundStyle(Color.auroraCyan)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.auroraStroke.opacity(0.3))
                                    .frame(height: 5)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.auroraCyan)
                                    .frame(width: geo.size.width * publishProgress, height: 5)
                                    .animation(.easeInOut(duration: 0.3), value: publishProgress)
                            }
                        }
                        .frame(height: 5)
                    }
                } else if let publishStatus {
                    Text(publishStatus)
                        .font(.manrope(11, weight: .semibold))
                        .foregroundStyle(publishStatus.contains("Success") ? .green : Color.auroraMuted)
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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path, "--\(publishBumpKind)"]
        process.currentDirectoryURL = scriptURL.deletingLastPathComponent()
        var env = ProcessInfo.processInfo.environment
        let extraPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        let currentPath = env["PATH"] ?? ""
        env["PATH"] = (extraPaths + [currentPath]).joined(separator: ":")
        process.environment = env
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        publishProcess = process
        publishProgress = 0
        publishStatus = "Preparing…"

        let q = DispatchQueue(label: "publish-read")
        var outBuf = ""
        var errBuf = ""

        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let chunk = String(data: data, encoding: .utf8) {
                q.async {
                    outBuf += chunk
                    let lines = outBuf.components(separatedBy: "\n")
                    outBuf = lines.last ?? ""
                    for line in lines.dropLast() {
                        DispatchQueue.main.async {
                            self.updatePublishProgress(line)
                        }
                    }
                }
            }
        }

        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let chunk = String(data: data, encoding: .utf8) {
                q.async {
                    errBuf += chunk
                    let lines = errBuf.components(separatedBy: "\n")
                    errBuf = lines.last ?? ""
                    for line in lines.dropLast() {
                        if line.lowercased().contains("error") {
                            DispatchQueue.main.async {
                                self.updatePublishProgress("error: " + line)
                            }
                        }
                    }
                }
            }
        }

        process.terminationHandler = { proc in
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async {
                self.publishProcess = nil
                if proc.terminationStatus == 0 {
                    self.publishProgress = 1
                    self.publishStatus = "Success. Sent to production!"
                } else {
                    self.publishProgress = nil
                    self.publishStatus = "Failed (exit \(proc.terminationStatus)). Check Console.app."
                }
            }
        }

        do {
            try process.run()
        } catch {
            publishProcess = nil
            publishProgress = nil
            publishStatus = "Failed to run: \(error.localizedDescription)"
        }
    }

    private func updatePublishProgress(_ line: String) {
        let l = line.lowercased()
        if l.contains("error:") {
            publishProgress = nil
            publishStatus = "Error: \(line.replacingOccurrences(of: "error: ", with: ""))"
        } else if l.contains("publishing aurora") {
            publishProgress = 0.1
            publishStatus = "Bumping version…"
        } else if l.contains("archiving release") {
            publishProgress = 0.25
            publishStatus = "Archiving…"
        } else if l.contains("adhoc signing") {
            publishProgress = 0.45
            publishStatus = "Signing…"
        } else if l.contains("building dmg") {
            publishProgress = 0.6
            publishStatus = "Building DMG…"
        } else if l.contains("signing dmg") || l.contains("sign_update") {
            publishProgress = 0.7
            publishStatus = "Signing DMG…"
        } else if l.contains("uploading to github") {
            publishProgress = 0.8
            publishStatus = "Uploading to GitHub…"
        } else if l.contains("✅ published") {
            publishProgress = 1.0
            publishStatus = "Success. Sent to production!"
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
                if AppPaths.isBeta {
                    HStack(spacing: 12) {
                        IconChip(systemName: "doc.on.doc.fill", color: .auroraCyan)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Copy Data from Production")
                                .font(.manrope(13, weight: .bold))
                                .foregroundStyle(Color.auroraTxt)
                            Text("Copies events, stats and banners from the Production app so you can work with real data.")
                                .font(.manrope(11, weight: .medium))
                                .foregroundStyle(Color.auroraFaint)
                        }
                        Spacer()
                        Button("Copy") { showCopyDataConfirm = true }
                            .buttonStyle(AuroraGhostButtonStyle())
                    }
                    if let copyDataStatus {
                        Text(copyDataStatus)
                            .font(.manrope(11, weight: .semibold))
                            .foregroundStyle(copyDataStatus.contains("Done") ? .green : Color.auroraMuted)
                    }
                }

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

                if AppPaths.isBeta {
                    HStack(spacing: 12) {
                        IconChip(systemName: "trash.circle.fill", color: .auroraLive)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Delete All Events")
                                .font(.manrope(13, weight: .bold))
                                .foregroundStyle(Color.auroraTxt)
                            Text("Removes all events, finalized snapshots, banners and stats cache.")
                                .font(.manrope(11, weight: .medium))
                                .foregroundStyle(Color.auroraFaint)
                        }
                        Spacer()
                        Button("Delete") { showDeleteEventsConfirm = true }
                            .buttonStyle(AuroraGhostButtonStyle())
                    }
                    if let deleteEventsStatus {
                        Text(deleteEventsStatus)
                            .font(.manrope(11, weight: .semibold))
                            .foregroundStyle(deleteEventsStatus.contains("Done") ? .green : Color.auroraMuted)
                    }

                    HStack(spacing: 12) {
                        IconChip(systemName: "arrow.counterclockwise.circle.fill", color: .auroraGold)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Reset Dashboard")
                                .font(.manrope(13, weight: .bold))
                                .foregroundStyle(Color.auroraTxt)
                            Text("Factory reset — clears everything: events, stats, history, banners, settings. App returns to initial state.")
                                .font(.manrope(11, weight: .medium))
                                .foregroundStyle(Color.auroraFaint)
                        }
                        Spacer()
                        Button("Reset All") { showResetDashboardConfirm = true }
                            .buttonStyle(AuroraGhostButtonStyle())
                    }
                }
            }
            .padding(.horizontal, 6)
        }
        .auroraStaticCard()
        .alert("Copy Production Data?", isPresented: $showCopyDataConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Copy", role: .destructive) { copyProductionData() }
        } message: {
            Text("This will overwrite current Beta data with Production data.")
        }
        .alert("Delete All Events?", isPresented: $showDeleteEventsConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { deleteAllEvents() }
        } message: {
            Text("This will permanently remove all events, banners, finalized snapshots and stats cache. This cannot be undone.")
        }
        .alert("Factory Reset?", isPresented: $showResetDashboardConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Reset Everything", role: .destructive) { resetDashboard() }
        } message: {
            Text("This will erase ALL data: events, stats, history, banners, import settings and logs. The app will be like new. This cannot be undone.")
        }
    }

    private func copyProductionData() {
        let fm = FileManager.default
        let prodRoot: URL = {
            let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            return appSupport.appendingPathComponent("commanderonev2", isDirectory: true)
        }()
        let betaRoot = AppPaths.applicationSupportRoot

        let itemsToCopy = [
            "finalized_events.json",
            "totalStats.json",
            "system.log.jsonl"
        ]
        let dirsToCopy = [
            "event_stats_cache",
            "event_banners"
        ]

        // Copy importHistory from production UserDefaults
        if let prodDefaults = UserDefaults(suiteName: "errormedia.commanderonev2"),
           let historyData = prodDefaults.data(forKey: "importHistory") {
            UserDefaults.standard.set(historyData, forKey: "importHistory")
        }

        var errors: [String] = []

        for item in itemsToCopy {
            let src = prodRoot.appendingPathComponent(item)
            let dst = betaRoot.appendingPathComponent(item)
            do {
                if fm.fileExists(atPath: dst.path) {
                    try fm.removeItem(at: dst)
                }
                try fm.copyItem(at: src, to: dst)
            } catch {
                errors.append(item)
            }
        }

        for dir in dirsToCopy {
            let src = prodRoot.appendingPathComponent(dir)
            let dst = betaRoot.appendingPathComponent(dir)
            do {
                if fm.fileExists(atPath: dst.path) {
                    try fm.removeItem(at: dst)
                }
                try fm.copyItem(at: src, to: dst)
            } catch {
                errors.append(dir)
            }
        }

        if errors.isEmpty {
            // Reload in-memory data from the copied files
            appState.importHistory = ImportHistoryStorage.load()
            appState.totalStatsReport = StatsStorage.load()
            appState.statsReport = StatsStorage.loadLastImport()
            appState.finalizedEvents = FinalizedEventsStore.loadAll()
            copyDataStatus = "Done — data loaded."
        } else {
            copyDataStatus = "Copied with errors: \(errors.joined(separator: ", "))"
        }
    }

    private func deleteAllEvents() {
        let fm = FileManager.default
        let root = AppPaths.applicationSupportRoot

        // 1. Clear in-memory event arrays in AppState
        appState.eventFolderBookmarks = []
        appState.eventFolderDisplayNames = []
        appState.eventFolderManualDates = []
        appState.eventFolderPeakRawCounts = []
        appState.eventFolderCachedCounts = []
        appState.eventFolderCachedJPGCounts = []
        appState.eventFolderCachedPaths = []
        appState.eventFolderPreviousCachedPaths = []
        appState.eventFolderBannerImagePaths = []
        appState.eventFolderBannerOffsets = []
        appState.eventFolderOrder = []
        appState.eventFolderFinalizedEventID = []
        appState.finalizedEvents = []
        appState.activeEventFolderIndex = -1

        // 2. Delete files on disk
        let filesToDelete = [
            "finalized_events.json"
        ]
        let dirsToDelete = [
            "event_stats_cache",
            "event_banners"
        ]

        for file in filesToDelete {
            let url = root.appendingPathComponent(file)
            try? fm.removeItem(at: url)
        }
        for dir in dirsToDelete {
            let url = root.appendingPathComponent(dir)
            try? fm.removeItem(at: url)
        }

        deleteEventsStatus = "Done — all events deleted."
    }

    private func resetDashboard() {
        let fm = FileManager.default
        let root = AppPaths.applicationSupportRoot
        let ud = UserDefaults.standard

        // 1. Clear all event arrays in memory
        appState.eventFolderBookmarks = []
        appState.eventFolderDisplayNames = []
        appState.eventFolderManualDates = []
        appState.eventFolderPeakRawCounts = []
        appState.eventFolderCachedCounts = []
        appState.eventFolderCachedJPGCounts = []
        appState.eventFolderCachedPaths = []
        appState.eventFolderPreviousCachedPaths = []
        appState.eventFolderBannerImagePaths = []
        appState.eventFolderBannerOffsets = []
        appState.eventFolderOrder = []
        appState.eventFolderFinalizedEventID = []
        appState.finalizedEvents = []
        appState.activeEventFolderIndex = -1

        // 2. Clear in-memory stats
        appState.totalStatsReport = nil
        appState.statsReport = nil
        appState.lastImportReport = nil
        appState.importHistory = []

        // 3. Reset import settings to defaults
        appState.destinationURL = nil
        appState.importMode = .copy
        appState.autoImport = false
        appState.autoEject = true
        appState.renameOnImport = false
        appState.renameTemplate = RenameTemplateRenderer.defaultTemplate

        // 4. Delete all files on disk
        let filesToDelete = [
            "finalized_events.json",
            "totalStats.json",
            "lastImportStats.json",
            "system.log.jsonl"
        ]
        let dirsToDelete = [
            "event_stats_cache",
            "event_banners"
        ]

        for file in filesToDelete {
            try? fm.removeItem(at: root.appendingPathComponent(file))
        }
        for dir in dirsToDelete {
            try? fm.removeItem(at: root.appendingPathComponent(dir))
        }

        // 5. Clear all UserDefaults keys
        let keysToRemove = [
            "destinationBookmark",
            "activeEventFolderIndex",
            "autoImport",
            "autoEject",
            "importMode",
            "renameOnImport",
            "renameTemplate",
            "eventFolderBookmarksData",
            "eventFolderDisplayNamesData",
            "eventFolderManualDatesData",
            "eventFolderPeakRawCountsData",
            "eventFolderCachedCountsData",
            "eventFolderCachedJPGCountsData",
            "eventFolderCachedPathsData",
            "eventFolderPreviousCachedPathsData",
            "eventFolderBannerImagePathsData",
            "eventFolderBannerOffsetsData",
            "eventFolderFinalizedEventIDData",
            "eventFolderOrderData",
            "eventSidebarNodesData",
            "com.commander.totalStats",
            "com.commander.lastImportStats",
            "errormedia.aurora.telegram.isEnabled",
            "errormedia.aurora.telegram.chatID",
            "errormedia.aurora.telegram.hasSavedToken",
            "DailyImportSummary.sentDays",
            "DailyImportSummary.entries",
            "SecurityBookmark.bookmarks",
            "importHistory"
        ]
        for key in keysToRemove {
            ud.removeObject(forKey: key)
        }

        // 6. Clear Keychain (license kept — user stays activated)
        // Licensing key is preserved intentionally.

        // 7. Clear event stats cache directory
        try? fm.removeItem(at: AppPaths.subdirectory("event_stats_cache"))

        // 8. Log
        appState.log("Dashboard factory reset — all data cleared", level: .warning)
    }
}
