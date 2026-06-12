import Foundation

struct StatsReport: Equatable, Codable {
    var topLenses: [LensStat]
    var mostUsedCamera: CameraStat?
    var shutterSpeeds: [ShutterStat]
    var totalFilesAnalyzed: Int
    var rawOutput: String
    var avgISO: Double?
    var maxISO: Double?
    var minISO: Double?
    var avgAperture: Double?
    var maxAperture: Double?
    var minAperture: Double?
    var avgFocalLength: Double?
    var maxFocalLength: Double?
    var minFocalLength: Double?
    var totalBytes: Int64
    var totalDuration: Int
    var importCount: Int
    var firstImportDate: Date?

    var averageSpeed: Double {
        guard totalDuration > 0, totalBytes > 0 else { return 0 }
        return Double(totalBytes) / Double(totalDuration) // bytes per second
    }

    var avgShutterSpeed: Double? {
        guard !shutterCounts.isEmpty else { return nil }
        let totalWeight = shutterCounts.values.reduce(0, +)
        guard totalWeight > 0 else { return nil }
        let weightedSum = shutterCounts.reduce(0.0) { sum, pair in
            sum + (pair.key * Double(pair.value))
        }
        return weightedSum / Double(totalWeight)
    }

    func recalculatingISOFromRawOutput() -> StatsReport {
        guard let data = rawOutput.data(using: .utf8),
              let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return self
        }

        let values = entries.compactMap(Self.effectiveISO(from:))
        guard !values.isEmpty else { return self }

        var report = self
        report.isoSum = values.reduce(0, +)
        report.isoCount = values.count
        report.avgISO = report.isoSum / Double(values.count)
        report.maxISO = values.max()
        report.minISO = values.min()
        return report
    }

    private static func effectiveISO(from entry: [String: Any]) -> Double? {
        let candidates = [
            parseISOField(entry["ISO"]),
            parseISOField(entry["ISOSpeed"]),
            parseISOField(entry["RecommendedExposureIndex"]),
            parseISOField(entry["ISOSetting"]),
            parseISOField(entry["SonyISO"])
        ].compactMap { $0 }.filter { $0 > 0 }
        return candidates.max()
    }

    private static func parseISOField(_ value: Any?) -> Double? {
        if let i = value as? Int { return Double(i) }
        if let d = value as? Double { return d }
        if let array = value as? [Any] {
            return array.compactMap(parseISOField).max()
        }
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let direct = Double(trimmed.replacingOccurrences(of: ",", with: "")) {
            return direct
        }

        var token = ""
        for char in trimmed {
            if char.isNumber || char == "." || char == "," {
                token.append(char)
            } else if !token.isEmpty {
                break
            }
        }
        return Double(token.replacingOccurrences(of: ",", with: ""))
    }

    var allCameras: [CameraStat] {
        let sorted = cameraCounts.sorted { $0.value > $1.value }
        return sorted.map { key, count in
            let parts = key.split(separator: "|", maxSplits: 1)
            return CameraStat(
                make: String(parts.first ?? ""),
                model: String(parts.last ?? ""),
                count: count
            )
        }
    }

    var allLenses: [LensStat] {
        // Filter out no-lens entries (e.g. "Sony ---") at display time so
        // historical accumulated data is also cleaned up.
        let isNoLens: (String) -> Bool = { str in
            let trimmed = str.trimmingCharacters(in: .whitespaces)
            return !trimmed.isEmpty && trimmed.allSatisfy { $0 == "-" }
        }
        let sorted = lensCounts
            .filter { pair in
                let parts = pair.key.split(separator: "|", maxSplits: 1)
                let model = String(parts.last ?? Substring(pair.key))
                return !isNoLens(model)
            }
            .sorted { $0.value > $1.value }
        return sorted.enumerated().map { idx, pair in
            let parts = pair.key.split(separator: "|", maxSplits: 1)
            return LensStat(
                make: String(parts.first ?? ""),
                model: String(parts.last ?? ""),
                count: pair.value,
                rank: idx + 1
            )
        }
    }

    // Internal data for accumulation
    var lensCounts: [String: Int]
    var cameraCounts: [String: Int]
    var shutterCounts: [Double: Int]
    var isoCounts: [String: Int]
    var apertureCounts: [String: Int]
    var focalCounts: [String: Int]
    var orientationCounts: [String: Int]
    var maxShutterSpeed: Double?
    var minShutterSpeed: Double?
    var isoSum: Double
    var isoCount: Int
    var apertureSum: Double
    var apertureCount: Int
    var focalSum: Double
    var focalCount: Int
    var monthCounts: [String: Int] // "MMM yyyy" -> count
    var weekCounts: [String: Int] // "YYYY-Www" -> count
    var yearCounts: [String: Int] // "YYYY" -> count

    init(
        topLenses: [LensStat],
        mostUsedCamera: CameraStat?,
        shutterSpeeds: [ShutterStat],
        totalFilesAnalyzed: Int,
        rawOutput: String,
        avgISO: Double?,
        maxISO: Double? = nil,
        minISO: Double? = nil,
        avgAperture: Double?,
        maxAperture: Double? = nil,
        minAperture: Double? = nil,
        avgFocalLength: Double?,
        maxFocalLength: Double? = nil,
        minFocalLength: Double? = nil,
        totalBytes: Int64 = 0,
        totalDuration: Int = 0,
        importCount: Int = 1,
        firstImportDate: Date? = nil,
        lensCounts: [String: Int] = [:],
        cameraCounts: [String: Int] = [:],
        shutterCounts: [Double: Int] = [:],
        isoCounts: [String: Int] = [:],
        apertureCounts: [String: Int] = [:],
        focalCounts: [String: Int] = [:],
        orientationCounts: [String: Int] = [:],
        maxShutterSpeed: Double? = nil,
        minShutterSpeed: Double? = nil,
        isoSum: Double = 0,
        isoCount: Int = 0,
        apertureSum: Double = 0,
        apertureCount: Int = 0,
        focalSum: Double = 0,
        focalCount: Int = 0,
        monthCounts: [String: Int] = [:],
        weekCounts: [String: Int] = [:],
        yearCounts: [String: Int] = [:]
    ) {
        self.topLenses = topLenses
        self.mostUsedCamera = mostUsedCamera
        self.shutterSpeeds = shutterSpeeds
        self.totalFilesAnalyzed = totalFilesAnalyzed
        self.rawOutput = rawOutput
        self.avgISO = avgISO
        self.maxISO = maxISO
        self.minISO = minISO
        self.avgAperture = avgAperture
        self.maxAperture = maxAperture
        self.minAperture = minAperture
        self.avgFocalLength = avgFocalLength
        self.maxFocalLength = maxFocalLength
        self.minFocalLength = minFocalLength
        self.totalBytes = totalBytes
        self.totalDuration = totalDuration
        self.importCount = importCount
        self.firstImportDate = firstImportDate
        self.lensCounts = lensCounts
        self.cameraCounts = cameraCounts
        self.shutterCounts = shutterCounts
        self.isoCounts = isoCounts
        self.apertureCounts = apertureCounts
        self.focalCounts = focalCounts
        self.orientationCounts = orientationCounts
        self.maxShutterSpeed = maxShutterSpeed
        self.minShutterSpeed = minShutterSpeed
        self.isoSum = isoSum
        self.isoCount = isoCount
        self.apertureSum = apertureSum
        self.apertureCount = apertureCount
        self.focalSum = focalSum
        self.focalCount = focalCount
        self.monthCounts = monthCounts
        self.weekCounts = weekCounts
        self.yearCounts = yearCounts
    }

    var mostUsedISO: Double? {
        mostUsedNumericKey(in: isoCounts)
    }

    var mostUsedAperture: Double? {
        mostUsedNumericKey(in: apertureCounts)
    }

    var mostUsedFocalLength: Double? {
        mostUsedNumericKey(in: focalCounts)
    }

    var mostUsedShutterSpeed: Double? {
        shutterCounts.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return lhs.key < rhs.key
        }.first?.key
    }

    private func mostUsedNumericKey(in counts: [String: Int]) -> Double? {
        counts.compactMap { key, count -> (value: Double, count: Int)? in
            guard let value = Double(key), value > 0 else { return nil }
            return (value, count)
        }
        .sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.value < rhs.value
        }
        .first?.value
    }

    var portraitCount: Int {
        orientationCounts["portrait", default: 0]
    }

    var landscapeCount: Int {
        orientationCounts["landscape", default: 0]
    }

    struct LensStat: Equatable, Identifiable, Codable {
        let id: UUID
        let make: String
        let model: String
        let count: Int
        let rank: Int

        init(make: String, model: String, count: Int, rank: Int) {
            self.id = UUID()
            self.make = make
            self.model = model
            self.count = count
            self.rank = rank
        }

        var fullName: String {
            let brand = inferredBrand(from: model, fallback: make)
            let cleanModel = stripBrandPrefix(model, brand: brand)
            return "\(brand) \(cleanModel)".trimmingCharacters(in: .whitespaces)
        }

        var medal: String {
            switch rank {
            case 1: return "🥇"
            case 2: return "🥈"
            case 3: return "🥉"
            default: return ""
            }
        }

        private func inferredBrand(from model: String, fallback: String) -> String {
            let upper = model.uppercased()

            if upper.contains("SAMYANG") { return "Samyang" }
            if upper.contains("SIGMA") || upper.contains(" DG DN ") || upper.contains("| ART") || upper.contains(" ART ") { return "Sigma" }
            if upper.contains("TAMRON") { return "Tamron" }
            if upper.contains("ZEISS") { return "Zeiss" }
            if upper.contains("VOIGTLANDER") { return "Voigtlander" }
            if upper.contains("TOKINA") { return "Tokina" }
            if upper.contains("LAOWA") { return "Laowa" }
            if upper.contains("VILTROX") { return "Viltrox" }
            if upper.contains("TTARTISAN") { return "TTArtisan" }
            if upper.contains("7ARTISANS") { return "7Artisans" }
            if upper.contains("MEIKE") { return "Meike" }

            return fallback
        }

        private func stripBrandPrefix(_ model: String, brand: String) -> String {
            let trimmed = model.trimmingCharacters(in: .whitespaces)
            let upperModel = trimmed.uppercased()
            let upperBrand = brand.uppercased()

            if upperModel.hasPrefix(upperBrand + " ") {
                return String(trimmed.dropFirst(upperBrand.count + 1))
            }
            return trimmed
        }
    }

    struct CameraStat: Equatable, Codable {
        let make: String
        let model: String
        let count: Int

        var fullName: String { "\(make) \(model)" }
    }

    struct ShutterStat: Equatable, Identifiable, Codable {
        let id: UUID
        let rawValue: Double
        let count: Int

        init(rawValue: Double, count: Int) {
            self.id = UUID()
            self.rawValue = rawValue
            self.count = count
        }

        var fractionString: String {
            if rawValue >= 1 {
                return "\(String(format: "%.1f", rawValue))s"
            }
            let denominator = Int(round(1.0 / rawValue))
            return "1/\(denominator)s"
        }
    }

    // MARK: - Custom Codable for [Double: Int] shutterCounts

    enum CodingKeys: String, CodingKey {
        case topLenses, mostUsedCamera, shutterSpeeds, totalFilesAnalyzed, rawOutput
        case avgISO, maxISO, minISO
        case avgAperture, maxAperture, minAperture
        case avgFocalLength, maxFocalLength, minFocalLength
        case totalBytes, totalDuration, importCount, firstImportDate
        case lensCounts, cameraCounts, shutterCounts, isoCounts, apertureCounts, focalCounts, orientationCounts, maxShutterSpeed, minShutterSpeed
        case isoSum, isoCount, apertureSum, apertureCount, focalSum, focalCount, monthCounts, weekCounts, yearCounts
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(topLenses, forKey: .topLenses)
        try container.encodeIfPresent(mostUsedCamera, forKey: .mostUsedCamera)
        try container.encode(shutterSpeeds, forKey: .shutterSpeeds)
        try container.encode(totalFilesAnalyzed, forKey: .totalFilesAnalyzed)
        try container.encode(rawOutput, forKey: .rawOutput)
        try container.encodeIfPresent(avgISO, forKey: .avgISO)
        try container.encodeIfPresent(maxISO, forKey: .maxISO)
        try container.encodeIfPresent(minISO, forKey: .minISO)
        try container.encodeIfPresent(avgAperture, forKey: .avgAperture)
        try container.encodeIfPresent(maxAperture, forKey: .maxAperture)
        try container.encodeIfPresent(minAperture, forKey: .minAperture)
        try container.encodeIfPresent(avgFocalLength, forKey: .avgFocalLength)
        try container.encodeIfPresent(maxFocalLength, forKey: .maxFocalLength)
        try container.encodeIfPresent(minFocalLength, forKey: .minFocalLength)
        try container.encode(totalBytes, forKey: .totalBytes)
        try container.encode(totalDuration, forKey: .totalDuration)
        try container.encode(importCount, forKey: .importCount)
        try container.encodeIfPresent(firstImportDate, forKey: .firstImportDate)
        try container.encode(lensCounts, forKey: .lensCounts)
        try container.encode(cameraCounts, forKey: .cameraCounts)
        // Encode [Double: Int] as [String: Int]
        let stringKeyedShutter = Dictionary(uniqueKeysWithValues: shutterCounts.map { (String($0.key), $0.value) })
        try container.encode(stringKeyedShutter, forKey: .shutterCounts)
        try container.encode(isoCounts, forKey: .isoCounts)
        try container.encode(apertureCounts, forKey: .apertureCounts)
        try container.encode(focalCounts, forKey: .focalCounts)
        try container.encode(orientationCounts, forKey: .orientationCounts)
        try container.encodeIfPresent(maxShutterSpeed, forKey: .maxShutterSpeed)
        try container.encodeIfPresent(minShutterSpeed, forKey: .minShutterSpeed)
        try container.encode(isoSum, forKey: .isoSum)
        try container.encode(isoCount, forKey: .isoCount)
        try container.encode(apertureSum, forKey: .apertureSum)
        try container.encode(apertureCount, forKey: .apertureCount)
        try container.encode(focalSum, forKey: .focalSum)
        try container.encode(focalCount, forKey: .focalCount)
        try container.encode(monthCounts, forKey: .monthCounts)
        try container.encode(weekCounts, forKey: .weekCounts)
        try container.encode(yearCounts, forKey: .yearCounts)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        topLenses = try container.decode([LensStat].self, forKey: .topLenses)
        mostUsedCamera = try container.decodeIfPresent(CameraStat.self, forKey: .mostUsedCamera)
        shutterSpeeds = try container.decode([ShutterStat].self, forKey: .shutterSpeeds)
        totalFilesAnalyzed = try container.decode(Int.self, forKey: .totalFilesAnalyzed)
        rawOutput = try container.decode(String.self, forKey: .rawOutput)
        avgISO = try container.decodeIfPresent(Double.self, forKey: .avgISO)
        maxISO = try container.decodeIfPresent(Double.self, forKey: .maxISO)
        minISO = try container.decodeIfPresent(Double.self, forKey: .minISO)
        avgAperture = try container.decodeIfPresent(Double.self, forKey: .avgAperture)
        maxAperture = try container.decodeIfPresent(Double.self, forKey: .maxAperture)
        minAperture = try container.decodeIfPresent(Double.self, forKey: .minAperture)
        avgFocalLength = try container.decodeIfPresent(Double.self, forKey: .avgFocalLength)
        maxFocalLength = try container.decodeIfPresent(Double.self, forKey: .maxFocalLength)
        minFocalLength = try container.decodeIfPresent(Double.self, forKey: .minFocalLength)
        totalBytes = try container.decodeIfPresent(Int64.self, forKey: .totalBytes) ?? 0
        totalDuration = try container.decodeIfPresent(Int.self, forKey: .totalDuration) ?? 0
        importCount = try container.decodeIfPresent(Int.self, forKey: .importCount) ?? 1
        firstImportDate = try container.decodeIfPresent(Date.self, forKey: .firstImportDate)
        lensCounts = try container.decodeIfPresent([String: Int].self, forKey: .lensCounts) ?? [:]
        cameraCounts = try container.decodeIfPresent([String: Int].self, forKey: .cameraCounts) ?? [:]
        // Decode [String: Int] back to [Double: Int], with fallback for old array format
        if let stringKeyedShutter = try container.decodeIfPresent([String: Int].self, forKey: .shutterCounts) {
            shutterCounts = Dictionary(uniqueKeysWithValues: stringKeyedShutter.compactMap { key, value in
                guard let d = Double(key) else { return nil }
                return (d, value)
            })
        } else {
            // Old data may have stored shutterCounts as an array — discard it
            shutterCounts = [:]
        }
        isoCounts = try container.decodeIfPresent([String: Int].self, forKey: .isoCounts) ?? [:]
        apertureCounts = try container.decodeIfPresent([String: Int].self, forKey: .apertureCounts) ?? [:]
        focalCounts = try container.decodeIfPresent([String: Int].self, forKey: .focalCounts) ?? [:]
        orientationCounts = try container.decodeIfPresent([String: Int].self, forKey: .orientationCounts) ?? [:]
        maxShutterSpeed = try container.decodeIfPresent(Double.self, forKey: .maxShutterSpeed)
        minShutterSpeed = try container.decodeIfPresent(Double.self, forKey: .minShutterSpeed)
        isoSum = try container.decodeIfPresent(Double.self, forKey: .isoSum) ?? 0
        isoCount = try container.decodeIfPresent(Int.self, forKey: .isoCount) ?? 0
        apertureSum = try container.decodeIfPresent(Double.self, forKey: .apertureSum) ?? 0
        apertureCount = try container.decodeIfPresent(Int.self, forKey: .apertureCount) ?? 0
        focalSum = try container.decodeIfPresent(Double.self, forKey: .focalSum) ?? 0
        focalCount = try container.decodeIfPresent(Int.self, forKey: .focalCount) ?? 0
        monthCounts = try container.decodeIfPresent([String: Int].self, forKey: .monthCounts) ?? [:]
        weekCounts = try container.decodeIfPresent([String: Int].self, forKey: .weekCounts) ?? [:]
        yearCounts = try container.decodeIfPresent([String: Int].self, forKey: .yearCounts) ?? [:]
    }

    // MARK: - Accumulation

    static func combine(_ report1: StatsReport?, _ report2: StatsReport) -> StatsReport {
        guard let report1 = report1 else { return report2 }

        // Combine counts
        var combinedLensCounts = report1.lensCounts
        for (lens, count) in report2.lensCounts {
            combinedLensCounts[lens, default: 0] += count
        }

        // Filter out "no lens" entries (Sony - - - or similar)
        let isNoLens: (String) -> Bool = { key in
            let parts = key.split(separator: "|", maxSplits: 1)
            guard parts.count == 2 else { return false }
            let model = String(parts.last ?? "").trimmingCharacters(in: .whitespaces)
            return !model.isEmpty && model.allSatisfy { $0 == "-" }
        }
        combinedLensCounts = combinedLensCounts.filter { !isNoLens($0.key) }

        var combinedCameraCounts = report1.cameraCounts
        for (camera, count) in report2.cameraCounts {
            combinedCameraCounts[camera, default: 0] += count
        }

        var combinedShutterCounts = report1.shutterCounts
        for (shutter, count) in report2.shutterCounts {
            combinedShutterCounts[shutter, default: 0] += count
        }

        var combinedISOCounts = report1.isoCounts
        for (iso, count) in report2.isoCounts {
            combinedISOCounts[iso, default: 0] += count
        }

        var combinedApertureCounts = report1.apertureCounts
        for (aperture, count) in report2.apertureCounts {
            combinedApertureCounts[aperture, default: 0] += count
        }

        var combinedFocalCounts = report1.focalCounts
        for (focal, count) in report2.focalCounts {
            combinedFocalCounts[focal, default: 0] += count
        }

        var combinedOrientationCounts = report1.orientationCounts
        for (orientation, count) in report2.orientationCounts {
            combinedOrientationCounts[orientation, default: 0] += count
        }

        var combinedMonthCounts = report1.monthCounts
        for (month, count) in report2.monthCounts {
            combinedMonthCounts[month, default: 0] += count
        }

        var combinedWeekCounts = report1.weekCounts
        for (week, count) in report2.weekCounts {
            combinedWeekCounts[week, default: 0] += count
        }

        var combinedYearCounts = report1.yearCounts
        for (year, count) in report2.yearCounts {
            combinedYearCounts[year, default: 0] += count
        }

        // Combine sums
        let combinedIsoSum = report1.isoSum + report2.isoSum
        let combinedIsoCount = report1.isoCount + report2.isoCount
        let combinedApertureSum = report1.apertureSum + report2.apertureSum
        let combinedApertureCount = report1.apertureCount + report2.apertureCount
        let combinedFocalSum = report1.focalSum + report2.focalSum
        let combinedFocalCount = report1.focalCount + report2.focalCount

        // Recalculate top lenses
        let sortedLenses = combinedLensCounts.sorted { $0.value > $1.value }
        let topLenses = sortedLenses.prefix(3).enumerated().map { idx, pair in
            let parts = pair.key.split(separator: "|", maxSplits: 1)
            return LensStat(
                make: String(parts.first ?? ""),
                model: String(parts.last ?? ""),
                count: pair.value,
                rank: idx + 1
            )
        }

        // Recalculate most used camera
        let topCamera = combinedCameraCounts.max(by: { $0.value < $1.value })
        let cameraStat: CameraStat?
        if let topCamera {
            let parts = topCamera.key.split(separator: "|", maxSplits: 1)
            cameraStat = CameraStat(
                make: String(parts.first ?? ""),
                model: String(parts.last ?? ""),
                count: topCamera.value
            )
        } else {
            cameraStat = nil
        }

        // Recalculate top shutters
        let sortedShutters = combinedShutterCounts.sorted { $0.value > $1.value }
        let topShutters = sortedShutters.prefix(5).map { pair in
            ShutterStat(rawValue: pair.key, count: pair.value)
        }

        // Recalculate averages
        let avgISO = combinedIsoCount > 0 ? combinedIsoSum / Double(combinedIsoCount) : nil
        let avgAperture = combinedApertureCount > 0 ? combinedApertureSum / Double(combinedApertureCount) : nil
        let avgFocalLength = combinedFocalCount > 0 ? combinedFocalSum / Double(combinedFocalCount) : nil

        // Combine max/min values (filter out zeros)
        let maxISO = [report1.maxISO, report2.maxISO].compactMap { $0 }.max()
        let minISO = [report1.minISO, report2.minISO].compactMap { $0 }.min()
        let maxAperture = [report1.maxAperture, report2.maxAperture].compactMap { $0 }.max()
        let minAperture = [report1.minAperture, report2.minAperture].compactMap { $0 }.filter { $0 > 0 }.min()
        let maxFocalLength = [report1.maxFocalLength, report2.maxFocalLength].compactMap { $0 }.max()
        let minFocalLength = [report1.minFocalLength, report2.minFocalLength].compactMap { $0 }.filter { $0 > 0 }.min()
        let maxShutterSpeed = [report1.maxShutterSpeed, report2.maxShutterSpeed].compactMap { $0 }.max()
        let minShutterSpeed = [report1.minShutterSpeed, report2.minShutterSpeed].compactMap { $0 }.min()

        // Preserve the earliest known import date
        let firstImportDate: Date? = [report1.firstImportDate, report2.firstImportDate]
            .compactMap { $0 }.min()

        return StatsReport(
            topLenses: topLenses,
            mostUsedCamera: cameraStat,
            shutterSpeeds: topShutters,
            totalFilesAnalyzed: report1.totalFilesAnalyzed + report2.totalFilesAnalyzed,
            rawOutput: "Combined stats from \(report1.totalFilesAnalyzed + report2.totalFilesAnalyzed) files",
            avgISO: avgISO,
            maxISO: maxISO,
            minISO: minISO,
            avgAperture: avgAperture,
            maxAperture: maxAperture,
            minAperture: minAperture,
            avgFocalLength: avgFocalLength,
            maxFocalLength: maxFocalLength,
            minFocalLength: minFocalLength,
            totalBytes: report1.totalBytes + report2.totalBytes,
            totalDuration: report1.totalDuration + report2.totalDuration,
            importCount: report1.importCount + report2.importCount,
            firstImportDate: firstImportDate,
            lensCounts: combinedLensCounts,
            cameraCounts: combinedCameraCounts,
            shutterCounts: combinedShutterCounts,
            isoCounts: combinedISOCounts,
            apertureCounts: combinedApertureCounts,
            focalCounts: combinedFocalCounts,
            orientationCounts: combinedOrientationCounts,
            maxShutterSpeed: maxShutterSpeed,
            minShutterSpeed: minShutterSpeed,
            isoSum: combinedIsoSum,
            isoCount: combinedIsoCount,
            apertureSum: combinedApertureSum,
            apertureCount: combinedApertureCount,
            focalSum: combinedFocalSum,
            focalCount: combinedFocalCount,
            monthCounts: combinedMonthCounts,
            weekCounts: combinedWeekCounts,
            yearCounts: combinedYearCounts
        )
    }

    func removing(_ removed: StatsReport) -> StatsReport? {
        let remainingFileCount = max(0, totalFilesAnalyzed - removed.totalFilesAnalyzed)
        guard remainingFileCount > 0 else { return nil }

        let remainingLensCounts = Self.subtractCounts(lensCounts, removing: removed.lensCounts)
            .filter { !Self.isNoLensKey($0.key) }
        let remainingCameraCounts = Self.subtractCounts(cameraCounts, removing: removed.cameraCounts)
        let remainingShutterCounts = Self.subtractCounts(shutterCounts, removing: removed.shutterCounts)
        let remainingISOCounts = Self.subtractCounts(isoCounts, removing: removed.isoCounts)
        let remainingApertureCounts = Self.subtractCounts(apertureCounts, removing: removed.apertureCounts)
        let remainingFocalCounts = Self.subtractCounts(focalCounts, removing: removed.focalCounts)
        let remainingOrientationCounts = Self.subtractCounts(orientationCounts, removing: removed.orientationCounts)
        let remainingMonthCounts = Self.subtractCounts(monthCounts, removing: removed.monthCounts)
        let remainingWeekCounts = Self.subtractCounts(weekCounts, removing: removed.weekCounts)
        let remainingYearCounts = Self.subtractCounts(yearCounts, removing: removed.yearCounts)

        let remainingIsoSum = max(0, isoSum - removed.isoSum)
        let remainingIsoCount = max(0, isoCount - removed.isoCount)
        let remainingApertureSum = max(0, apertureSum - removed.apertureSum)
        let remainingApertureCount = max(0, apertureCount - removed.apertureCount)
        let remainingFocalSum = max(0, focalSum - removed.focalSum)
        let remainingFocalCount = max(0, focalCount - removed.focalCount)

        return StatsReport(
            topLenses: Self.topLenses(from: remainingLensCounts),
            mostUsedCamera: Self.topCamera(from: remainingCameraCounts),
            shutterSpeeds: Self.topShutters(from: remainingShutterCounts),
            totalFilesAnalyzed: remainingFileCount,
            rawOutput: "Adjusted stats from \(remainingFileCount) files",
            avgISO: remainingIsoCount > 0 ? remainingIsoSum / Double(remainingIsoCount) : nil,
            maxISO: Self.numericMaximum(in: remainingISOCounts),
            minISO: Self.numericMinimum(in: remainingISOCounts),
            avgAperture: remainingApertureCount > 0 ? remainingApertureSum / Double(remainingApertureCount) : nil,
            maxAperture: Self.numericMaximum(in: remainingApertureCounts),
            minAperture: Self.numericMinimum(in: remainingApertureCounts),
            avgFocalLength: remainingFocalCount > 0 ? remainingFocalSum / Double(remainingFocalCount) : nil,
            maxFocalLength: Self.numericMaximum(in: remainingFocalCounts),
            minFocalLength: Self.numericMinimum(in: remainingFocalCounts),
            totalBytes: max(0, totalBytes - removed.totalBytes),
            totalDuration: max(0, totalDuration - removed.totalDuration),
            importCount: max(0, importCount - removed.importCount),
            firstImportDate: firstImportDate,
            lensCounts: remainingLensCounts,
            cameraCounts: remainingCameraCounts,
            shutterCounts: remainingShutterCounts,
            isoCounts: remainingISOCounts,
            apertureCounts: remainingApertureCounts,
            focalCounts: remainingFocalCounts,
            orientationCounts: remainingOrientationCounts,
            maxShutterSpeed: remainingShutterCounts.keys.max(),
            minShutterSpeed: remainingShutterCounts.keys.min(),
            isoSum: remainingIsoSum,
            isoCount: remainingIsoCount,
            apertureSum: remainingApertureSum,
            apertureCount: remainingApertureCount,
            focalSum: remainingFocalSum,
            focalCount: remainingFocalCount,
            monthCounts: remainingMonthCounts,
            weekCounts: remainingWeekCounts,
            yearCounts: remainingYearCounts
        )
    }

    private static func subtractCounts<Key: Hashable>(_ counts: [Key: Int], removing removed: [Key: Int]) -> [Key: Int] {
        var result = counts
        for (key, removedCount) in removed {
            let remaining = result[key, default: 0] - removedCount
            if remaining > 0 {
                result[key] = remaining
            } else {
                result.removeValue(forKey: key)
            }
        }
        return result
    }

    private static func topLenses(from counts: [String: Int]) -> [LensStat] {
        counts
            .filter { !isNoLensKey($0.key) }
            .sorted { $0.value > $1.value }
            .prefix(3)
            .enumerated()
            .map { idx, pair in
                let parts = pair.key.split(separator: "|", maxSplits: 1)
                return LensStat(
                    make: String(parts.first ?? ""),
                    model: String(parts.last ?? ""),
                    count: pair.value,
                    rank: idx + 1
                )
            }
    }

    private static func topCamera(from counts: [String: Int]) -> CameraStat? {
        guard let topCamera = counts.max(by: { $0.value < $1.value }) else { return nil }
        let parts = topCamera.key.split(separator: "|", maxSplits: 1)
        return CameraStat(
            make: String(parts.first ?? ""),
            model: String(parts.last ?? ""),
            count: topCamera.value
        )
    }

    private static func topShutters(from counts: [Double: Int]) -> [ShutterStat] {
        counts
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { ShutterStat(rawValue: $0.key, count: $0.value) }
    }

    private static func numericMaximum(in counts: [String: Int]) -> Double? {
        counts.keys.compactMap(Double.init).filter { $0 > 0 }.max()
    }

    private static func numericMinimum(in counts: [String: Int]) -> Double? {
        counts.keys.compactMap(Double.init).filter { $0 > 0 }.min()
    }

    private static func isNoLensKey(_ key: String) -> Bool {
        let parts = key.split(separator: "|", maxSplits: 1)
        guard parts.count == 2 else { return false }
        let model = String(parts.last ?? "").trimmingCharacters(in: .whitespaces)
        return !model.isEmpty && model.allSatisfy { $0 == "-" }
    }
}
