import Foundation

struct ImportRenameOptions: Sendable {
    let template: String
    let eventName: String
    let importDate: Date
    let totalCount: Int
    let captureDatesByPath: [String: Date]

    func destinationFileName(for sourceURL: URL, index: Int) -> String {
        let originalBase = sourceURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension
        let tokenDate = captureDatesByPath[sourceURL.path] ?? importDate
        let base = RenameTemplateRenderer.render(
            template: template,
            eventName: eventName,
            originalBaseName: originalBase,
            sequence: index + 1,
            totalCount: totalCount,
            date: tokenDate
        )
        let safeBase = RenameTemplateRenderer.sanitizedFilenameBase(base)
        let fallback = RenameTemplateRenderer.sanitizedFilenameBase(originalBase)
        let finalBase = safeBase.isEmpty ? fallback : safeBase
        return ext.isEmpty ? finalBase : "\(finalBase).\(ext)"
    }
}

enum RenameTemplateRenderer {
    static let defaultTemplate = "{date:yyyyMMdd}_{event}_{sequence:00001}_{filename}"

    static func usesDateTokens(_ template: String) -> Bool {
        template.contains("{date")
            || template.contains("{hour}")
            || template.contains("{minute}")
            || template.contains("{second}")
    }

    static func render(
        template: String,
        eventName: String,
        originalBaseName: String,
        sequence: Int,
        totalCount: Int,
        date: Date
    ) -> String {
        var result = template.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.isEmpty { result = defaultTemplate }

        result = replaceDateTokens(in: result, date: date)
        result = result.replacingOccurrences(of: "{hour}", with: dateString(date, format: "HH"))
        result = result.replacingOccurrences(of: "{minute}", with: dateString(date, format: "mm"))
        result = result.replacingOccurrences(of: "{second}", with: dateString(date, format: "ss"))
        result = result.replacingOccurrences(of: "{filename}", with: originalBaseName)
        result = result.replacingOccurrences(of: "{originalFilename}", with: originalBaseName)
        result = result.replacingOccurrences(of: "{copyName}", with: originalBaseName)
        result = result.replacingOccurrences(of: "{filenameNumberSuffix}", with: filenameNumberSuffix(originalBaseName))
        result = result.replacingOccurrences(of: "{originalNumberSuffix}", with: filenameNumberSuffix(originalBaseName))
        result = result.replacingOccurrences(of: "{event}", with: eventName)
        result = replaceSequenceTokens(in: result, sequence: sequence)
        result = replaceNumberTokens(in: result, prefix: "image", number: sequence)
        result = replaceNumberTokens(in: result, prefix: "total", number: totalCount)
        return result
    }

    static func preview(template: String, eventName: String) -> String {
        let base = render(
            template: template,
            eventName: eventName,
            originalBaseName: "DSC01234",
            sequence: 1,
            totalCount: 500,
            date: Date()
        )
        return "\(sanitizedFilenameBase(base)).ARW"
    }

    static func sanitizedFilenameBase(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\0")
        return value
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replaceDateTokens(in input: String, date: Date) -> String {
        replaceTokenPattern(in: input, prefix: "date", defaultValue: dateString(date, format: "yyyyMMdd")) { format in
            dateString(date, format: format.isEmpty ? "yyyyMMdd" : format)
        }
    }

    private static func replaceSequenceTokens(in input: String, sequence: Int) -> String {
        replaceNumberTokens(in: input, prefix: "sequence", number: sequence)
    }

    private static func replaceNumberTokens(in input: String, prefix: String, number: Int) -> String {
        replaceTokenPattern(in: input, prefix: prefix, defaultValue: String(number)) { pattern in
            let width = pattern.filter { $0 == "0" }.count
            guard width > 0 else { return String(number) }
            return String(format: "%0\(width)d", number)
        }
    }

    private static func replaceTokenPattern(
        in input: String,
        prefix: String,
        defaultValue: String,
        transform: (String) -> String
    ) -> String {
        var result = input.replacingOccurrences(of: "{\(prefix)}", with: defaultValue)
        let pattern = "\\{\(prefix):([^}]+)\\}"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return result }
        let range = NSRange(result.startIndex..<result.endIndex, in: result)
        let matches = regex.matches(in: result, range: range).reversed()
        for match in matches {
            guard let fullRange = Range(match.range(at: 0), in: result),
                  let valueRange = Range(match.range(at: 1), in: result) else { continue }
            result.replaceSubrange(fullRange, with: transform(String(result[valueRange])))
        }
        return result
    }

    private static func dateString(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    private static func filenameNumberSuffix(_ filename: String) -> String {
        let suffix = filename.reversed().prefix { $0.isNumber }.reversed()
        return String(suffix)
    }
}
