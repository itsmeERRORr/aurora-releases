import Foundation
import IOKit
import CryptoKit

/// Online licensing via Supabase.
///
/// Activation calls the `validate-license` Edge Function which:
///   - Verifies the key exists in the DB and is active/not-expired
///   - Binds the Mac UUID on first use (rejects on a different Mac)
///   - Updates `last_seen_at` on subsequent validations
///   - Signs the response with an ECDSA (P-256) private key held only on the server
///
/// The result is cached locally so the app works offline after the first activation,
/// but the cache is only trusted if its ECDSA signature verifies against the public
/// key embedded below — a hand-edited or fabricated cache entry fails verification
/// and is treated as not activated. A silent background revalidation runs at launch
/// to catch revoked/expired keys and to refresh the signature/last-validated stamp.
enum LicensingService {

    // MARK: - Supabase config

    static let supabaseURL = "https://aknpnxdgbatrcketoaku.supabase.co"
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFrbnBueGRnYmF0cmNrZXRvYWt1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODIzODg3MzUsImV4cCI6MjA5Nzk2NDczNX0.YmgppbIpYJAffHRtwcBNEE_UqAeBqBuYaZlaxam5Gss"

    // MARK: - Keychain keys

    private static let keychainService = "errormedia.aurora.license"
    private static let keychainAccount = "activatedKey"
    private static let adminEmailKeychainAccount = "adminEmail"
    private static let adminPasswordKeychainAccount = "adminPassword"

    // MARK: - Signature verification

    /// Public half of the ECDSA (P-256) key pair used by the `validate-license` Edge
    /// Function to sign activation payloads. Safe to embed — only the private key
    /// (held server-side as a Supabase secret) can produce valid signatures.
    private static let signingPublicKeyDER = Data(
        base64Encoded: "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAET2tVgzW1g8AGdY3nNIgenp1PsQLEObR9CGxAE00vfa5h0pVOE4hS/S7L3iTlgPeqEyWY8ZynNimMCpuwGx+fhg=="
    )!
    private static let signingPublicKey = try? P256.Signing.PublicKey(derRepresentation: signingPublicKeyDER)

    /// Offline grace period: an activation cached locally must be re-confirmed with
    /// the server at least this often, or it stops being trusted. Prevents an
    /// indefinitely-offline (or network-blocked) Mac from trusting a forged or
    /// long-revoked cache forever.
    private static let maxOfflineValidationAge: TimeInterval = 30 * 24 * 60 * 60 // 30 days

    static func normalizeLicenseKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    }

    /// Must exactly match the message the server signs in validate-license/index.ts.
    private static func activationMessage(key: String, uuid: String, plan: String, expiresAtRaw: String?, issuedAtRaw: String) -> String {
        "\(key)|\(uuid)|\(plan)|\(expiresAtRaw ?? "")|\(issuedAtRaw)"
    }

    private static func verifySignature(_ signatureB64: String?, for activation: StoredActivation) -> Bool {
        guard let signatureB64,
              let issuedAtRaw = activation.issuedAtRaw,
              let signingPublicKey,
              let sigData = Data(base64Encoded: signatureB64),
              let signature = try? P256.Signing.ECDSASignature(rawRepresentation: sigData) else { return false }
        let message = activationMessage(
            key: activation.key, uuid: activation.uuid, plan: activation.plan,
            expiresAtRaw: activation.expiresAtRaw, issuedAtRaw: issuedAtRaw
        )
        return signingPublicKey.isValidSignature(signature, for: Data(message.utf8))
    }

    // MARK: - Hardware UUID

    static func hardwareUUID() -> String? {
        var masterPort: mach_port_t = 0
        guard IOMasterPort(mach_host_self(), &masterPort) == KERN_SUCCESS else { return nil }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(masterPort, IOServiceMatching("IOPlatformExpertDevice"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        let service = IOIteratorNext(iterator)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString, nil, 0)?.takeRetainedValue() as? String
    }

    // MARK: - Stored activation (local cache)

    struct StoredActivation: Codable {
        let key: String
        let uuid: String
        let plan: String
        var expiresAt: Date?
        /// Exact `expires_at` string as returned (and signed) by the server. Needed
        /// verbatim for signature verification — re-formatting the Date wouldn't match.
        var expiresAtRaw: String?
        var customerEmail: String?
        let activatedAt: Date
        /// Server-issued timestamp (ISO8601) that is part of the signed message, so it
        /// can't be forged. Used for the offline-grace window instead of a client-side
        /// clock the user could edit. `nil` only on pre-signing legacy records.
        var issuedAtRaw: String?
        /// Base64 ECDSA signature from the server over `activationMessage(...)`.
        /// `nil` only for activations cached by an app version predating this check.
        var signature: String?

        init(
            key: String, uuid: String, plan: String, expiresAt: Date?, expiresAtRaw: String?,
            customerEmail: String?, activatedAt: Date, issuedAtRaw: String?, signature: String?
        ) {
            self.key = key
            self.uuid = uuid
            self.plan = plan
            self.expiresAt = expiresAt
            self.expiresAtRaw = expiresAtRaw
            self.customerEmail = customerEmail
            self.activatedAt = activatedAt
            self.issuedAtRaw = issuedAtRaw
            self.signature = signature
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            key = try container.decode(String.self, forKey: .key)
            uuid = try container.decode(String.self, forKey: .uuid)
            plan = try container.decode(String.self, forKey: .plan)
            expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
            expiresAtRaw = try container.decodeIfPresent(String.self, forKey: .expiresAtRaw)
            customerEmail = try container.decodeIfPresent(String.self, forKey: .customerEmail)
            activatedAt = try container.decode(Date.self, forKey: .activatedAt)
            issuedAtRaw = try container.decodeIfPresent(String.self, forKey: .issuedAtRaw)
            signature = try container.decodeIfPresent(String.self, forKey: .signature)
        }
    }

    static func hasStoredKey() -> Bool {
        KeychainStore.string(service: keychainService, account: keychainAccount) != nil
    }

    /// Synchronous check — reads from the local cache. Safe to call on main thread.
    /// Trusts the cache ONLY if every condition holds: a valid ECDSA signature
    /// (proving the server issued it — an unsigned or edited record fails here), the
    /// Mac's hardware UUID matches the bound one, not past its expiry, and the
    /// server-signed issue time is within the offline-grace window.
    ///
    /// There is deliberately no "trust unsigned cache" fallback: the entire record
    /// lives in user-writable storage, so an unsigned record is indistinguishable
    /// from a forged one. Legacy (pre-signing) caches simply read as not-activated
    /// here; `revalidateInBackground()` re-confirms them with the server on launch
    /// (which re-signs the record) and flips the live state back to activated.
    static func isActivated() -> Bool {
        guard let a = storedActivation() else { return false }
        guard let signature = a.signature else { return false }
        // `a.uuid` stores the hashed device id (see DeviceIdentity) — never the raw
        // hardware UUID. Compare against a freshly-computed hash for this Mac.
        guard let currentUUID = DeviceIdentity.deviceHash(), currentUUID == a.uuid else { return false }
        guard verifySignature(signature, for: a) else { return false }
        if let exp = a.expiresAt, exp < Date() { return false }
        guard let issuedAtRaw = a.issuedAtRaw,
              let issuedAt = parseDate(issuedAtRaw),
              Date().timeIntervalSince(issuedAt) <= maxOfflineValidationAge else { return false }
        return true
    }

    static func storedActivation() -> StoredActivation? {
        guard let json = KeychainStore.string(service: keychainService, account: keychainAccount),
              let data = json.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(StoredActivation.self, from: data)
    }

    private static func save(_ activation: StoredActivation) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(activation),
              let json = String(data: data, encoding: .utf8) else { return }
        KeychainStore.setString(json, service: keychainService, account: keychainAccount)
    }

    private static func parseDate(_ string: String) -> Date? {
        let full = ISO8601DateFormatter()
        full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = full.date(from: string) { return d }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        return basic.date(from: string)
    }

    static func deactivate() {
        KeychainStore.remove(service: keychainService, account: keychainAccount)
    }

    // MARK: - Activation result

    enum ActivationResult {
        case success(plan: String, expiresAt: Date?, email: String?)
        case notFound
        case alreadyActivatedOnAnotherMac
        case inactive(reason: String)
        case networkError(String)
    }

    // MARK: - Activate (online — calls validate-license Edge Function)

    @discardableResult
    static func activate(with key: String) async -> ActivationResult {
        // Send the hashed device id, not the raw UUID — the server binds and signs
        // whatever it receives here as an opaque per-device identifier.
        guard let uuid = DeviceIdentity.deviceHash() else {
            return .networkError("Could not read hardware UUID.")
        }
        guard let url = URL(string: "\(supabaseURL)/functions/v1/validate-license") else {
            return .networkError("Invalid URL.")
        }

        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["license_key": key, "mac_uuid": uuid])

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .networkError("Invalid server response.")
            }

            if http.statusCode == 200, json["valid"] as? Bool == true {
                let plan = json["plan"] as? String ?? "pro"
                let email = json["customer_email"] as? String
                let expiresAtRaw = json["expires_at"] as? String
                let expiresAt = expiresAtRaw.flatMap { Self.parseDate($0) }
                let issuedAtRaw = json["issued_at"] as? String
                let signature = json["signature"] as? String
                let normalizedKey = normalizeLicenseKey(key)

                let activation = StoredActivation(
                    key: normalizedKey, uuid: uuid, plan: plan,
                    expiresAt: expiresAt, expiresAtRaw: expiresAtRaw,
                    customerEmail: email, activatedAt: Date(),
                    issuedAtRaw: issuedAtRaw, signature: signature
                )
                guard verifySignature(signature, for: activation) else {
                    return .networkError("Could not verify the server's response. Please try again.")
                }
                save(activation)
                return .success(plan: plan, expiresAt: expiresAt, email: email)
            }

            let errorMsg = json["error"] as? String ?? "Unknown error."
            switch http.statusCode {
            case 404: return .notFound
            case 403 where errorMsg.contains("another Mac"): return .alreadyActivatedOnAnotherMac
            case 403: return .inactive(reason: errorMsg)
            default: return .networkError(errorMsg)
            }
        } catch {
            return .networkError(error.localizedDescription)
        }
    }

    // MARK: - Background revalidation (call at app launch, non-blocking)

    static func revalidateInBackground() {
        guard let activation = storedActivation() else { return }
        Task.detached(priority: .background) {
            let result = await activate(with: activation.key)
            // If the key was revoked server-side, deactivate locally on next launch
            if case .inactive = result { await MainActor.run { deactivate() } }
            if case .notFound = result { await MainActor.run { deactivate() } }
        }
    }

    // MARK: - Cancel subscription

    enum CancelResult {
        case success(expiresAt: Date?)
        case notFound
        case unauthorized
        case alreadyCancelled
        case networkError(String)
    }

    static func cancelSubscription() async -> CancelResult {
        guard let activation = storedActivation(),
              let uuid = DeviceIdentity.deviceHash() else {
            return .networkError("Could not read activation or hardware UUID.")
        }
        guard let url = URL(string: "\(supabaseURL)/functions/v1/cancel-subscription") else {
            return .networkError("Invalid URL.")
        }

        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "license_key": activation.key,
            "mac_uuid": uuid,
        ])

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .networkError("Invalid server response.")
            }
            switch http.statusCode {
            case 200:
                let expiresAt = (json["expires_at"] as? String).flatMap { Self.parseDate($0) }
                return .success(expiresAt: expiresAt)
            case 400 where (json["error"] as? String) == "Already cancelled":
                return .alreadyCancelled
            case 403:
                return .unauthorized
            case 404:
                return .notFound
            default:
                return .networkError(json["error"] as? String ?? "Unknown error.")
            }
        } catch {
            return .networkError(error.localizedDescription)
        }
    }

    // MARK: - Admin: create manual license (Beta only)
    // Calls the admin-create-license / admin-revoke-license Edge Functions.
    // Auth is a Supabase Auth (email/password) sign-in rather than a static shared
    // secret — easier to remember than a token, and the Edge Function validates a
    // real per-user JWT instead of comparing to a fixed string. The Supabase Auth
    // user itself (email/password) must be created once from the Supabase dashboard
    // (Authentication → Users → Add user) — this app never creates that account.

    enum AdminCreateResult {
        case success(licenseKey: String)
        case unauthorized
        case networkError(String)
    }

    static func saveAdminCredentials(email: String, password: String) {
        KeychainStore.setString(email, service: keychainService, account: adminEmailKeychainAccount)
        KeychainStore.setString(password, service: keychainService, account: adminPasswordKeychainAccount)
    }

    static func hasAdminCredentials() -> Bool {
        guard let email = KeychainStore.string(service: keychainService, account: adminEmailKeychainAccount) else { return false }
        return !email.isEmpty
    }

    static func clearAdminCredentials() {
        KeychainStore.remove(service: keychainService, account: adminEmailKeychainAccount)
        KeychainStore.remove(service: keychainService, account: adminPasswordKeychainAccount)
    }

    /// Signs in via Supabase Auth and returns a short-lived JWT to send as the admin
    /// Bearer token. Re-signs in fresh for each admin action rather than juggling
    /// refresh-token expiry — this tool is used a handful of times a week, so the
    /// extra round-trip is irrelevant and the code stays simple.
    private static func fetchAdminAccessToken() async -> String? {
        guard let email = KeychainStore.string(service: keychainService, account: adminEmailKeychainAccount), !email.isEmpty,
              let password = KeychainStore.string(service: keychainService, account: adminPasswordKeychainAccount), !password.isEmpty,
              let url = URL(string: "\(supabaseURL)/auth/v1/token?grant_type=password") else { return nil }

        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["email": email, "password": password])

        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String else { return nil }
        return token
    }

    static func adminCreateLicense(name: String, plan: String, email: String?) async -> AdminCreateResult {
        guard let token = await fetchAdminAccessToken() else {
            return .unauthorized
        }
        guard let url = URL(string: "\(supabaseURL)/functions/v1/admin-create-license") else {
            return .networkError("Invalid URL.")
        }

        var body: [String: Any] = ["name": name, "plan": plan]
        if let email, !email.isEmpty { body["email"] = email }

        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .networkError("Invalid server response.")
            }
            if http.statusCode == 401 { return .unauthorized }
            if http.statusCode == 200, let key = json["license_key"] as? String {
                return .success(licenseKey: key)
            }
            return .networkError(json["error"] as? String ?? "Unknown error.")
        } catch {
            return .networkError(error.localizedDescription)
        }
    }

    static func adminRevokeLicense(key: String) async -> AdminCreateResult {
        guard let token = await fetchAdminAccessToken() else {
            return .unauthorized
        }
        guard let url = URL(string: "\(supabaseURL)/functions/v1/admin-revoke-license") else {
            return .networkError("Invalid URL.")
        }

        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["license_key": key])

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .networkError("Invalid server response.")
            }
            if http.statusCode == 401 { return .unauthorized }
            if http.statusCode == 200 { return .success(licenseKey: key) }
            return .networkError(json["error"] as? String ?? "Unknown error.")
        } catch {
            return .networkError(error.localizedDescription)
        }
    }

}
