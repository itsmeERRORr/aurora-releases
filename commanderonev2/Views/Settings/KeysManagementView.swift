import SwiftUI

/// Admin tool (beta only) — creates license keys in Supabase via the `admin-create-license` Edge
/// Function and lists/revokes the real license table via `admin-dashboard` (same backend the web
/// admin panel at jf.getaurora.pro uses). The admin credentials are stored in Keychain on first
/// sign-in and never appear in source code.
struct KeysManagementView: View {
    @State private var name = ""
    @State private var email = ""
    @State private var plan: Plan = .pro
    @State private var isCreating = false
    @State private var result: CreateResult?
    @State private var copiedKey: String?

    // Live license list (fetched from Supabase via admin-dashboard)
    @State private var allLicenses: [LicensingService.AdminLicense] = []
    @State private var isLoadingLicenses = false
    @State private var licensesLoadError: String?
    @State private var revokingLicenseID: String?
    @State private var licenseToRevoke: LicensingService.AdminLicense?

    // Admin sign-in
    @State private var adminEmail = ""
    @State private var adminPassword = ""
    @State private var hasToken = LicensingService.hasAdminCredentials()
    @State private var showTokenSetup = false

    enum Plan: String, CaseIterable {
        case pro, lifetime
        var label: String { rawValue.capitalized }
    }

    enum CreateResult {
        case success(key: String, name: String, plan: String)
        case unauthorized
        case error(String)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if !hasToken { tokenSetupBanner }
                createSection
                allLicensesSection
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(minWidth: 520, minHeight: 400)
        .onAppear {
            if hasToken { Task { await loadAllLicenses() } }
        }
        .confirmationDialog(
            "Revogar licença de \(licenseToRevoke?.name ?? "")?",
            isPresented: Binding(get: { licenseToRevoke != nil }, set: { if !$0 { licenseToRevoke = nil } }),
            titleVisibility: .visible
        ) {
            Button("Revogar", role: .destructive) {
                if let license = licenseToRevoke { revokeLicense(license) }
            }
            Button("Cancelar", role: .cancel) { licenseToRevoke = nil }
        } message: {
            Text("Esta licença ficará inválida no Supabase. Não é possível desfazer.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("License Manager")
                .font(.auroraTopbarH2)
                .tracking(-0.4)
                .foregroundStyle(Color.auroraTxt)
            Spacer()
            if hasToken {
                Button("Sign Out") {
                    LicensingService.clearAdminCredentials()
                    hasToken = false
                }
                .buttonStyle(AuroraGhostButtonStyle())
                .font(.manrope(11, weight: .semibold))
            }
        }
        .padding(.bottom, 4)
        .sheet(isPresented: $showTokenSetup) { tokenSetupSheet }
    }

    // MARK: - Token setup banner

    private var tokenSetupBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Not signed in")
                    .font(.manrope(12, weight: .bold))
                    .foregroundStyle(Color.auroraTxt)
                Text("Sign in with your Supabase admin account to create keys.")
                    .font(.manrope(11, weight: .medium))
                    .foregroundStyle(Color.auroraFaint)
            }
            Spacer()
            Button("Sign In") { showTokenSetup = true }
                .buttonStyle(AuroraGradientButtonStyle(compact: true))
        }
        .padding(12)
        .background(Color.auroraPanel2)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Sign-in sheet

    private var tokenSetupSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Admin Sign In")
                .font(.manrope(16, weight: .black))
                .foregroundStyle(Color.auroraTxt)

            Text("Use the Supabase Auth account created for admin access:\nDashboard → Authentication → Users")
                .font(.manrope(12, weight: .medium))
                .foregroundStyle(Color.auroraFaint)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Email", text: $adminEmail)
                .textFieldStyle(.plain)
                .font(.manrope(13, weight: .medium))
                .foregroundStyle(Color.auroraTxt)
                .padding(10)
                .background(Color.auroraPanel2)
                .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.small))

            SecureField("Password", text: $adminPassword)
                .textFieldStyle(.plain)
                .font(.manrope(13, weight: .medium))
                .foregroundStyle(Color.auroraTxt)
                .padding(10)
                .background(Color.auroraPanel2)
                .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.small))

            HStack {
                Spacer()
                Button("Cancel") { showTokenSetup = false }
                    .buttonStyle(AuroraGhostButtonStyle())
                Button("Sign In") {
                    let trimmedEmail = adminEmail.trimmingCharacters(in: .whitespaces)
                    guard !trimmedEmail.isEmpty, !adminPassword.isEmpty else { return }
                    LicensingService.saveAdminCredentials(email: trimmedEmail, password: adminPassword)
                    hasToken = true
                    showTokenSetup = false
                    adminPassword = ""
                    Task { await loadAllLicenses() }
                }
                .buttonStyle(AuroraGradientButtonStyle(compact: true))
                .disabled(adminEmail.trimmingCharacters(in: .whitespaces).isEmpty || adminPassword.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
        .background(Color.auroraBg)
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Create section

    private var createSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Create Key")
                .font(.manrope(13, weight: .bold))
                .foregroundStyle(Color.auroraTxt)

            field(label: "Name") {
                TextField("e.g. Elliot", text: $name)
            }

            field(label: "Email (opcional)") {
                TextField("friend@example.com", text: $email)
            }

            HStack(spacing: 8) {
                Text("Plan")
                    .font(.manrope(11, weight: .bold))
                    .foregroundStyle(Color.auroraFaint)
                    .frame(width: 80, alignment: .leading)
                ForEach(Plan.allCases, id: \.self) { p in
                    Button(p.label) { plan = p }
                        .buttonStyle(AuroraGhostButtonStyle(active: plan == p))
                }
                Spacer()
            }

            HStack {
                Spacer()
                Button(isCreating ? "A criar…" : "Create Key") { createKey() }
                    .buttonStyle(AuroraGradientButtonStyle(compact: true))
                    .disabled(!hasToken || name.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
            }

            if let result {
                resultView(result)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .background(Color.auroraPanel2)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .animation(.easeOut(duration: 0.18), value: result != nil)
    }

    @ViewBuilder
    private func resultView(_ r: CreateResult) -> some View {
        switch r {
        case .success(let key, let name, let plan):
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Key criada para \(name) (\(plan))")
                        .font(.manrope(12, weight: .bold))
                        .foregroundStyle(.green)
                }
                keyDisplay(key)
            }

        case .unauthorized:
            HStack(spacing: 6) {
                Image(systemName: "lock.fill").foregroundStyle(.orange)
                Text("Sign-in rejeitado. Verifica o email/password.")
                    .font(.manrope(11, weight: .semibold))
                    .foregroundStyle(.orange)
            }

        case .error(let msg):
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                Text(msg)
                    .font(.manrope(11, weight: .semibold))
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - All licenses (live from Supabase)

    private var allLicensesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Todas as licenças")
                    .font(.manrope(13, weight: .bold))
                    .foregroundStyle(Color.auroraTxt)
                if isLoadingLicenses {
                    ProgressView().scaleEffect(0.5).frame(width: 16, height: 16)
                }
                Spacer()
                Button("Atualizar") {
                    Task { await loadAllLicenses() }
                }
                .buttonStyle(.plain)
                .font(.manrope(10, weight: .semibold))
                .foregroundStyle(Color.auroraFaint)
                .disabled(!hasToken || isLoadingLicenses)
            }

            if let licensesLoadError {
                Text(licensesLoadError)
                    .font(.manrope(11, weight: .semibold))
                    .foregroundStyle(.orange)
            }

            VStack(spacing: 6) {
                ForEach(allLicenses) { license in
                    licenseRow(license)
                }
            }
        }
    }

    private func licenseRow(_ license: LicensingService.AdminLicense) -> some View {
        let isRevoking = revokingLicenseID == license.id
        let canRevoke = license.status == "active" || license.status == "cancelled"

        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(license.name)
                        .font(.manrope(12, weight: .bold))
                        .foregroundStyle(Color.auroraTxt)
                    Text(license.plan.capitalized)
                        .font(.manrope(9, weight: .bold))
                        .foregroundStyle(license.plan == "lifetime" ? Color.auroraGold : Color.auroraCyan)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            (license.plan == "lifetime" ? Color.auroraGold : Color.auroraCyan).opacity(0.15)
                        )
                        .clipShape(Capsule())
                    Text(license.status.capitalized)
                        .font(.manrope(9, weight: .bold))
                        .foregroundStyle(license.status == "active" ? .green : Color.auroraFaint)
                }
                Text((license.licenseKeyPrefix ?? "") + "…")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Color.auroraFaint)
                    .lineLimit(1)
                if let email = license.customerEmail {
                    Text(email)
                        .font(.manrope(10, weight: .medium))
                        .foregroundStyle(Color.auroraMuted)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                if let created = license.createdAt {
                    Text(created.formatted(date: .abbreviated, time: .omitted))
                        .font(.manrope(10, weight: .medium))
                        .foregroundStyle(Color.auroraFaint)
                }

                if canRevoke {
                    if isRevoking {
                        ProgressView().scaleEffect(0.5).frame(width: 20, height: 20)
                    } else {
                        Button {
                            licenseToRevoke = license
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundStyle(.red.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        .help("Revogar esta licença no Supabase")
                    }
                }
            }
        }
        .padding(10)
        .background(Color.auroraPanel2)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .opacity(isRevoking ? 0.5 : 1)
    }

    // MARK: - Helpers

    private func keyDisplay(_ key: String) -> some View {
        HStack(spacing: 8) {
            Text(key)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(Color.auroraTxt)
                .textSelection(.enabled)
            Spacer()
            Button(copiedKey == key ? "Copiado!" : "Copiar") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(key, forType: .string)
                copiedKey = key
            }
            .buttonStyle(AuroraGhostButtonStyle())
        }
        .padding(10)
        .background(Color.auroraPanel)
        .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.small))
    }

    private func field<F: View>(label: String, @ViewBuilder field: () -> F) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.manrope(11, weight: .bold))
                .foregroundStyle(Color.auroraFaint)
                .frame(width: 80, alignment: .leading)
            field()
                .textFieldStyle(.plain)
                .font(.manrope(12, weight: .medium))
                .foregroundStyle(Color.auroraTxt)
                .padding(8)
                .background(Color.auroraPanel)
                .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.small))
        }
    }

    // MARK: - Create action

    private func createKey() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        isCreating = true
        result = nil
        copiedKey = nil

        Task { @MainActor in
            let r = await LicensingService.adminCreateLicense(
                name: trimmedName,
                plan: plan.rawValue,
                email: trimmedEmail.isEmpty ? nil : trimmedEmail
            )
            isCreating = false

            switch r {
            case .success(let key):
                result = .success(key: key, name: trimmedName, plan: plan.label)
                name = ""
                email = ""
                plan = .pro
                await loadAllLicenses()
            case .unauthorized:
                hasToken = false
                result = .unauthorized
            case .networkError(let msg):
                result = .error(msg)
            }
        }
    }

    // MARK: - Live license list

    private func loadAllLicenses() async {
        isLoadingLicenses = true
        licensesLoadError = nil

        let r = await LicensingService.adminFetchLicenses()
        isLoadingLicenses = false

        switch r {
        case .success(let licenses):
            allLicenses = licenses.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        case .unauthorized:
            hasToken = false
        case .networkError(let msg):
            licensesLoadError = msg
        }
    }

    private func revokeLicense(_ license: LicensingService.AdminLicense) {
        licenseToRevoke = nil
        revokingLicenseID = license.id

        Task { @MainActor in
            let r = await LicensingService.adminRevokeLicenseByID(license.id)
            revokingLicenseID = nil

            switch r {
            case .success:
                await loadAllLicenses()
            case .unauthorized:
                hasToken = false
            case .networkError(let msg):
                licensesLoadError = "Revoke falhou: \(msg)"
            }
        }
    }
}

extension KeysManagementView.CreateResult: Equatable {
    static func == (lhs: KeysManagementView.CreateResult, rhs: KeysManagementView.CreateResult) -> Bool {
        switch (lhs, rhs) {
        case (.unauthorized, .unauthorized): return true
        case (.success(let k1, _, _), .success(let k2, _, _)): return k1 == k2
        case (.error(let m1), .error(let m2)): return m1 == m2
        default: return false
        }
    }
}

#Preview {
    KeysManagementView()
}
