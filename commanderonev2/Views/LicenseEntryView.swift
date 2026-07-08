import SwiftUI

/// License activation overlay. Shown on top of the dashboard with a blur
/// background when the app is not activated.
struct LicenseEntryView: View {
    @Binding var isPresented: Bool
    @State private var licenseKey = ""
    @State private var status: Status?
    @State private var isActivating = false

    enum Status {
        case success
        case error(String)
    }

    var body: some View {
        ZStack {
            // Blur background
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture { }

            // Small card
            VStack(spacing: 0) {
                // Header
                HStack {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.auroraCyan, .auroraViolet],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Text("Aurora")
                        .font(.manrope(16, weight: .black))
                        .foregroundStyle(Color.auroraTxt)
                    Text("RAW speed. Smart stats.")
                        .font(.manrope(11, weight: .medium))
                        .foregroundStyle(Color.auroraFaint)
                    Spacer()
                }
                .padding(.bottom, 16)

                Divider()
                    .background(Color.auroraStroke)
                    .padding(.bottom, 16)

                // Key input
                HStack(spacing: 10) {
                    Image(systemName: "key.fill")
                        .foregroundStyle(Color.auroraViolet)
                        .frame(width: 16)

                    TextField("", text: $licenseKey, prompt: Text("AURORA-XXXX-XXXX-XXXX").foregroundColor(Color.auroraMuted))
                        .textFieldStyle(.plain)
                        .font(.manrope(13, weight: .medium))
                        .foregroundStyle(Color.auroraTxt)
                        .autocorrectionDisabled()
                        .onSubmit { activate() }
                }
                .padding(10)
                .background(Color.auroraPanel)
                .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.small))

                .padding(.top, 16)

                // Status
                if let status {
                    Group {
                        switch status {
                        case .success:
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Activated!")
                                    .font(.manrope(12, weight: .semibold))
                                    .foregroundStyle(.green)
                            }
                        case .error(let msg):
                            HStack(spacing: 6) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                                Text(msg)
                                    .font(.manrope(11, weight: .semibold))
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 10)
                }

                if isActivating {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("Activating…")
                            .font(.manrope(11, weight: .semibold))
                            .foregroundStyle(Color.auroraMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 10)
                }

                // Activate button
                Button("Activate") { activate() }
                    .buttonStyle(AuroraGradientButtonStyle(compact: true))
                    .disabled(licenseKey.trimmingCharacters(in: .whitespaces).isEmpty || isActivating)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 16)
            }
            .padding(20)
            .frame(width: 380)
            .background(
                RoundedRectangle(cornerRadius: AuroraRadius.medium)
                    .fill(Color.auroraBg)
                    .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AuroraRadius.medium)
                    .stroke(Color.auroraStroke, lineWidth: 1)
            )
            .environment(\.colorScheme, .dark)
        }
    }

    private func activate() {
        let key = licenseKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }

        isActivating = true
        status = nil

        Task { @MainActor in
            let result = await LicensingService.activate(with: key)
            isActivating = false

            switch result {
            case .success:
                status = .success
                try? await Task.sleep(for: .seconds(1))
                isPresented = false
            case .notFound:
                status = .error("License key not found.")
            case .alreadyActivatedOnAnotherMac:
                status = .error("This key is already in use on another Mac.")
            case .inactive(let reason, _):
                status = .error(reason)
            case .networkError(let msg):
                status = .error(msg)
            }
        }
    }
}
