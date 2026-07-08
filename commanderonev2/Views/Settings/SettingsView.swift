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
    @State private var showMockDataConfirm = false
    @State private var mockDataStatus: String?
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
    @State private var analyticsOptOut = UserDefaults.standard.bool(forKey: "aurora.analyticsOptOut")
    @State private var licenseKey = ""
    @State private var licenseStatus: String?
    @State private var licenseIsActive = LicensingService.isActivated()
    @State private var isActivatingLicense = false
    @State private var showKeysManagement = false
    @State private var showCancelConfirm = false
    @State private var isCancelling = false
    @State private var cancelSuccessMessage: String?
    @State private var isHoveringManageSubscription = false
    @State private var isHoveringCancelSubscription = false

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
        .sheet(isPresented: $showKeysManagement) {
            KeysManagementView()
                .frame(minWidth: 600, minHeight: 500)
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

    // MARK: - Stripe URLs (LIVE)
    private let stripeProMonthlyURL = "https://buy.stripe.com/aFa28kcXN9je92J6dl6J205"      // Pro monthly (5.99€ +VAT/month)
    private let stripeProYearlyURL  = "https://buy.stripe.com/7sY5kwe1R9je4MtatB6J203"      // Pro yearly (59.90€ +VAT/yr)
    private let stripeLifetimeURL   = "https://buy.stripe.com/bJe5kwcXNeDydiZ59h6J204"      // Lifetime (100€ +VAT/1 time-payment)
    private let stripePortalURL     = "https://billing.stripe.com/p/login/aFa28k5vl1QM0wdeJR6J200"      // Customer Portal

    private var licenseSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            AuroraPanelHeader(title: "License")

            VStack(alignment: .leading, spacing: 14) {
                if licenseIsActive {
                    activatedLicenseView
                } else {
                    notActivatedView
                }

                if let status = licenseStatus {
                    Text(status)
                        .font(.manrope(11, weight: .semibold))
                        .foregroundStyle(status.contains("not found") || status.contains("use on") || status.contains("Deactivated") ? .red : .green)
                }
            }
            .padding(.horizontal, 6)
        }
        .auroraStaticCard()
    }

    @ViewBuilder
    private var activatedLicenseView: some View {
        let activation = LicensingService.storedActivation()
        let plan = activation?.plan ?? "pro"
        let email = activation?.customerEmail

        switch plan {
        case "lifetime":
            lifetimePlanRow(email: email)
        case "free":
            freePlanRow(email: email)
        default:
            proPlanRow(activation: activation, email: email)
        }
    }

    private func lifetimePlanRow(email: String?) -> some View {
        HStack(spacing: 12) {
            IconChip(systemName: "infinity", color: .auroraGold, size: 36, iconScale: 0.5)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Lifetime License")
                        .font(.manrope(13, weight: .bold))
                        .foregroundStyle(Color.auroraTxt)
                    planBadge("LIFETIME", color: .auroraGold)
                }
                Text("Full access forever. Thank you for supporting Aurora.")
                    .font(.manrope(11, weight: .medium))
                    .foregroundStyle(Color.auroraFaint)
            }
            Spacer()
            deactivateButton
        }
    }

    private func proPlanRow(activation: LicensingService.StoredActivation?, email: String?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                IconChip(systemName: "key.fill", color: .auroraCyan, size: 36, iconScale: 0.5)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Pro License")
                            .font(.manrope(13, weight: .bold))
                            .foregroundStyle(Color.auroraTxt)
                        planBadge("PRO", color: .auroraCyan)
                    }
                    HStack(spacing: 4) {
                        Text("Active")
                            .font(.manrope(11, weight: .medium))
                            .foregroundStyle(Color.auroraHealthy)
                        if let exp = activation?.expiresAt {
                            Text("· until \(exp.formatted(date: .abbreviated, time: .omitted))")
                                .font(.manrope(11, weight: .medium))
                                .foregroundStyle(Color.auroraFaint)
                        }
                    }
                }
                Spacer()
                deactivateButton
            }

            // Lifetime upgrade banner
            Button(action: stripeAction(baseURL: stripeLifetimeURL, email: email)) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.auroraGold.opacity(0.15))
                            .frame(width: 36, height: 36)
                        Image(systemName: "infinity")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.auroraGold)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Upgrade to Lifetime")
                            .font(.manrope(13, weight: .black))
                            .foregroundStyle(Color.auroraTxt)
                        Text("Pay once. No renewals. Yours forever.")
                            .font(.manrope(11, weight: .medium))
                            .foregroundStyle(Color.auroraFaint)
                    }
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.auroraGold)
                }
                .padding(12)
                .background(Color.auroraGold.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.small))
                .overlay(
                    RoundedRectangle(cornerRadius: AuroraRadius.small)
                        .stroke(Color.auroraGold.opacity(0.35), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            if let msg = cancelSuccessMessage {
                Text(msg)
                    .font(.manrope(11, weight: .semibold))
                    .foregroundStyle(Color.auroraFaint)
            } else {
                HStack(spacing: 16) {
                    Button {
                        openStripeCustomerPortal()
                    } label: {
                        Label("Manage subscription", systemImage: "creditcard")
                            .font(.manrope(11, weight: .semibold))
                            .foregroundStyle(isHoveringManageSubscription ? Color.auroraTxt : Color.auroraMuted)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color.auroraMuted.opacity(isHoveringManageSubscription ? 0.14 : 0))
                            )
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        withAnimation(.easeOut(duration: 0.15)) {
                            isHoveringManageSubscription = hovering
                        }
                    }

                    Button {
                        showCancelConfirm = true
                    } label: {
                        if isCancelling {
                            Label("Cancelling…", systemImage: "hourglass")
                                .font(.manrope(11, weight: .semibold))
                                .foregroundStyle(Color.auroraMuted)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                        } else {
                            Label("Cancel subscription", systemImage: "xmark.circle")
                                .font(.manrope(11, weight: .semibold))
                                .foregroundStyle(isHoveringCancelSubscription ? Color.auroraLive : Color.auroraMuted)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(Color.auroraLive.opacity(isHoveringCancelSubscription ? 0.12 : 0))
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isCancelling)
                    .onHover { hovering in
                        withAnimation(.easeOut(duration: 0.15)) {
                            isHoveringCancelSubscription = hovering
                        }
                    }
                    .confirmationDialog(
                        "Cancel subscription?",
                        isPresented: $showCancelConfirm,
                        titleVisibility: .visible
                    ) {
                        Button("Cancel subscription", role: .destructive) {
                            performCancellation(activation: activation)
                        }
                        Button("Keep subscription", role: .cancel) {}
                    } message: {
                        if let exp = activation?.expiresAt {
                            Text("Are you sure? You'll keep full access until \(exp.formatted(date: .long, time: .omitted)).")
                        } else {
                            Text("Are you sure you want to cancel your Pro subscription?")
                        }
                    }
                }
            }
        }
    }

    /// Opens Stripe's hosted Customer Portal, where the user manages their own
    /// payment method, billing address and invoices — separate from the in-app
    /// "Cancel subscription" flow, which calls our own Edge Function directly.
    private func openStripeCustomerPortal() {
        guard let url = URL(string: stripePortalURL) else { return }
        NSWorkspace.shared.open(url)
    }

    private func performCancellation(activation: LicensingService.StoredActivation?) {
        isCancelling = true
        Task { @MainActor in
            let result = await LicensingService.cancelSubscription()
            isCancelling = false
            switch result {
            case .success(let expiresAt):
                if let exp = expiresAt {
                    cancelSuccessMessage = "Sorry to see you go. You keep full access until \(exp.formatted(date: .long, time: .omitted))."
                } else {
                    cancelSuccessMessage = "Subscription cancelled. You keep access until the end of your current period."
                }
            case .alreadyCancelled:
                cancelSuccessMessage = "Your subscription was already cancelled."
            case .notFound:
                licenseStatus = "License not found on the server."
            case .unauthorized:
                licenseStatus = "Could not verify your identity."
            case .networkError(let msg):
                licenseStatus = msg
            }
        }
    }

    private func freePlanRow(email: String?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                IconChip(systemName: "key.fill", color: .auroraFaint, size: 36, iconScale: 0.5)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Free License")
                            .font(.manrope(13, weight: .bold))
                            .foregroundStyle(Color.auroraTxt)
                        planBadge("FREE", color: .auroraFaint)
                    }
                    Text("Upgrade to unlock all features.")
                        .font(.manrope(11, weight: .medium))
                        .foregroundStyle(Color.auroraFaint)
                }
                Spacer()
                deactivateButton
            }
            upgradeCards(email: email)
        }
    }

    private var notActivatedView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                IconChip(systemName: "key.fill", color: .auroraLive, size: 36, iconScale: 0.5)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Not Activated")
                        .font(.manrope(13, weight: .bold))
                        .foregroundStyle(Color.auroraTxt)
                    Text("Enter your license key or choose a plan below.")
                        .font(.manrope(11, weight: .medium))
                        .foregroundStyle(Color.auroraFaint)
                }
                Spacer()
            }

            HStack(spacing: 10) {
                TextField("AURORA-XXXX-XXXX-XXXX", text: $licenseKey)
                    .textFieldStyle(.plain)
                    .font(.manrope(12, weight: .medium))
                    .foregroundStyle(Color.auroraTxt)
                    .padding(8)
                    .background(Color.auroraPanel)
                    .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.small))
                Button(isActivatingLicense ? "Checking…" : "Activate") {
                    let code = licenseKey.trimmingCharacters(in: .whitespaces)
                    guard !code.isEmpty else { return }
                    isActivatingLicense = true
                    licenseStatus = nil
                    Task { @MainActor in
                        let result = await LicensingService.activate(with: code)
                        isActivatingLicense = false
                        switch result {
                        case .success:
                            appState.refreshLicenseStatus()
                            licenseIsActive = true
                            licenseKey = ""
                        case .notFound:
                            licenseStatus = "License key not found."
                        case .alreadyActivatedOnAnotherMac:
                            licenseStatus = "Key already in use on another Mac."
                        case .inactive(let reason, _):
                            licenseStatus = reason
                        case .networkError(let msg):
                            licenseStatus = msg
                        }
                    }
                }
                .buttonStyle(AuroraGradientButtonStyle(compact: true))
                .disabled(licenseKey.trimmingCharacters(in: .whitespaces).isEmpty || isActivatingLicense)
            }

            upgradeCards(email: nil)
        }
    }

    /// One priced call-to-action on an upgrade card (e.g. "5.99€ +VAT/month" → the
    /// Pro monthly Stripe link). A card can show more than one — Pro shows monthly
    /// and yearly side by side; Lifetime shows its single one-time price.
    private struct UpgradeCTA {
        let label: String
        let baseURL: String
    }

    private func upgradeCards(email: String?) -> some View {
        HStack(spacing: 10) {
            upgradeCard(
                icon: "bolt.fill",
                title: "Pro",
                description: "Monthly or yearly.\nCancel any time.",
                accent: Color.auroraCyan,
                ctas: [
                    UpgradeCTA(label: "5.99€ +VAT/month", baseURL: stripeProMonthlyURL),
                    UpgradeCTA(label: "59.90€ +VAT/yr", baseURL: stripeProYearlyURL),
                ],
                email: email
            )
            upgradeCard(
                icon: "infinity",
                title: "Lifetime",
                description: "Pay once.\nYours forever.",
                accent: Color.auroraGold,
                ctas: [
                    UpgradeCTA(label: "100€ +VAT/1 time-payment", baseURL: stripeLifetimeURL),
                ],
                email: email
            )
        }
    }

    private func upgradeCard(icon: String, title: String, description: String, accent: Color, ctas: [UpgradeCTA], email: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(accent)
                Text(title)
                    .font(.manrope(15, weight: .black))
                    .foregroundStyle(Color.auroraTxt)
                Spacer()
            }
            Text(description)
                .font(.manrope(11, weight: .medium))
                .foregroundStyle(Color.auroraFaint)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)

            HStack(spacing: 6) {
                ForEach(ctas, id: \.label) { cta in
                    Button(action: stripeAction(baseURL: cta.baseURL, email: email)) {
                        Text(cta.label)
                            .font(.manrope(12, weight: .bold))
                            .foregroundStyle(accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .padding(.horizontal, 4)
                            .background(accent.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.small))
        .overlay(
            RoundedRectangle(cornerRadius: AuroraRadius.small)
                .stroke(accent.opacity(0.4), lineWidth: 1)
        )
    }

    // MARK: - Shared components

    @ViewBuilder
    private var deactivateButton: some View {
        if AppPaths.isBeta {
            Button("Deactivate") {
                LicensingService.deactivate()
                appState.refreshLicenseStatus()
                licenseIsActive = false
                licenseStatus = nil
            }
            .buttonStyle(AuroraGhostButtonStyle())
        }
    }

    private func planBadge(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.manrope(9, weight: .black))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }

    private enum StripeButtonStyle { case gradient, ghost }

    @ViewBuilder
    private func stripeButton(label: String, icon: String, baseURL: String, email: String?, style: StripeButtonStyle) -> some View {
        let action = stripeAction(baseURL: baseURL, email: email)
        if style == .gradient {
            Button(action: action) { Label(label, systemImage: icon) }
                .buttonStyle(AuroraGradientButtonStyle(compact: true))
        } else {
            Button(action: action) { Label(label, systemImage: icon) }
                .buttonStyle(AuroraGhostButtonStyle())
        }
    }

    private func stripeAction(baseURL: String, email: String?) -> () -> Void {
        {
            var urlString = baseURL
            let sep = baseURL.contains("?") ? "&" : "?"
            if let email, !email.isEmpty,
               let encoded = email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                urlString += "\(sep)prefilled_email=\(encoded)&client_reference_id=aurora-app"
            } else {
                urlString += "\(sep)client_reference_id=aurora-app"
            }
            if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
        }
    }

    // MARK: - Beta Key Generator

    private var betaKeyGenSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            AuroraPanelHeader(title: "Key Generator (Beta)")

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    IconChip(systemName: "key.fill", color: .auroraHealthy)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Manage Named Keys")
                            .font(.manrope(13, weight: .bold))
                            .foregroundStyle(Color.auroraTxt)
                        Text("Create Supabase licenses for friends or colleagues.")
                            .font(.manrope(11, weight: .medium))
                            .foregroundStyle(Color.auroraFaint)
                    }
                    Spacer()
                    Button("Keys →") {
                        showKeysManagement = true
                    }
                    .buttonStyle(AuroraGradientButtonStyle(compact: true))
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
                toggleRow(label: "Auto-subfolders",
                          help: "Organize imports into Year/Date subfolders automatically (e.g. 2026/2026-06-14).",
                          binding: $appState.autoSubfolders)
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

                HStack(spacing: 12) {
                    IconChip(systemName: "chart.bar.xaxis", color: .auroraFaint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Share anonymous usage stats")
                            .font(.manrope(13, weight: .bold))
                            .foregroundStyle(Color.auroraTxt)
                        Text("Helps improve Aurora. No personal data like names, emails, or event names are collected — only camera models, lenses, and shooting settings.")
                            .font(.manrope(11, weight: .medium))
                            .foregroundStyle(Color.auroraFaint)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { !analyticsOptOut },
                        set: { enabled in
                            analyticsOptOut = !enabled
                            UserDefaults.standard.set(!enabled, forKey: "aurora.analyticsOptOut")
                        }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
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

                    HStack(spacing: 12) {
                        IconChip(systemName: "sparkles", color: .auroraCyan)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Generate Mock Data")
                                .font(.manrope(13, weight: .bold))
                                .foregroundStyle(Color.auroraTxt)
                            Text("Creates football event data, stats and import history for demo/promo purposes.")
                                .font(.manrope(11, weight: .medium))
                                .foregroundStyle(Color.auroraFaint)
                        }
                        Spacer()
                        Button("Generate") { showMockDataConfirm = true }
                            .buttonStyle(AuroraGhostButtonStyle())
                    }
                    if let mockDataStatus {
                        Text(mockDataStatus)
                            .font(.manrope(11, weight: .semibold))
                            .foregroundStyle(mockDataStatus.contains("Done") ? .green : Color.auroraMuted)
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
        .alert("Generate Mock Data?", isPresented: $showMockDataConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Generate") { generateMockData() }
        } message: {
            Text("This will create football event data, stats and import history. Existing data will be replaced.")
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

    // MARK: - Mock Data Generator

    private func generateMockData() {
        let fm = FileManager.default
        let cal = Calendar.current
        let root = AppPaths.applicationSupportRoot

        func makeDate(year: Int, month: Int, day: Int, hour: Int = 14, minute: Int = 30) -> Date {
            var c = DateComponents()
            c.year = year; c.month = month; c.day = day; c.hour = hour; c.minute = minute
            return cal.date(from: c) ?? Date()
        }
        func makePath(_ name: String) -> String {
            root.appendingPathComponent("mock_events/\(name)").path
        }
        func dayKey(_ date: Date) -> String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: date)
        }
        func mockCaptureTimestamps(photoCount: Int, startDate: Date) -> [String: [Double]] {
            let dayCount = photoCount >= 3600 ? 3 : (photoCount >= 1800 ? 2 : 1)
            var remaining = photoCount
            var result: [String: [Double]] = [:]

            for dayOffset in 0..<dayCount {
                let date = cal.date(byAdding: .day, value: dayOffset, to: startDate) ?? startDate
                let daysLeft = max(dayCount - dayOffset, 1)
                let count = dayOffset == dayCount - 1 ? remaining : max(1, remaining / daysLeft)
                remaining -= count

                let dayStart = cal.startOfDay(for: date).timeIntervalSince1970
                let coverageStart = dayStart + Double(10 + dayOffset) * 3600
                let coverageSeconds = Double(5 + (photoCount / 1800) + dayOffset) * 3600
                let spacing = max(1.0, coverageSeconds / Double(max(count, 1)))
                result[dayKey(date)] = (0..<count).map { idx in
                    coverageStart + Double(idx) * spacing
                }
            }
            return result
        }
        func cameraMetadata(
            for cameras: [(make: String, model: String, pct: Double)],
            eventDate: Date,
            eventIndex: Int
        ) -> (maxShutterCounts: [String: Int], lastSeenDates: [String: Date]) {
            var shutterCounts: [String: Int] = [:]
            var lastSeen: [String: Date] = [:]
            for (idx, camera) in cameras.enumerated() {
                let key = "\(camera.make)|\(camera.model)"
                lastSeen[key] = cal.date(byAdding: .hour, value: idx * 2, to: eventDate) ?? eventDate
                if camera.make.lowercased().contains("sony") || camera.make.lowercased().contains("canon") || camera.make.lowercased().contains("nikon") {
                    shutterCounts[key] = 18_000 + eventIndex * 3_750 + idx * 8_500
                }
            }
            return (shutterCounts, lastSeen)
        }

        // MARK: - Events (diverse categories)
        struct MockEvent {
            let name: String
            let photos: Int
            let gigabytes: Double
            let source: String
            let year: Int, month: Int, day: Int
            let cameras: [(make: String, model: String, pct: Double)]
            let lenses: [(make: String, model: String, pct: Double)]
            let searchTerm: String
        }

        let events: [MockEvent] = [
            // Football
            MockEvent(name: "Benfica vs Porto", photos: 1824, gigabytes: 168, source: "CF-AB-256GB",
                      year: 2026, month: 1, day: 15,
                      cameras: [("Sony", "ILCE-9M3", 0.55), ("Sony", "ILCE-7M4", 0.25), ("Canon", "EOS R5", 0.12), ("Nikon", "Z 8", 0.08)],
                      lenses: [("Sony", "FE 400mm F2.8 GM OSS", 0.30), ("Sony", "FE 70-200mm F2.8 GM II", 0.25), ("Sony", "FE 24-70mm F2.8 GM", 0.25), ("Sony", "FE 14mm F1.8 GM", 0.20)],
                      searchTerm: "football+stadium+night+lights"),
            MockEvent(name: "Sporting — Champions League", photos: 2400, gigabytes: 220, source: "CF-AB-256GB",
                      year: 2025, month: 12, day: 10,
                      cameras: [("Sony", "ILCE-9M3", 0.60), ("Sony", "ILCE-1", 0.40)],
                      lenses: [("Sony", "FE 400mm F2.8 GM OSS", 0.35), ("Sony", "FE 70-200mm F2.8 GM II", 0.30), ("Sony", "FE 135mm F1.8 GM", 0.20), ("Sony", "FE 16-35mm F2.8 GM", 0.15)],
                      searchTerm: "soccer+champions+league+goal"),
            MockEvent(name: "World Cup Qualifier", photos: 5200, gigabytes: 84.7, source: "CF-AB-256GB",
                      year: 2025, month: 11, day: 18,
                      cameras: [("Sony", "ILCE-1", 0.50), ("Sony", "ILCE-9M3", 0.35), ("Sony", "ILCE-7RM5", 0.15)],
                      lenses: [("Sony", "FE 600mm F4 GM OSS", 0.28), ("Sony", "FE 400mm F2.8 GM OSS", 0.25), ("Sony", "FE 70-200mm F2.8 GM II", 0.22), ("Sony", "FE 24-70mm F2.8 GM", 0.15), ("Sony", "FE 14mm F1.8 GM", 0.10)],
                      searchTerm: "world+cup+football+celebration"),
            MockEvent(name: "FA Cup Semi-Final", photos: 2800, gigabytes: 45.2, source: "CF-AB-256GB",
                      year: 2025, month: 10, day: 5,
                      cameras: [("Sony", "ILCE-9M3", 0.50), ("Sony", "ILCE-7M4", 0.30), ("Sony", "ILCE-7SM3", 0.20)],
                      lenses: [("Sony", "FE 300mm F2.8 GM OSS", 0.28), ("Sony", "FE 70-200mm F2.8 GM II", 0.25), ("Sony", "FE 24-70mm F2.8 GM", 0.25), ("Sony", "FE 85mm F1.4 GM", 0.22)],
                      searchTerm: "football+cup+match+action"),
            // Music festivals
            MockEvent(name: "NOS Alive — Day 1", photos: 3100, gigabytes: 285, source: "SD-PG-128GB",
                      year: 2026, month: 2, day: 20,
                      cameras: [("Sony", "ILCE-9M3", 0.45), ("Sony", "ILCE-7M4", 0.35), ("Leica", "Q3", 0.20)],
                      lenses: [("Sony", "FE 24-70mm F2.8 GM", 0.35), ("Sony", "FE 70-200mm F2.8 GM II", 0.25), ("Sony", "FE 50mm F1.4 GM", 0.20), ("Sony", "FE 16-35mm F2.8 GM", 0.20)],
                      searchTerm: "music+festival+crowd+stage+lights"),
            MockEvent(name: "MEO Arena — Coldplay", photos: 3800, gigabytes: 350, source: "CF-AB-256GB",
                      year: 2026, month: 5, day: 28,
                      cameras: [("Sony", "ILCE-9M3", 0.50), ("Sony", "ILCE-7M4", 0.30), ("Canon", "EOS R5", 0.20)],
                      lenses: [("Sony", "FE 70-200mm F2.8 GM II", 0.30), ("Sony", "FE 24-70mm F2.8 GM", 0.30), ("Sony", "FE 50mm F1.4 GM", 0.25), ("Canon", "RF 70-200mm F2.8L", 0.15)],
                      searchTerm: "concert+arena+band+performance+stage"),
            MockEvent(name: "Rock in Rio — Main Stage", photos: 4100, gigabytes: 378, source: "CF-AB-256GB",
                      year: 2025, month: 9, day: 22,
                      cameras: [("Sony", "ILCE-9M3", 0.55), ("Sony", "ILCE-1", 0.25), ("Canon", "EOS R5", 0.20)],
                      lenses: [("Sony", "FE 70-200mm F2.8 GM II", 0.30), ("Sony", "FE 24-70mm F2.8 GM", 0.25), ("Sony", "FE 50mm F1.4 GM", 0.20), ("Canon", "RF 50mm F1.2L", 0.15), ("Sony", "FE 16-35mm F2.8 GM", 0.10)],
                      searchTerm: "rock+concert+stage+pyrotechnics+crowd"),
            // Esports
            MockEvent(name: "ESL Pro League Finals", photos: 4200, gigabytes: 390, source: "CF-AB-256GB",
                      year: 2026, month: 4, day: 10,
                      cameras: [("Sony", "ILCE-9M3", 0.50), ("Sony", "ILCE-7M4", 0.30), ("Nikon", "Z 8", 0.20)],
                      lenses: [("Sony", "FE 24-70mm F2.8 GM", 0.35), ("Sony", "FE 70-200mm F2.8 GM II", 0.25), ("Nikon", "Z 70-200mm f/2.8", 0.20), ("Sony", "FE 50mm F1.4 GM", 0.20)],
                      searchTerm: "esports+gaming+tournament+arena+screens"),
            MockEvent(name: "Valorant Champions Tour", photos: 2800, gigabytes: 258, source: "SD-PG-128GB",
                      year: 2025, month: 11, day: 5,
                      cameras: [("Sony", "ILCE-7M4", 0.45), ("Sony", "ILCE-9M3", 0.35), ("Canon", "EOS R5", 0.20)],
                      lenses: [("Sony", "FE 24-70mm F2.8 GM", 0.30), ("Sony", "FE 50mm F1.4 GM", 0.25), ("Canon", "RF 50mm F1.2L", 0.25), ("Sony", "FE 85mm F1.4 GM", 0.20)],
                      searchTerm: "esports+gaming+competition+neon"),
            // Product / commercial
            MockEvent(name: "Watch Shoot — TAG Heuer", photos: 980, gigabytes: 92, source: "CF-AB-256GB",
                      year: 2026, month: 3, day: 5,
                      cameras: [("Sony", "ILCE-7RM5", 0.60), ("Leica", "Q3", 0.40)],
                      lenses: [("Sony", "FE 90mm F2.8 Macro", 0.40), ("Sony", "FE 50mm F1.4 GM", 0.35), ("Leica", "Summilux 28mm", 0.25)],
                      searchTerm: "luxury+watch+product+photography+studio"),
            MockEvent(name: "Studio — Fashion Lookbook", photos: 2200, gigabytes: 203, source: "CF-AB-256GB",
                      year: 2026, month: 6, day: 12,
                      cameras: [("Sony", "ILCE-7RM5", 0.50), ("Canon", "EOS R5", 0.30), ("Sony", "ILCE-7M4", 0.20)],
                      lenses: [("Sony", "FE 85mm F1.4 GM", 0.35), ("Canon", "RF 50mm F1.2L", 0.30), ("Sony", "FE 24-70mm F2.8 GM", 0.20), ("Sony", "FE 135mm F1.8 GM", 0.15)],
                      searchTerm: "fashion+photoshoot+studio+model+lighting"),
            // Wedding / portrait
            MockEvent(name: "Wedding — Ana & Tiago", photos: 5400, gigabytes: 498, source: "CF-AB-256GB",
                      year: 2026, month: 4, day: 25,
                      cameras: [("Sony", "ILCE-9M3", 0.45), ("Sony", "ILCE-7M4", 0.35), ("Canon", "EOS R5", 0.20)],
                      lenses: [("Sony", "FE 70-200mm F2.8 GM II", 0.28), ("Sony", "FE 24-70mm F2.8 GM", 0.25), ("Sony", "FE 85mm F1.4 GM", 0.22), ("Canon", "RF 50mm F1.2L", 0.15), ("Sony", "FE 35mm F1.4 GM", 0.10)],
                      searchTerm: "wedding+couple+romantic+flowers+bouquet"),
            // Nature / bird watching
            MockEvent(name: "Bird Watch — Sintra", photos: 2100, gigabytes: 195, source: "SD-PG-128GB",
                      year: 2026, month: 3, day: 18,
                      cameras: [("Sony", "ILCE-9M3", 0.70), ("Sony", "ILCE-7RM5", 0.30)],
                      lenses: [("Sony", "FE 200-600mm F5.6-6.3 G", 0.50), ("Sony", "FE 100-400mm F4.5-5.6 GM", 0.30), ("Sony", "FE 600mm F4 GM OSS", 0.20)],
                      searchTerm: "bird+wildlife+nature+forest+telephoto"),
            MockEvent(name: "Faro Boat Trip — Dolphins", photos: 1560, gigabytes: 144, source: "SD-PG-128GB",
                      year: 2026, month: 6, day: 8,
                      cameras: [("Sony", "ILCE-9M3", 0.60), ("Sony", "ILCE-7M4", 0.40)],
                      lenses: [("Sony", "FE 100-400mm F4.5-5.6 GM", 0.40), ("Sony", "FE 70-200mm F2.8 GM II", 0.35), ("Sony", "FE 24-70mm F2.8 GM", 0.25)],
                      searchTerm: "dolphins+ocean+sea+boat+blue+water"),
            // Travel / street
            MockEvent(name: "Lisbon Street Photography", photos: 980, gigabytes: 90, source: "SD-PG-128GB",
                      year: 2026, month: 6, day: 14,
                      cameras: [("Leica", "Q3", 0.50), ("Sony", "ILCE-7M4", 0.30), ("Sony", "ILCE-9M3", 0.20)],
                      lenses: [("Leica", "Summilux 28mm", 0.50), ("Sony", "FE 35mm F1.4 GM", 0.30), ("Sony", "FE 50mm F1.4 GM", 0.20)],
                      searchTerm: "lisbon+street+tram+architecture+yellow"),
            MockEvent(name: "Porto — Ribeira District", photos: 1200, gigabytes: 110, source: "SD-PG-128GB",
                      year: 2026, month: 5, day: 3,
                      cameras: [("Sony", "ILCE-7M4", 0.45), ("Leica", "Q3", 0.35), ("Sony", "ILCE-9M3", 0.20)],
                      lenses: [("Sony", "FE 24-70mm F2.8 GM", 0.35), ("Leica", "Summilux 28mm", 0.35), ("Sony", "FE 50mm F1.4 GM", 0.30)],
                      searchTerm: "porto+river+douro+bridge+colorful+houses"),
            // Sport (non-football)
            MockEvent(name: "Maratona de Lisboa", photos: 1680, gigabytes: 155, source: "SD-PG-128GB",
                      year: 2025, month: 10, day: 18,
                      cameras: [("Sony", "ILCE-9M3", 0.55), ("Sony", "ILCE-7M4", 0.30), ("Nikon", "Z 8", 0.15)],
                      lenses: [("Sony", "FE 70-200mm F2.8 GM II", 0.30), ("Sony", "FE 24-70mm F2.8 GM", 0.30), ("Sony", "FE 100-400mm F4.5-5.6 GM", 0.25), ("Nikon", "Z 70-200mm f/2.8", 0.15)],
                      searchTerm: "marathon+running+city+race+athletes"),
            MockEvent(name: "Training Session — Academy", photos: 890, gigabytes: 82, source: "SD-PG-128GB",
                      year: 2026, month: 5, day: 15,
                      cameras: [("Sony", "ILCE-7M4", 0.50), ("Sony", "ILCE-9M3", 0.30), ("Canon", "EOS R5", 0.20)],
                      lenses: [("Sony", "FE 70-200mm F2.8 GM II", 0.35), ("Sony", "FE 24-70mm F2.8 GM", 0.30), ("Canon", "RF 70-200mm F2.8L", 0.20), ("Sony", "FE 50mm F1.4 GM", 0.15)],
                      searchTerm: "football+training+academy+practice+field"),
            // Personal
            MockEvent(name: "Family BBQ — Summer", photos: 420, gigabytes: 38, source: "SD-PG-128GB",
                      year: 2025, month: 8, day: 14,
                      cameras: [("Sony", "ILCE-7M4", 0.60), ("Leica", "Q3", 0.40)],
                      lenses: [("Sony", "FE 24-70mm F2.8 GM", 0.40), ("Leica", "Summilux 28mm", 0.35), ("Sony", "FE 50mm F1.4 GM", 0.25)],
                      searchTerm: "family+bbq+summer+outdoor+garden+food"),
            MockEvent(name: "Sunset — Cascais", photos: 340, gigabytes: 31, source: "SD-PG-128GB",
                      year: 2025, month: 7, day: 6,
                      cameras: [("Sony", "ILCE-7M4", 0.50), ("Leica", "Q3", 0.50)],
                      lenses: [("Sony", "FE 24-70mm F2.8 GM", 0.35), ("Leica", "Summilux 28mm", 0.35), ("Sony", "FE 50mm F1.4 GM", 0.30)],
                      searchTerm: "sunset+beach+cascais+ocean+golden+hour")
        ]

        // MARK: - Build per-event finalized snapshots + import history
        var allImportHistory: [ImportHistoryEntry] = []
        var allFinalizedEvents: [FinalizedEvent] = []

        // Older events (before 2026-05) are finalized; newer ones are active
        let finalizedCutoff = makeDate(year: 2026, month: 5, day: 1)

        for (eventIndex, event) in events.enumerated() {
            let eventDate = makeDate(year: event.year, month: event.month, day: event.day)
            let isFinalized = eventDate < finalizedCutoff

            let eventCameraCounts = event.cameras.reduce(into: [String: Int]()) { $0["\($1.make)|\($1.model)"] = Int(Double(event.photos) * $1.pct) }
            let eventLensCounts = event.lenses.reduce(into: [String: Int]()) { $0["\($1.make)|\($1.model)"] = Int(Double(event.photos) * $1.pct) }

            let topLenses = event.lenses.enumerated().map { i, l in
                StatsReport.LensStat(make: l.make, model: l.model, count: Int(Double(event.photos) * l.pct), rank: i + 1)
            }
            let cameras = event.cameras.map { StatsReport.CameraStat(make: $0.make, model: $0.model, count: Int(Double(event.photos) * $0.pct)) }
            let captureTimestampsByDay = mockCaptureTimestamps(photoCount: event.photos, startDate: eventDate)
            let cameraMeta = cameraMetadata(for: event.cameras, eventDate: eventDate, eventIndex: eventIndex)
            let mainCamera = cameras.max(by: { $0.count < $1.count }).map { camera in
                let key = "\(camera.make)|\(camera.model)"
                return StatsReport.CameraStat(
                    make: camera.make,
                    model: camera.model,
                    count: camera.count,
                    maxShutterCount: cameraMeta.maxShutterCounts[key],
                    lastSeenDate: cameraMeta.lastSeenDates[key]
                )
            }

            let snapshot = StatsReport(
                topLenses: topLenses,
                mostUsedCamera: mainCamera,
                shutterSpeeds: [
                    StatsReport.ShutterStat(rawValue: 1.0/2000.0, count: Int(Double(event.photos) * 0.25)),
                    StatsReport.ShutterStat(rawValue: 1.0/1000.0, count: Int(Double(event.photos) * 0.35)),
                    StatsReport.ShutterStat(rawValue: 1.0/500.0, count: Int(Double(event.photos) * 0.20)),
                    StatsReport.ShutterStat(rawValue: 1.0/250.0, count: Int(Double(event.photos) * 0.12)),
                    StatsReport.ShutterStat(rawValue: 1.0/125.0, count: Int(Double(event.photos) * 0.08))
                ],
                totalFilesAnalyzed: event.photos,
                rawOutput: "[]",
                avgISO: Double.random(in: 400...2400),
                avgAperture: Double.random(in: 2.0...4.0),
                avgFocalLength: Double.random(in: 50...250),
                totalBytes: Int64(event.gigabytes * 1024 * 1024 * 1024),
                totalDuration: Int.random(in: 1800...7200),
                importCount: Int.random(in: 1...3),
                lensCounts: eventLensCounts,
                cameraCounts: eventCameraCounts,
                orientationCounts: ["landscape": Int(Double(event.photos) * 0.55), "portrait": Int(Double(event.photos) * 0.45)],
                captureTimestampsByDay: captureTimestampsByDay,
                cameraMaxShutterCounts: cameraMeta.maxShutterCounts,
                cameraLastSeenDates: cameraMeta.lastSeenDates
            )

            if isFinalized {
                let fe = FinalizedEvent(
                    name: event.name,
                    snapshot: snapshot,
                    totalBytes: Int64(event.gigabytes * 1024 * 1024 * 1024),
                    photoCount: event.photos,
                    firstImportDate: eventDate,
                    lastImportDate: eventDate,
                    finalizedAt: cal.date(byAdding: .day, value: 1, to: eventDate) ?? eventDate,
                    lastKnownPath: makePath(event.name)
                )
                allFinalizedEvents.append(fe)
            }

            // Import history: 1-3 sessions per event
            let sessionCount = Int.random(in: 1...3)
            for s in 0..<sessionCount {
                let sessionDate = s == 2
                    ? (cal.date(byAdding: .day, value: 1, to: eventDate) ?? eventDate)
                    : (cal.date(byAdding: .hour, value: s * 6, to: eventDate) ?? eventDate)
                let fraction = s == 0 ? 0.6 : (s == 1 ? 0.3 : 0.1)
                let sessionFiles = max(Int(Double(event.photos) * fraction), 10)
                let sessionBytes = Int64(Double(sessionFiles) * 20.0 * 1024 * 1024)
                allImportHistory.append(ImportHistoryEntry(
                    date: sessionDate,
                    sourceName: event.source,
                    destinationPath: makePath(event.name),
                    fileCount: sessionFiles,
                    totalBytes: sessionBytes
                ))
            }
        }

        allImportHistory.sort { $0.date > $1.date }

        // MARK: - Sidebar arrays
        let count = events.count
        appState.eventFolderBookmarks = Array(repeating: Data(), count: count)
        appState.eventFolderDisplayNames = events.map { $0.name }
        appState.eventFolderCachedPaths = events.map { makePath($0.name) }
        appState.eventFolderPeakRawCounts = events.map { $0.photos + Int.random(in: 50...300) }
        appState.eventFolderCachedCounts = events.map { $0.photos }
        appState.eventFolderCachedJPGCounts = events.map { Int(Double($0.photos) * Double.random(in: 0.08...0.18)) }
        appState.eventFolderManualDates = events.map { makeDate(year: $0.year, month: $0.month, day: $0.day) }
        appState.eventFolderBannerImagePaths = Array(repeating: "", count: count)
        appState.eventFolderBannerOffsets = Array(repeating: EventBannerOffset(), count: count)
        appState.eventFolderOrder = Array(0..<count)
        appState.eventSidebarNodes = events.indices.map { .event(index: $0) }
        appState.activeEventFolderIndex = 0

        // MARK: - Curated pic IDs per event category
        let picIDs: [Int] = [
            1044,  // football/stadium
            1074,  // football night
            1059,  // sports action
            1060,  // stadium
            1039,  // concert crowd
            1040,  // concert stage
            1041,  // music festival
            118,   // esports/gaming
            1080,  // gaming setup
            250,   // product/watch
            1062,  // fashion studio
            1064,  // wedding
            1015,  // river landscape
            1036,  // ocean/dolphins
            1042,  // street photography
            1043,  // city architecture
            1029,  // running/marathon
            1047,  // training field
            1025,  // outdoor/summer
            1038   // sunset beach
        ]

        // MARK: - Create mock event folders with sample images on disk
        let rawExtensions = ["arw", "cr2", "cr3", "nef", "dng"]
        let imagesPerEvent = 12

        for (i, event) in events.enumerated() {
            let eventDir = URL(fileURLWithPath: makePath(event.name))
            try? fm.createDirectory(at: eventDir, withIntermediateDirectories: true)

            let batchGroup = DispatchGroup()
            for j in 0..<imagesPerEvent {
                batchGroup.enter()
                let picID = (picIDs[i % picIDs.count] + j * 7) % 200 + 10
                let urlString = "https://picsum.photos/id/\(picID)/6000/4000"
                guard let url = URL(string: urlString) else { batchGroup.leave(); continue }

                let task = URLSession.shared.dataTask(with: url) { data, _, _ in
                    defer { batchGroup.leave() }
                    guard let data = data, let img = NSImage(data: data),
                          let tiff = img.tiffRepresentation,
                          let rep = NSBitmapImageRep(data: tiff) else { return }

                    let isRaw = j < (imagesPerEvent * 60 / 100)
                    let ext = isRaw ? rawExtensions[j % rawExtensions.count] : "jpg"
                    let filename = String(format: "IMG_%04d.%@", j + 1, ext)
                    let fileURL = eventDir.appendingPathComponent(filename)

                    if let imgData = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) {
                        try? imgData.write(to: fileURL)
                    }
                }
                task.resume()
            }
            batchGroup.wait()
        }

        // MARK: - Shared EXIF distribution dictionaries
        let isoCounts: [String: Int] = ["100": 800, "200": 1200, "400": 2400, "800": 3100, "1600": 1800, "3200": 900, "6400": 400]
        let apertureCounts: [String: Int] = ["1.4": 600, "2.0": 1400, "2.8": 3200, "4.0": 2100, "5.6": 1500, "8.0": 800, "11": 400, "16": 200]
        let focalCounts: [String: Int] = ["14": 300, "24": 1800, "35": 1500, "50": 2200, "70": 1100, "85": 900, "100": 600, "135": 800, "200": 1200, "400": 1600, "600": 400]

        // MARK: - Pre-populate EventStatsCache for each mock event
        for (i, event) in events.enumerated() {
            let eventPath = makePath(event.name)
            let rawCount = Int(Double(event.photos) * 0.6)

            let eventCameraCounts = event.cameras.reduce(into: [String: Int]()) { $0["\($1.make)|\($1.model)"] = Int(Double(event.photos) * $1.pct) }
            let eventLensCounts = event.lenses.reduce(into: [String: Int]()) { $0["\($1.make)|\($1.model)"] = Int(Double(event.photos) * $1.pct) }
            let eventDate = makeDate(year: event.year, month: event.month, day: event.day)
            let captureTimestampsByDay = mockCaptureTimestamps(photoCount: event.photos, startDate: eventDate)
            let cameraMeta = cameraMetadata(for: event.cameras, eventDate: eventDate, eventIndex: i)
            let primaryCameraKey = "\(event.cameras[0].make)|\(event.cameras[0].model)"

            let cachedReport = StatsReport(
                topLenses: event.lenses.prefix(5).enumerated().map { idx, l in
                    StatsReport.LensStat(make: l.make, model: l.model, count: Int(Double(event.photos) * l.pct), rank: idx + 1)
                },
                mostUsedCamera: StatsReport.CameraStat(
                    make: event.cameras[0].make,
                    model: event.cameras[0].model,
                    count: Int(Double(event.photos) * event.cameras[0].pct),
                    maxShutterCount: cameraMeta.maxShutterCounts[primaryCameraKey],
                    lastSeenDate: cameraMeta.lastSeenDates[primaryCameraKey]
                ),
                shutterSpeeds: [
                    StatsReport.ShutterStat(rawValue: 1.0/2000.0, count: Int(Double(event.photos) * 0.25)),
                    StatsReport.ShutterStat(rawValue: 1.0/1000.0, count: Int(Double(event.photos) * 0.35)),
                    StatsReport.ShutterStat(rawValue: 1.0/500.0, count: Int(Double(event.photos) * 0.20)),
                    StatsReport.ShutterStat(rawValue: 1.0/250.0, count: Int(Double(event.photos) * 0.12)),
                    StatsReport.ShutterStat(rawValue: 1.0/125.0, count: Int(Double(event.photos) * 0.08))
                ],
                totalFilesAnalyzed: event.photos,
                rawOutput: "[]",
                avgISO: Double.random(in: 400...2400),
                avgAperture: Double.random(in: 1.8...5.6),
                avgFocalLength: Double.random(in: 24...200),
                totalBytes: Int64(event.gigabytes * 1024 * 1024 * 1024),
                totalDuration: Int.random(in: 1800...7200),
                importCount: 1,
                lensCounts: eventLensCounts,
                cameraCounts: eventCameraCounts,
                shutterCounts: [1.0/2000: Int(Double(event.photos)*0.25), 1.0/1000: Int(Double(event.photos)*0.35), 1.0/500: Int(Double(event.photos)*0.20)],
                isoCounts: isoCounts,
                apertureCounts: apertureCounts,
                focalCounts: focalCounts,
                orientationCounts: ["landscape": Int(Double(event.photos)*0.55), "portrait": Int(Double(event.photos)*0.45)],
                isoSum: Double.random(in: 400...2400) * Double(event.photos),
                isoCount: event.photos,
                apertureSum: Double.random(in: 1.8...5.6) * Double(event.photos),
                apertureCount: event.photos,
                focalSum: Double.random(in: 24...200) * Double(event.photos),
                focalCount: event.photos,
                captureTimestampsByDay: captureTimestampsByDay,
                cameraMaxShutterCounts: cameraMeta.maxShutterCounts,
                cameraLastSeenDates: cameraMeta.lastSeenDates
            )
            EventStatsCache.save(cachedReport, forPath: eventPath, scanDate: Date(), rawFileCountAtScan: rawCount)
        }

        // MARK: - Download real banner images (picsum.photos)
        let bannerDir = AppPaths.subdirectory("event_banners")
        try? fm.createDirectory(at: bannerDir, withIntermediateDirectories: true)

        let group = DispatchGroup()
        var bannerPaths = Array(repeating: "", count: count)

        for i in 0..<count {
            group.enter()
            let picID = picIDs[i % picIDs.count]
            let urlString = "https://picsum.photos/id/\(picID)/800/400"
            guard let url = URL(string: urlString) else { group.leave(); continue }

            let task = URLSession.shared.dataTask(with: url) { data, _, _ in
                defer { group.leave() }
                guard let data = data, let img = NSImage(data: data) else { return }

                let filename = events[i].name.replacingOccurrences(of: " ", with: "_")
                    .replacingOccurrences(of: "/", with: "-")
                    .replacingOccurrences(of: "&", with: "and") + ".jpg"
                let fileURL = bannerDir.appendingPathComponent(filename)

                // Crop to center at thumbnail aspect ratio (44:34 ≈ 1.29:1)
                if let cgImg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    let targetAspect: CGFloat = 44.0 / 34.0
                    let imgW = CGFloat(cgImg.width)
                    let imgH = CGFloat(cgImg.height)
                    let imgAspect = imgW / imgH

                    var cropRect: CGRect
                    if imgAspect > targetAspect {
                        let newW = imgH * targetAspect
                        cropRect = CGRect(x: (imgW - newW) / 2, y: 0, width: newW, height: imgH)
                    } else {
                        let newH = imgW / targetAspect
                        cropRect = CGRect(x: 0, y: (imgH - newH) / 2, width: imgW, height: newH)
                    }

                    if let cropped = cgImg.cropping(to: cropRect) {
                        let rep = NSBitmapImageRep(cgImage: cropped)
                        if let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) {
                            try? jpg.write(to: fileURL)
                            bannerPaths[i] = fileURL.path
                        }
                    }
                }
            }
            task.resume()
        }

        group.wait()
        appState.eventFolderBannerImagePaths = bannerPaths

        // Link finalized events to their bookmarks
        appState.eventFolderFinalizedEventID = Array(repeating: nil, count: count)
        for fe in allFinalizedEvents {
            if let idx = events.firstIndex(where: { $0.name == fe.name }) {
                appState.eventFolderFinalizedEventID[idx] = fe.id
            }
        }

        // MARK: - Total stats report (merged across all events)
        let totalPhotos = events.reduce(0) { $0 + $1.photos }
        let totalBytes = events.reduce(Int64(0)) { $0 + Int64($1.gigabytes * 1024 * 1024 * 1024) }

        var mergedCameraCounts: [String: Int] = [:]
        var mergedLensCounts: [String: Int] = [:]
        var mergedCaptureTimestampsByDay: [String: [Double]] = [:]
        var mergedCameraMaxShutterCounts: [String: Int] = [:]
        var mergedCameraLastSeenDates: [String: Date] = [:]
        for (eventIndex, event) in events.enumerated() {
            let eventDate = makeDate(year: event.year, month: event.month, day: event.day)
            for (key, pct) in event.cameras.map({ ("\($0.make)|\($0.model)", $0.pct) }) {
                mergedCameraCounts[key, default: 0] += Int(Double(event.photos) * pct)
            }
            for (key, pct) in event.lenses.map({ ("\($0.make)|\($0.model)", $0.pct) }) {
                mergedLensCounts[key, default: 0] += Int(Double(event.photos) * pct)
            }
            for (day, timestamps) in mockCaptureTimestamps(photoCount: event.photos, startDate: eventDate) {
                mergedCaptureTimestampsByDay[day, default: []].append(contentsOf: timestamps)
            }
            let meta = cameraMetadata(for: event.cameras, eventDate: eventDate, eventIndex: eventIndex)
            for (key, count) in meta.maxShutterCounts {
                mergedCameraMaxShutterCounts[key] = max(mergedCameraMaxShutterCounts[key] ?? 0, count)
            }
            for (key, date) in meta.lastSeenDates {
                if date > (mergedCameraLastSeenDates[key] ?? .distantPast) {
                    mergedCameraLastSeenDates[key] = date
                }
            }
        }

        let mergedTopLenses = mergedLensCounts
            .sorted { $0.value > $1.value }
            .prefix(8)
            .enumerated()
            .map { entry -> StatsReport.LensStat in
                let parts = entry.element.key.split(separator: "|", maxSplits: 1)
                return StatsReport.LensStat(make: String(parts[0]), model: String(parts[1]), count: entry.element.value, rank: entry.offset + 1)
            }

        let monthCounts: [String: Int] = allImportHistory.reduce(into: [String: Int]()) { result, entry in
            let fmt = DateFormatter()
            fmt.dateFormat = "MMM yyyy"
            let key = fmt.string(from: entry.date)
            result[key, default: 0] += entry.fileCount
        }

        let shutterCounts: [Double: Int] = [1.0/8000: 400, 1.0/4000: 800, 1.0/2000: 2200, 1.0/1000: 3800, 1.0/500: 2200, 1.0/250: 1100, 1.0/125: 700]
        let topCameraKey = "Sony|ILCE-9M3"

        let totalStats = StatsReport(
            topLenses: Array(mergedTopLenses),
            mostUsedCamera: StatsReport.CameraStat(
                make: "Sony",
                model: "ILCE-9M3",
                count: mergedCameraCounts[topCameraKey] ?? Int(Double(totalPhotos) * 0.45),
                maxShutterCount: mergedCameraMaxShutterCounts[topCameraKey],
                lastSeenDate: mergedCameraLastSeenDates[topCameraKey]
            ),
            shutterSpeeds: shutterCounts.map { StatsReport.ShutterStat(rawValue: $0.key, count: $0.value) }.sorted { $0.rawValue > $1.rawValue },
            totalFilesAnalyzed: totalPhotos,
            rawOutput: "[]",
            avgISO: 1100,
            avgAperture: 2.8,
            avgFocalLength: 135,
            totalBytes: totalBytes,
            totalDuration: 18000,
            importCount: allImportHistory.count,
            firstImportDate: allImportHistory.last?.date,
            lensCounts: mergedLensCounts,
            cameraCounts: mergedCameraCounts,
            shutterCounts: shutterCounts,
            isoCounts: isoCounts,
            apertureCounts: apertureCounts,
            focalCounts: focalCounts,
            orientationCounts: ["landscape": Int(Double(totalPhotos) * 0.55), "portrait": Int(Double(totalPhotos) * 0.45)],
            isoSum: 1100 * Double(totalPhotos),
            isoCount: totalPhotos,
            apertureSum: 2.8 * Double(totalPhotos),
            apertureCount: totalPhotos,
            focalSum: 135 * Double(totalPhotos),
            focalCount: totalPhotos,
            monthCounts: monthCounts,
            captureTimestampsByDay: mergedCaptureTimestampsByDay,
            cameraMaxShutterCounts: mergedCameraMaxShutterCounts,
            cameraLastSeenDates: mergedCameraLastSeenDates
        )

        // MARK: - Last import report (hero card)
        let lastEvent = events.last!
        appState.lastImportReport = ImportReport(
            sourceVolumeName: lastEvent.source,
            sourcePath: "/Volumes/\(lastEvent.source)/DCIM",
            destinationPath: makePath(lastEvent.name),
            fileCount: lastEvent.photos,
            totalBytes: Int64(lastEvent.gigabytes * 1024 * 1024 * 1024),
            duration: Double.random(in: 60...300),
            averageSpeed: Double.random(in: 80_000_000...250_000_000),
            importedFiles: []
        )

        // MARK: - Persist everything
        appState.totalStatsReport = totalStats
        appState.finalizedEvents = allFinalizedEvents
        StatsStorage.save(totalStats)
        ImportHistoryStorage.save(allImportHistory)
        appState.importHistory = allImportHistory
        FinalizedEventsStore.saveAll(allFinalizedEvents)

        appState.log("Mock data generated: \(events.count) events, \(totalPhotos) photos, \(allImportHistory.count) imports", level: .info)
        mockDataStatus = "Done — \(events.count) events, \(totalPhotos) photos, \(allImportHistory.count) imports."
    }
}
