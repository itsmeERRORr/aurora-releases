import Foundation
import CryptoKit

enum AnalyticsService {

    private static let endpoint = "\(LicensingService.supabaseURL)/functions/v1/log-analytics"

    private static func userHash() -> String? {
        guard let uuid = LicensingService.hardwareUUID() else { return nil }
        let data = Data((uuid + "aurora-salt").utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func logStats(_ report: StatsReport) async {
        guard report.totalFilesAnalyzed > 0 else { return }
        guard !UserDefaults.standard.bool(forKey: "aurora.analyticsOptOut") else { return }
        guard let url = URL(string: endpoint) else { return }

        var shutterDict: [String: Int] = [:]
        for (speed, count) in report.shutterCounts {
            shutterDict[formatShutter(speed)] = count
        }

        var payload: [String: Any] = [
            "raws_imported": report.totalFilesAnalyzed,
            "iso":          report.isoCounts,
            "aperture":     report.apertureCounts,
            "focal":        report.focalCounts,
            "shutter":      shutterDict,
            "top_cameras":  topN(report.cameraCounts, n: 20),
            "top_lenses":   topN(report.lensCounts, n: 20),
        ]
        if let hash = userHash() { payload["user_hash"] = hash }

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }

        var req = URLRequest(url: url, timeoutInterval: 10)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(LicensingService.anonKey, forHTTPHeaderField: "apikey")
        req.httpBody = body

        _ = try? await URLSession.shared.data(for: req)
    }

    private static func topN(_ dict: [String: Int], n: Int) -> [String: Int] {
        var result: [String: Int] = [:]
        for (key, value) in dict.sorted(by: { $0.value > $1.value }).prefix(n) {
            result[key] = value
        }
        return result
    }

    private static func formatShutter(_ value: Double) -> String {
        if value >= 1 { return "\(Int(value))s" }
        let denom = Int((1.0 / value).rounded())
        return "1/\(denom)"
    }
}
