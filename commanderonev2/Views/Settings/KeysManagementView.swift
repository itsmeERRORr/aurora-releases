import SwiftUI

struct CreatedLicenseKey: Identifiable, Codable {
    var id: UUID = UUID()
    let name: String
    let plan: String
    let key: String
    let email: String?
    let createdAt: Date
}

/// Admin tool (beta only) — creates license keys in Supabase via the `admin-create-license` Edge Function.
/// The admin token is stored in Keychain on first setup and never appears in source code.
struct KeysManagementView: View {
    @State private var name = ""
    @State private var email = ""
    @State private var plan: Plan = .pro
    @State private var isCreating = false
    @State private var result: CreateResult?
    @State private var copiedKey: String?
    @State private var createdKeys: [CreatedLicenseKey] = []
    @State private var revokingKeyID: UUID?
    @State private var keyToRevoke: CreatedLicenseKey?

    // Admin token setup
    @State private var adminToken = ""
    @State private var hasToken = LicensingService.hasAdminToken()
    @State private var showTokenSetup = false

    private static let udKey = "aurora.adminCreatedKeys"

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
                if !createdKeys.isEmpty { keysListSection }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(minWidth: 520, minHeight: 400)
        .onAppear { loadKeys() }
        .confirmationDialog(
            "Revogar key de \(keyToRevoke?.name ?? "")?",
            isPresented: Binding(get: { keyToRevoke != nil }, set: { if !$0 { keyToRevoke = nil } }),
            titleVisibility: .visible
        ) {
            Button("Revogar", role: .destructive) {
                if let entry = keyToRevoke { revokeKey(entry) }
            }
            Button("Cancelar", role: .cancel) { keyToRevoke = nil }
        } message: {
            Text("A key \(keyToRevoke?.key ?? "") ficará inválida no Supabase. Não é possível desfazer.")
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
                Button("Change Token") { showTokenSetup = true }
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
                Text("Admin token not configured")
                    .font(.manrope(12, weight: .bold))
                    .foregroundStyle(Color.auroraTxt)
                Text("Set the ADMIN_SECRET from your Supabase dashboard to create keys.")
                    .font(.manrope(11, weight: .medium))
                    .foregroundStyle(Color.auroraFaint)
            }
            Spacer()
            Button("Configure") { showTokenSetup = true }
                .buttonStyle(AuroraGradientButtonStyle(compact: true))
        }
        .padding(12)
        .background(Color.auroraPanel2)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Token setup sheet

    private var tokenSetupSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Admin Token")
                .font(.manrope(16, weight: .black))
                .foregroundStyle(Color.auroraTxt)

            Text("Paste the value of ADMIN_SECRET from your Supabase project:\nDashboard → Edge Functions → Secrets → ADMIN_SECRET")
                .font(.manrope(12, weight: .medium))
                .foregroundStyle(Color.auroraFaint)
                .fixedSize(horizontal: false, vertical: true)

            SecureField("Paste your ADMIN_SECRET here", text: $adminToken)
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
                Button("Save") {
                    let trimmed = adminToken.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    LicensingService.saveAdminToken(trimmed)
                    hasToken = true
                    showTokenSetup = false
                    adminToken = ""
                }
                .buttonStyle(AuroraGradientButtonStyle(compact: true))
                .disabled(adminToken.trimmingCharacters(in: .whitespaces).isEmpty)
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
                Text("Admin token rejeitado. Verifica o ADMIN_SECRET no Supabase.")
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

    // MARK: - Keys list

    private var keysListSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Keys criadas")
                    .font(.manrope(13, weight: .bold))
                    .foregroundStyle(Color.auroraTxt)
                Spacer()
                Button("Limpar lista") {
                    createdKeys = []
                    saveKeys()
                }
                .buttonStyle(.plain)
                .font(.manrope(10, weight: .semibold))
                .foregroundStyle(Color.auroraFaint)
            }

            VStack(spacing: 6) {
                ForEach(createdKeys.reversed()) { entry in
                    keyRow(entry)
                }
            }
        }
    }

    private func keyRow(_ entry: CreatedLicenseKey) -> some View {
        let isRevoking = revokingKeyID == entry.id

        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.name)
                        .font(.manrope(12, weight: .bold))
                        .foregroundStyle(Color.auroraTxt)
                    Text(entry.plan.capitalized)
                        .font(.manrope(9, weight: .bold))
                        .foregroundStyle(entry.plan == "lifetime" ? Color.auroraGold : Color.auroraCyan)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            (entry.plan == "lifetime" ? Color.auroraGold : Color.auroraCyan).opacity(0.15)
                        )
                        .clipShape(Capsule())
                }
                Text(entry.key)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Color.auroraFaint)
                    .lineLimit(1)
                if let email = entry.email {
                    Text(email)
                        .font(.manrope(10, weight: .medium))
                        .foregroundStyle(Color.auroraMuted)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text(entry.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.manrope(10, weight: .medium))
                    .foregroundStyle(Color.auroraFaint)

                HStack(spacing: 6) {
                    Button(copiedKey == entry.key ? "Copiado!" : "Copiar") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(entry.key, forType: .string)
                        copiedKey = entry.key
                    }
                    .buttonStyle(AuroraGhostButtonStyle())
                    .controlSize(.small)

                    if isRevoking {
                        ProgressView().scaleEffect(0.5).frame(width: 20, height: 20)
                    } else {
                        Button {
                            keyToRevoke = entry
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundStyle(.red.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        .help("Revogar esta key no Supabase")
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
                let entry = CreatedLicenseKey(
                    name: trimmedName,
                    plan: plan.rawValue,
                    key: key,
                    email: trimmedEmail.isEmpty ? nil : trimmedEmail,
                    createdAt: Date()
                )
                createdKeys.append(entry)
                saveKeys()
                result = .success(key: key, name: trimmedName, plan: plan.label)
                name = ""
                email = ""
                plan = .pro
            case .unauthorized:
                hasToken = false
                result = .unauthorized
            case .networkError(let msg):
                result = .error(msg)
            }
        }
    }

    // MARK: - Revoke action

    private func revokeKey(_ entry: CreatedLicenseKey) {
        keyToRevoke = nil
        revokingKeyID = entry.id

        Task { @MainActor in
            let r = await LicensingService.adminRevokeLicense(key: entry.key)
            revokingKeyID = nil

            switch r {
            case .success:
                createdKeys.removeAll { $0.id == entry.id }
                saveKeys()
            case .unauthorized:
                hasToken = false
                result = .unauthorized
            case .networkError(let msg):
                result = .error("Revoke falhou: \(msg)")
            }
        }
    }

    // MARK: - Persistence

    private func saveKeys() {
        guard let data = try? JSONEncoder().encode(createdKeys) else { return }
        UserDefaults.standard.set(data, forKey: Self.udKey)
    }

    private func loadKeys() {
        guard let data = UserDefaults.standard.data(forKey: Self.udKey),
              let decoded = try? JSONDecoder().decode([CreatedLicenseKey].self, from: data) else { return }
        createdKeys = decoded
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
