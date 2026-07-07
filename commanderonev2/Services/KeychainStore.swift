import Foundation
import Security
import CryptoKit
import IOKit

// Stores app secrets in UserDefaults to avoid Keychain permission prompts on every
// Sparkle update (ad-hoc signed binaries lose Keychain trust after each update).
//
// Values are encrypted at rest with AES-GCM using a key derived from this Mac's
// hardware UUID, so the raw plist is not human-readable and a copy taken off the
// machine (Time Machine backup, another user, forensic dump) can't be decrypted on
// a different Mac. This is not a defense against code running as the same user on
// the same machine (it can derive the same key) — for that, secrets that gate
// access (the license cache) are additionally ECDSA-signed by the server.
enum KeychainStore {
    private static let encPrefix = "encv1:"

    private static func udKey(service: String, account: String) -> String {
        "aurora.store.\(service).\(account)"
    }

    static func string(service: String, account: String) -> String? {
        let key = udKey(service: service, account: account)

        if let stored = UserDefaults.standard.string(forKey: key) {
            return decryptIfNeeded(stored)
        }

        // One-time migration: pull from Keychain if it exists there, then move to
        // UserDefaults (encrypted at rest) and drop the old Keychain item.
        if let migrated = keychainRead(service: service, account: account) {
            setString(migrated, service: service, account: account)
            keychainDelete(service: service, account: account)
            return migrated
        }

        return nil
    }

    static func setString(_ value: String, service: String, account: String) {
        UserDefaults.standard.set(encrypt(value), forKey: udKey(service: service, account: account))
    }

    static func remove(service: String, account: String) {
        UserDefaults.standard.removeObject(forKey: udKey(service: service, account: account))
        keychainDelete(service: service, account: account)
    }

    // MARK: - At-rest encryption

    /// AES-GCM key derived from the hardware UUID. Falls back to a fixed constant if
    /// the UUID can't be read, so storage still works (just without the off-machine
    /// binding on that rare device).
    private static func encryptionKey() -> SymmetricKey {
        let seed = hardwareUUID() ?? "aurora-fallback-seed"
        let digest = SHA256.hash(data: Data((seed + "|aurora.store.key.v1").utf8))
        return SymmetricKey(data: Data(digest))
    }

    private static func encrypt(_ value: String) -> String {
        guard let sealed = try? AES.GCM.seal(Data(value.utf8), using: encryptionKey()),
              let combined = sealed.combined else {
            return value // extremely unlikely; degrade to plaintext rather than lose data
        }
        return encPrefix + combined.base64EncodedString()
    }

    private static func decryptIfNeeded(_ stored: String) -> String? {
        guard stored.hasPrefix(encPrefix) else {
            // Legacy plaintext value written before at-rest encryption existed. Return
            // it as-is; it gets re-encrypted the next time setString is called.
            return stored
        }
        let b64 = String(stored.dropFirst(encPrefix.count))
        guard let data = Data(base64Encoded: b64),
              let box = try? AES.GCM.SealedBox(combined: data),
              let plain = try? AES.GCM.open(box, using: encryptionKey()) else {
            return nil
        }
        return String(data: plain, encoding: .utf8)
    }

    // MARK: - Hardware UUID (local, self-contained)

    private static func hardwareUUID() -> String? {
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

    // MARK: - Keychain helpers (migration only)

    private static func keychainRead(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func keychainDelete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
