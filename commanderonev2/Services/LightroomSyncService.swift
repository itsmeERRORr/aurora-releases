import AppKit
import Foundation

struct LightroomSyncRequest: Codable {
    let id: String
    let eventName: String
    let importFolder: String
    let recursive: Bool
    let createdAt: String
}

enum LightroomSyncService {
    static func writePendingRequest(eventName: String, importFolder: String) throws -> URL {
        let request = LightroomSyncRequest(
            id: UUID().uuidString,
            eventName: eventName,
            importFolder: importFolder,
            recursive: false,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(request)
        let fileName = "\(request.id).json"
        let primaryURL = try writePendingRequestData(data, fileName: fileName, root: lightroomAppDataSyncRoot())
        return primaryURL
    }

    static func openLightroom(appPath: String?) {
        if let appPath,
           !appPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let url = URL(fileURLWithPath: appPath)
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            return
        }

        if let defaultURL = defaultLightroomURL() {
            NSWorkspace.shared.openApplication(at: defaultURL, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    static func defaultLightroomURL() -> URL? {
        let candidates = [
            "/Applications/Adobe Lightroom Classic/Adobe Lightroom Classic.app",
            "/Applications/Adobe Lightroom Classic.app",
            "/Applications/Lightroom Classic.app"
        ]
        return candidates.map(URL.init(fileURLWithPath:)).first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Activates Lightroom Classic and clicks the Aurora Sync plug-in menu command
    /// (File ▸ Plug-in Extras ▸ "Import Aurora Photos Now") via System Events UI
    /// scripting, so the pending import is pulled into the catalog automatically.
    ///
    /// Requires macOS Automation permission (the user is prompted on first use).
    /// `afterDelay` gives Lightroom a moment to come to the front / finish launching.
    /// The result is reported via the completion handler so callers can surface it.
    @discardableResult
    static func triggerImportInLightroom(afterDelay delay: TimeInterval = 1.2) -> Bool {
        let menuTitle = "Import Aurora Photos Now"
        let pluginExtras = "Plug-in Extras"
        // Try File ▸ Plug-in Extras first (present in every module), then fall back to
        // Library ▸ Plug-in Extras in case the File entry isn't available.
        let script = """
        tell application "Adobe Lightroom Classic" to activate
        delay \(String(format: "%.2f", delay))
        tell application "System Events"
            tell process "Adobe Lightroom Classic"
                set frontmost to true
                try
                    click menu item "\(menuTitle)" of menu 1 of menu item "\(pluginExtras)" of menu 1 of menu bar item "File" of menu bar 1
                    return "ok-file"
                on error
                    click menu item "\(menuTitle)" of menu 1 of menu item "\(pluginExtras)" of menu 1 of menu bar item "Library" of menu bar 1
                    return "ok-library"
                end try
            end tell
        end tell
        """

        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            scriptObject.executeAndReturnError(&error)
            if let error {
                NSLog("LightroomSyncService.triggerImportInLightroom failed: \(error)")
                return false
            }
            return true
        }
        return false
    }

    private static func writePendingRequestData(_ data: Data, fileName: String, root: URL) throws -> URL {
        let pendingDir = root.appendingPathComponent("pending", isDirectory: true)
        try FileManager.default.createDirectory(at: pendingDir, withIntermediateDirectories: true)
        let fileURL = pendingDir.appendingPathComponent(fileName)
        try data.write(to: fileURL, options: [.atomic])
        return fileURL
    }

    private static func lightroomAppDataSyncRoot() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("Adobe", isDirectory: true)
            .appendingPathComponent("Lightroom", isDirectory: true)
            .appendingPathComponent("commanderonev2", isDirectory: true)
            .appendingPathComponent("lightroom_sync", isDirectory: true)
    }
}
