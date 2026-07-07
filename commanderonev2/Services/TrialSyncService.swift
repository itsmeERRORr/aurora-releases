import Foundation

/// Syncs the local trial counter with the `trial-sync` Supabase Edge Function.
///
/// The server keeps the authoritative count keyed by the hashed device id. The
/// reconciliation rule is `max(local, server)` applied on both ends, so:
///   - deleting/editing the local file is corrected up to the server count on the
///     next online sync (the server never forgets),
///   - a forged low server response can't lower the local count (hence no need to
///     sign the response),
///   - offline usage still works (the client increments locally and pushes later).
enum TrialSyncService {

    /// Pushes the local `usedActions` and returns the server's authoritative count
    /// (`max(existing, local)`), or `nil` on any failure (offline, error) — callers
    /// keep their local value in that case.
    static func sync(localUsed: Int) async -> Int? {
        guard let deviceHash = DeviceIdentity.deviceHash() else { return nil }
        guard let url = URL(string: "\(LicensingService.supabaseURL)/functions/v1/trial-sync") else { return nil }

        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(LicensingService.anonKey, forHTTPHeaderField: "apikey")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "device_hash": deviceHash,
            "used_actions": localUsed,
        ])

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let serverUsed = json["used_actions"] as? Int else {
                return nil
            }
            return serverUsed
        } catch {
            return nil
        }
    }
}
