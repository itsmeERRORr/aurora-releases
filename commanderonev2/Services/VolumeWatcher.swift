import Foundation
import AppKit

@MainActor
final class VolumeWatcher {
    private let appState: AppState
    private var isWatching = false
    private var mountObserver: NSObjectProtocol?
    private var unmountObserver: NSObjectProtocol?

    init(appState: AppState) {
        self.appState = appState
    }

    func startWatching() {
        guard !isWatching else { return }
        isWatching = true
        appState.log("Volume watcher started")

        let center = NSWorkspace.shared.notificationCenter

        mountObserver = center.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            guard let path = notif.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            Task { @MainActor [weak self] in
                self?.handleMountInternal(path: path)
            }
        }

        unmountObserver = center.addObserver(
            forName: NSWorkspace.didUnmountNotification,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            guard let path = notif.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            Task { @MainActor [weak self] in
                self?.handleUnmountInternal(path: path)
            }
        }

        scanExistingVolumes()
    }

    func stopWatching() {
        guard isWatching else { return }
        isWatching = false
        let center = NSWorkspace.shared.notificationCenter
        if let mountObserver {
            center.removeObserver(mountObserver)
            self.mountObserver = nil
        }
        if let unmountObserver {
            center.removeObserver(unmountObserver)
            self.unmountObserver = nil
        }
        appState.log("Volume watcher stopped")
    }

    func refreshMountedVolumes() {
        scanExistingVolumes()
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        if let mountObserver { center.removeObserver(mountObserver) }
        if let unmountObserver { center.removeObserver(unmountObserver) }
    }

    private func scanExistingVolumes() {
        let fm = FileManager.default
        guard let volumeURLs = fm.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeNameKey, .volumeIsRemovableKey, .volumeIsLocalKey, .volumeIsInternalKey],
            options: [.skipHiddenVolumes]
        ) else { return }

        for url in volumeURLs {
            let resourceValues = try? url.resourceValues(forKeys: [.volumeNameKey, .volumeIsRemovableKey, .volumeIsLocalKey, .volumeIsInternalKey])
            let name = resourceValues?.volumeName ?? url.lastPathComponent
            let isRemovable = resourceValues?.volumeIsRemovable ?? false

            if shouldProcessVolume(url, name: name, isRemovable: isRemovable, isLocal: resourceValues?.volumeIsLocal ?? false, isInternal: resourceValues?.volumeIsInternal ?? false) {
                if let info = makeVolumeInfo(from: url) {
                    if let index = appState.mountedVolumes.firstIndex(where: { $0.path == info.path }) {
                        var updated = info
                        updated.isActive = appState.activeVolume?.path == info.path && info.rawFileCount > 0
                        appState.mountedVolumes[index] = updated
                        if appState.activeVolume?.path == info.path {
                            appState.activeVolume = info.rawFileCount > 0 ? updated : nil
                        }
                    } else {
                        appState.mountedVolumes.append(info)
                        appState.log("Found card: \(info.name) (\(info.rawFileCount) RAW files)")
                        if info.rawFileCount > 0 {
                            activateVolume(info)
                        }
                    }
                }
            }
        }
    }

    private func handleMountInternal(path: URL) {
        let resourceValues = try? path.resourceValues(forKeys: [.volumeNameKey, .volumeIsRemovableKey, .volumeIsLocalKey, .volumeIsInternalKey])
        let name = resourceValues?.volumeName ?? path.lastPathComponent
        let isRemovable = resourceValues?.volumeIsRemovable ?? false

        guard shouldProcessVolume(
            path,
            name: name,
            isRemovable: isRemovable,
            isLocal: resourceValues?.volumeIsLocal ?? false,
            isInternal: resourceValues?.volumeIsInternal ?? false
        ) else { return }

        appState.log("Detected card mount: \(name)")

        if let info = makeVolumeInfo(from: path) {
            appState.mountedVolumes.removeAll { $0.path == info.path }
            appState.mountedVolumes.append(info)
            appState.log("Card \(info.name): \(info.rawFileCount) RAW files found")

            if info.rawFileCount > 0 {
                activateVolume(info)
                if appState.autoImport && appState.destinationURL != nil {
                    appState.log("Auto-import triggered for \(info.name)")
                    NotificationCenter.default.post(name: .startAutoImport, object: nil)
                }
            }
        }
    }

    private func handleUnmountInternal(path: URL) {
        let name = path.lastPathComponent
        appState.log("Volume unmounted: \(name)")
        appState.mountedVolumes.removeAll { $0.path == path }

        if appState.activeVolume?.path == path {
            appState.activeVolume = nil
            appState.log("Active volume removed")
        }
    }

    private func activateVolume(_ info: VolumeInfo) {
        var activated = info
        activated.isActive = true
        appState.activeVolume = activated

        // Update in list
        if let idx = appState.mountedVolumes.firstIndex(where: { $0.path == info.path }) {
            appState.mountedVolumes[idx] = activated
        }
        appState.log("Active volume set: \(info.name)")
        NotificationCenter.default.post(name: .cardDetected, object: nil)
    }

    private func shouldProcessVolume(_ url: URL, name: String, isRemovable: Bool, isLocal: Bool, isInternal: Bool) -> Bool {
        guard name != "Macintosh HD", !isDestinationVolume(url) else { return false }
        if name == "Untitled" || isRemovable { return true }
        // CFexpress readers over Thunderbolt may appear as local, non-internal
        // volumes rather than removable/ejectable media.
        return isLocal && !isInternal
    }

    private func isDestinationVolume(_ volumeURL: URL) -> Bool {
        guard let destinationURL = appState.destinationURL else { return false }
        let volumePath = normalizedPath(volumeURL.path)
        let destinationPath = normalizedPath(destinationURL.path)
        return destinationPath == volumePath || destinationPath.hasPrefix(volumePath + "/")
    }

    private func normalizedPath(_ path: String) -> String {
        path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    // Manual folder selection
    func selectManualSource() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select source folder containing RAW files"

        if panel.runModal() == .OK, let url = panel.url {
            let rawCount = countRawFiles(at: url)
            if rawCount > 0 {
                SecurityBookmarkManager.shared.saveBookmark(for: url)
            }
            let info = VolumeInfo(
                id: url.path,
                name: url.lastPathComponent,
                path: url,
                rawFileCount: rawCount,
                isActive: true
            )

            appState.mountedVolumes.removeAll()
            appState.mountedVolumes.append(info)
            appState.activeVolume = info
            appState.log("Manual source selected: \(info.name) (\(rawCount) RAW files)")
        }
    }

    private func makeVolumeInfo(from url: URL) -> VolumeInfo? {
        let resourceValues = try? url.resourceValues(forKeys: [.volumeNameKey, .volumeIsRemovableKey])
        let name = resourceValues?.volumeName ?? url.lastPathComponent

        let rawCount = countRawFiles(at: url)
        if rawCount > 0 {
            SecurityBookmarkManager.shared.saveBookmark(for: url)
        }

        return VolumeInfo(
            id: url.path,
            name: name,
            path: url,
            rawFileCount: rawCount,
            isActive: false
        )
    }

    func countRawFiles(at url: URL) -> Int {
        Self.countRawFiles(at: url, extensions: appState.supportedExtensions)
    }

    /// Count RAW files recursively in a folder (including subfolders). Thread-safe; can be called from background.
    /// - Parameter modifiedOnOrAfter: if non-nil, only count files with contentModificationDate >= this date (e.g. last 12 months).
    nonisolated static func countRawFiles(at url: URL, extensions: Set<String>, modifiedOnOrAfter: Date? = nil) -> Int {
        let fm = FileManager.default
        let securityScoped = SecurityBookmarkManager.shared.requestAccess(for: url)
        defer { if securityScoped { SecurityBookmarkManager.shared.stopAccessing(url) } }
        guard (try? url.checkResourceIsReachable()) ?? false else { return 0 }
        let keys: Set<URLResourceKey> = modifiedOnOrAfter != nil ? [.isRegularFileKey, .contentModificationDateKey] : [.isRegularFileKey]
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return 0 }
        var count = 0
        for case let fileURL as URL in enumerator {
            guard (try? fileURL.checkResourceIsReachable()) ?? false else { continue }
            let ext = fileURL.pathExtension.lowercased()
            guard extensions.contains(ext) else { continue }
            if let cutoff = modifiedOnOrAfter {
                guard let mod = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                      mod >= cutoff else { continue }
            }
            count += 1
        }
        return count
    }

    func listRawFiles(at url: URL) -> [URL] {
        let fm = FileManager.default
        let securityScoped = SecurityBookmarkManager.shared.requestAccess(for: url)
        defer { if securityScoped { SecurityBookmarkManager.shared.stopAccessing(url) } }

        // Check if volume is accessible before enumerating
        guard (try? url.checkResourceIsReachable()) ?? false else {
            return []
        }

        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            // Skip files that cause I/O errors
            guard (try? fileURL.checkResourceIsReachable()) ?? false else {
                continue
            }
            let ext = fileURL.pathExtension.lowercased()
            if appState.supportedExtensions.contains(ext) {
                files.append(fileURL)
            }
        }
        return files
    }

    /// List RAW files recursively in a folder. Thread-safe; can be called from any context.
    nonisolated static func listRawFiles(at url: URL, extensions: Set<String>) -> [URL] {
        let fm = FileManager.default
        let securityScoped = SecurityBookmarkManager.shared.requestAccess(for: url)
        defer { if securityScoped { SecurityBookmarkManager.shared.stopAccessing(url) } }
        guard (try? url.checkResourceIsReachable()) ?? false else { return [] }
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            guard (try? fileURL.checkResourceIsReachable()) ?? false else { continue }
            let ext = fileURL.pathExtension.lowercased()
            if extensions.contains(ext) {
                files.append(fileURL)
            }
        }
        return files
    }
}

extension Notification.Name {
    static let startAutoImport = Notification.Name("startAutoImport")
    static let cardDetected = Notification.Name("cardDetected")
}
