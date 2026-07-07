import Foundation
import CryptoKit

/// A privacy-preserving, stable-per-device identifier sent to the backend in
/// place of the raw hardware UUID. The server never learns the real UUID.
///
/// `SHA256(hardwareUUID + pepper)` — the same Mac always produces the same hash,
/// two different Macs produce different hashes, and the hash can't be reversed to
/// the UUID (a macOS `IOPlatformUUID` has ~122 bits of entropy). The pepper lives
/// in the binary: it makes the hash app-specific but is NOT an anti-cheat secret
/// (anyone reading this source can reproduce it) — its only job is privacy.
enum DeviceIdentity {
    private static let pepper = "aurora-device-id-v1"

    static func deviceHash() -> String? {
        guard let uuid = LicensingService.hardwareUUID() else { return nil }
        let digest = SHA256.hash(data: Data("\(uuid)|\(pepper)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
