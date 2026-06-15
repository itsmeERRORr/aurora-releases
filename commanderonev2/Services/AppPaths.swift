import Foundation

/// Central source of truth for filesystem locations the app reads from and writes to.
///
/// Beta builds (bundle identifier ending in `.beta`) get their own isolated data
/// directory so they never collide with the production app's events, banners,
/// stats, or logs. The Production app keeps reading from the original
/// `commanderonev2/` folder so users keep their data across upgrades.
enum AppPaths {

    /// `true` when running under the Beta scheme (bundle id contains `.beta`).
    static let isBeta: Bool = {
        Bundle.main.bundleIdentifier?.contains(".beta") == true
    }()

    /// Root subdirectory name inside `~/Library/Application Support/`.
    /// - Production: `commanderonev2`
    /// - Beta:       `commanderonev2-beta`
    static let supportDirectoryName: String = isBeta ? "commanderonev2-beta" : "commanderonev2"

    /// `~/Library/Application Support/<commanderonev2 | commanderonev2-beta>/`,
    /// creating it on demand.
    static var applicationSupportRoot: URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let root = appSupport.appendingPathComponent(supportDirectoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// Convenience: returns a subdirectory inside `applicationSupportRoot`, created if needed.
    static func subdirectory(_ name: String) -> URL {
        let dir = applicationSupportRoot.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
