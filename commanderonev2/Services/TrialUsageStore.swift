import Foundation
import CryptoKit

struct TrialUsageState: Codable, Equatable {
    static let maxActions = 5

    var usedActions: Int = 0

    /// HMAC over `usedActions` + this Mac's hardware UUID. Detects hand-edited trial
    /// files (e.g. setting usedActions back to 0 in a text editor). Not present on
    /// files written before this check existed — those are trusted once, as-is.
    var integrityTag: String?

    var remainingActions: Int {
        max(0, Self.maxActions - usedActions)
    }

    var isExhausted: Bool {
        remainingActions == 0
    }
}

enum TrialUsageStore {
    private static var fileURL: URL {
        AppPaths.applicationSupportRoot.appendingPathComponent("trial_state.json")
    }

    // Pepper for the integrity HMAC. This lives in the app binary, so it only stops
    // casual/naive edits (opening the JSON and changing a number) — anyone reading
    // this source can reproduce it. Real tamper-resistance for a client-only trial
    // counter would require server-side tracking per hardware UUID; deleting the
    // file entirely still resets the trial and can't be prevented from the client.
    private static let integrityPepper = "aurora-trial-integrity-v1"

    private static func computeTag(usedActions: Int) -> String? {
        guard let uuid = LicensingService.hardwareUUID() else { return nil }
        let message = "\(usedActions)|\(uuid)|\(integrityPepper)"
        let key = SymmetricKey(data: Data(integrityPepper.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        return Data(mac).base64EncodedString()
    }

    static func load() -> TrialUsageState {
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? JSONDecoder().decode(TrialUsageState.self, from: data) else {
            return TrialUsageState()
        }
        if let tag = state.integrityTag, tag != computeTag(usedActions: state.usedActions) {
            // The tag exists but doesn't match — this file was hand-edited after the
            // check was introduced. Fail closed (treat as trial exhausted) rather
            // than reward the edit with a fresh trial.
            var exhausted = TrialUsageState()
            exhausted.usedActions = TrialUsageState.maxActions
            return exhausted
        }
        // Sanitize: a file with no integrity tag is trusted as-is (legacy path), so a
        // crafted value could otherwise be negative (→ effectively infinite actions)
        // or near Int.max (→ overflow trap when `usedActions + count` is evaluated).
        // The server sync reconciles the real count anyway; this just keeps the local
        // value in a sane, crash-proof range. usedActions may legitimately exceed
        // maxActions (offline over-use that the server later confirms), so we only cap
        // the far upper bound, not down to maxActions.
        var sanitized = state
        sanitized.usedActions = max(0, min(state.usedActions, 1_000_000))
        return sanitized
    }

    static func save(_ state: TrialUsageState) {
        var signed = state
        signed.integrityTag = computeTag(usedActions: state.usedActions)
        guard let data = try? JSONEncoder().encode(signed) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
