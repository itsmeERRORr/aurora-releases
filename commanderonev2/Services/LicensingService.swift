import Foundation
import IOKit

/// Online licensing via Supabase.
///
/// Activation calls the `validate-license` Edge Function which:
///   - Verifies the key exists in the DB and is active/not-expired
///   - Binds the Mac UUID on first use (rejects on a different Mac)
///   - Updates `last_seen_at` on subsequent validations
///
/// The result is cached in Keychain so the app works offline after the first activation.
/// A silent background revalidation runs at launch to catch revoked/expired keys.
enum LicensingService {

    // MARK: - Supabase config

    static let supabaseURL = "https://aknpnxdgbatrcketoaku.supabase.co"
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFrbnBueGRnYmF0cmNrZXRvYWt1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODIzODg3MzUsImV4cCI6MjA5Nzk2NDczNX0.YmgppbIpYJAffHRtwcBNEE_UqAeBqBuYaZlaxam5Gss"

    // MARK: - Keychain keys

    private static let keychainService = "errormedia.aurora.license"
    private static let keychainAccount = "activatedKey"
    static let adminTokenKeychainAccount = "adminToken"

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

    // MARK: - Stored activation (Keychain cache)

    struct StoredActivation: Codable {
        let key: String
        let uuid: String
        let plan: String
        var expiresAt: Date?
        var customerEmail: String?
        let activatedAt: Date
    }

    static func hasStoredKey() -> Bool {
        KeychainStore.string(service: keychainService, account: keychainAccount) != nil
    }

    /// Synchronous check — reads from Keychain cache. Safe to call on main thread.
    static func isActivated() -> Bool {
        guard let a = storedActivation() else { return false }
        if let exp = a.expiresAt, exp < Date() { return false }
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
        guard let uuid = hardwareUUID() else {
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
                let expiresAt = (json["expires_at"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }

                save(StoredActivation(key: key, uuid: uuid, plan: plan, expiresAt: expiresAt, customerEmail: email, activatedAt: Date()))
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
              let uuid = hardwareUUID() else {
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
                let expiresAt = (json["expires_at"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
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
    // Calls the admin-create-license Edge Function.
    // Requires ADMIN_SECRET to be configured in Supabase and stored in Keychain.

    enum AdminCreateResult {
        case success(licenseKey: String)
        case unauthorized
        case networkError(String)
    }

    static func adminCreateLicense(name: String, plan: String, email: String?) async -> AdminCreateResult {
        guard let secret = KeychainStore.string(service: keychainService, account: adminTokenKeychainAccount),
              !secret.isEmpty else {
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
        req.setValue("Bearer \(secret)", forHTTPHeaderField: "authorization")
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
        guard let secret = KeychainStore.string(service: keychainService, account: adminTokenKeychainAccount),
              !secret.isEmpty else {
            return .unauthorized
        }
        guard let url = URL(string: "\(supabaseURL)/functions/v1/admin-revoke-license") else {
            return .networkError("Invalid URL.")
        }

        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue("Bearer \(secret)", forHTTPHeaderField: "authorization")
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

    static func saveAdminToken(_ token: String) {
        KeychainStore.setString(token, service: keychainService, account: adminTokenKeychainAccount)
    }

    static func hasAdminToken() -> Bool {
        guard let t = KeychainStore.string(service: keychainService, account: adminTokenKeychainAccount) else { return false }
        return !t.isEmpty
    }

    static func clearAdminToken() {
        KeychainStore.remove(service: keychainService, account: adminTokenKeychainAccount)
    }
}
