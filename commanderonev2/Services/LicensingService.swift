import Foundation
import CryptoKit
import IOKit

/// Offline licensing service. Uses two-part activation:
///
/// 1. **Activation code** — issued without a UUID, contains expiry + features.
///    Format: `AURORA-<base64url-payload>-<base64url-signature>`
///    Payload: `{"code":"<random>","exp":<timestamp>,"feat":<flags>}`
///
/// 2. **Bound key** — stored in Keychain after first use. Combines the
///    activation code with the Mac's hardware UUID so it only works on that Mac.
///
enum LicensingService {

    // MARK: - Public key (P256 ECDSA)

    private static let publicKeyBase64 = "BCrf1xnjFeHTCd++S3bkVUEoYfDLWf4RWfE8ensOhi2CBISwvWisXA0hPO0NfQtew9iRqBfULjKRkuKIpJqrzP4="

    private static let publicKey: P256.Signing.PublicKey? = {
        guard let data = Data(base64Encoded: publicKeyBase64) else { return nil }
        return try? P256.Signing.PublicKey(x963Representation: data)
    }()

    // MARK: - Keychain

    private static let keychainService = "errormedia.aurora.license"
    private static let keychainAccount = "activatedKey"

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

        if let uuid = IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString, nil, 0)?.takeRetainedValue() as? String {
            return uuid
        }
        return nil
    }

    // MARK: - Activation code validation

    enum CodeValidationResult {
        case valid(expiry: Date?, features: UInt32)
        case invalid
        case expired
        case noPublicKey
    }

    /// Validate an activation code (without UUID check).
    static func validateCode(_ code: String) -> CodeValidationResult {
        guard let pub = publicKey else { return .noPublicKey }

        let parts = code.split(separator: "-").map(String.init)
        guard parts.count == 3,
              parts[0] == "AURORA" else { return .invalid }

        guard let payloadData = base64URLDecode(parts[1]),
              let signatureData = base64URLDecode(parts[2]) else { return .invalid }

        guard let signature = try? P256.Signing.ECDSASignature(derRepresentation: signatureData) else { return .invalid }

        guard pub.isValidSignature(signature, for: payloadData) else { return .invalid }

        guard let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else { return .invalid }

        if let exp = json["exp"] as? TimeInterval, exp > 0 {
            if Date().timeIntervalSince1970 > exp { return .expired }
        }

        let features = json["feat"] as? UInt32 ?? 0
        let expiry: Date? = {
            if let exp = json["exp"] as? TimeInterval, exp > 0 {
                return Date(timeIntervalSince1970: exp)
            }
            return nil
        }()

        return .valid(expiry: expiry, features: features)
    }

    // MARK: - Stored activation (code + UUID)

    /// The JSON stored in Keychain: `{"code":"...","uuid":"..."}`
    private struct StoredActivation: Codable {
        let code: String
        let uuid: String
    }

    /// Check if the app is currently activated (stored code is valid + UUID matches).
    static func isActivated() -> Bool {
        guard let storedJSON = KeychainStore.string(service: keychainService, account: keychainAccount),
              let data = storedJSON.data(using: .utf8),
              let activation = try? JSONDecoder().decode(StoredActivation.self, from: data) else { return false }

        // Verify code signature + expiry
        switch validateCode(activation.code) {
        case .valid: break
        default: return false
        }

        // Verify UUID matches this machine
        if let hw = hardwareUUID(), hw != activation.uuid { return false }

        return true
    }

    /// Activate with an activation code. Binds to current machine's UUID.
    @discardableResult
    static func activate(with code: String) -> Bool {
        switch validateCode(code) {
        case .valid:
            guard let uuid = hardwareUUID() else { return false }
            let activation = StoredActivation(code: code, uuid: uuid)
            if let data = try? JSONEncoder().encode(activation),
               let json = String(data: data, encoding: .utf8) {
                KeychainStore.setString(json, service: keychainService, account: keychainAccount)
                return true
            }
            return false
        default:
            return false
        }
    }

    /// Deactivate (clear stored key).
    static func deactivate() {
        KeychainStore.remove(service: keychainService, account: keychainAccount)
    }

    /// Return the stored activation info, if any.
    static func storedActivation() -> (code: String, uuid: String)? {
        guard let storedJSON = KeychainStore.string(service: keychainService, account: keychainAccount),
              let data = storedJSON.data(using: .utf8),
              let activation = try? JSONDecoder().decode(StoredActivation.self, from: data) else { return nil }
        return (activation.code, activation.uuid)
    }

    // MARK: - Base64URL helpers

    private static func base64URLDecode(_ s: String) -> Data? {
        var base64 = s.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - base64.count % 4) % 4
        base64 += String(repeating: "=", count: padding)
        return Data(base64Encoded: base64)
    }

    static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Activation code generation (Beta only)

    private static let keyPairDir: URL = {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".aurora-license-keypair")
    }()

    private static var privateKeyPemPath: URL {
        keyPairDir.appendingPathComponent("private_key.pem")
    }

    /// Check if a key pair exists on disk.
    static func keyPairExists() -> Bool {
        FileManager.default.fileExists(atPath: privateKeyPemPath.path)
    }

    /// Generate an activation code (not bound to any UUID).
    static func generateActivationCode(expiryDays: Int = 0) -> String? {
        guard let privateKeyData = try? Data(contentsOf: privateKeyPemPath) else { return nil }

        let pemString = String(data: privateKeyData, encoding: .utf8) ?? ""
        let base64 = pemString
            .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let derData = Data(base64Encoded: base64) else { return nil }
        guard let privateKey = try? P256.Signing.PrivateKey(derRepresentation: derData) else { return nil }

        // Random activation code
        let code = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16).uppercased()

        var payload: [String: Any] = ["code": code, "feat": 0]
        if expiryDays > 0 {
            payload["exp"] = Int(Date().timeIntervalSince1970) + (expiryDays * 86400)
        }
        guard let payloadData = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else { return nil }
        guard let signature = try? privateKey.signature(for: payloadData) else { return nil }

        let payloadB64 = base64URLEncode(payloadData)
        let sigB64 = base64URLEncode(signature.derRepresentation)
        return "AURORA-\(payloadB64)-\(sigB64)"
    }
}
