import Foundation

enum AuroraFormat {
    private static let mediumDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private static let compactDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d yyyy"
        return f
    }()

    /// Formats a byte count as a two-part tuple: ("3.62", "TB").
    /// Threshold rules tuned to match the handoff sample data.
    static func bytesParts(_ bytes: Int64) -> (value: String, unit: String) {
        let b = Double(bytes)
        let kb = 1024.0
        let mb = kb * 1024
        let gb = mb * 1024
        let tb = gb * 1024

        if b >= tb { return (format(b / tb), "TB") }
        if b >= gb { return (format(b / gb), "GB") }
        if b >= mb { return (format(b / mb), "MB") }
        if b >= kb { return (format(b / kb), "KB") }
        return ("\(Int(b))", "B")
    }

    /// Speed bytes-per-second → two-part tuple ("886.1", "MB/s").
    static func speedParts(_ bps: Double) -> (value: String, unit: String) {
        let mbps = bps / (1024 * 1024)
        if mbps >= 1024 {
            return (format(mbps / 1024), "GB/s")
        }
        if mbps >= 1 {
            return (format(mbps), "MB/s")
        }
        return (format(bps / 1024), "KB/s")
    }

    /// Duration seconds → compact "1h 47m" / "38m" / "12s".
    static func durationParts(_ seconds: Int) -> (value: String, unit: String) {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            // "1h 47m" → value "1h 47", unit "m" doesn't read well; keep value joined and unit empty.
            return ("\(h)h \(m)", "m")
        }
        if m > 0 {
            return ("\(m)", "m")
        }
        return ("\(s)", "s")
    }

    /// Photo count with thin space thousands separator (e.g. "151 495").
    static func count(_ n: Int) -> String {
        let sign = n < 0 ? "-" : ""
        let digits = String(abs(n)).reversed()
        var grouped: [Character] = []
        grouped.reserveCapacity(digits.count + digits.count / 3)
        for (index, char) in digits.enumerated() {
            if index > 0, index % 3 == 0 {
                grouped.append("\u{2009}")
            }
            grouped.append(char)
        }
        return sign + String(grouped.reversed())
    }

    static func aperture(_ v: Double) -> String {
        if v <= 0 { return "—" }
        return String(format: "f/%.1f", v)
    }

    static func focal(_ v: Double) -> String {
        if v <= 0 { return "—" }
        return "\(Int(v.rounded()))mm"
    }

    /// Shutter in seconds → "1/400s" or "1.5s".
    static func shutter(_ v: Double) -> String {
        if v <= 0 { return "—" }
        if v >= 1 { return String(format: "%.1fs", v) }
        let denom = Int((1.0 / v).rounded())
        return "1/\(denom)s"
    }

    static func iso(_ v: Double) -> String {
        if v <= 0 { return "—" }
        return "\(Int(v.rounded()))"
    }

    /// "May 11, 2026"
    static func dateMedium(_ date: Date) -> String {
        mediumDateFormatter.string(from: date)
    }

    /// "May 11"
    static func dateShort(_ date: Date) -> String {
        shortDateFormatter.string(from: date)
    }

    /// "May 11 2026"
    static func dateCompact(_ date: Date) -> String {
        compactDateFormatter.string(from: date)
    }

    /// "May 9 — May 11, 2026"
    static func dateRange(_ start: Date, _ end: Date) -> String {
        let endStr = dateMedium(end)
        if Calendar.current.isDate(start, inSameDayAs: end) {
            return endStr
        }
        return "\(shortDateFormatter.string(from: start)) — \(endStr)"
    }

    private static func format(_ d: Double) -> String {
        if d >= 100 { return String(format: "%.0f", d) }
        if d >= 10 { return String(format: "%.1f", d) }
        return String(format: "%.2f", d)
    }
}
