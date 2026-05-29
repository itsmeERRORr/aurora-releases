import Foundation

final class SecurityBookmarkManager {
    static let shared = SecurityBookmarkManager()

    private let bookmarksKey = "savedSecurityBookmarks"
    private var activeBookmarks: [String: URL] = [:]

    private init() {
        loadBookmarks()
    }

    // Save a security-scoped bookmark for a URL
    func saveBookmark(for url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            print("⚠️ Failed to access security scoped resource")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let bookmarkData = try url.bookmarkData(
                options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )

            var bookmarks = loadBookmarksData()
            bookmarks[url.path] = bookmarkData
            saveBookmarksData(bookmarks)

            print("✅ Saved security bookmark for: \(url.lastPathComponent)")
        } catch {
            print("❌ Failed to create bookmark: \(error)")
        }
    }

    // Request access to a URL, restoring from bookmark if available
    func requestAccess(for url: URL) -> Bool {
        // Check if we already have an active bookmark
        if let activeURL = activeBookmarks[url.path] {
            return activeURL.startAccessingSecurityScopedResource()
        }

        // Try to restore from saved bookmark
        let bookmarks = loadBookmarksData()
        if let bookmarkData = bookmarks[url.path] {
            do {
                var isStale = false
                let restoredURL = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )

                if isStale {
                    print("⚠️ Bookmark is stale, will need to re-authorize")
                    // Remove stale bookmark
                    var updatedBookmarks = bookmarks
                    updatedBookmarks.removeValue(forKey: url.path)
                    saveBookmarksData(updatedBookmarks)
                    return false
                }

                if restoredURL.startAccessingSecurityScopedResource() {
                    activeBookmarks[url.path] = restoredURL
                    print("✅ Restored access from bookmark: \(url.lastPathComponent)")
                    return true
                }
            } catch {
                print("❌ Failed to resolve bookmark: \(error)")
            }
        }

        return false
    }

    // Stop accessing a security-scoped resource
    func stopAccessing(_ url: URL) {
        if let activeURL = activeBookmarks[url.path] {
            activeURL.stopAccessingSecurityScopedResource()
            activeBookmarks.removeValue(forKey: url.path)
        }
    }

    // Clear all bookmarks (for testing/debugging)
    func clearAllBookmarks() {
        UserDefaults.standard.removeObject(forKey: bookmarksKey)
        activeBookmarks.removeAll()
        print("🗑️ Cleared all security bookmarks")
    }

    // MARK: - Private

    private func loadBookmarks() {
        let bookmarks = loadBookmarksData()
        print("📚 Loaded \(bookmarks.count) saved bookmarks")
    }

    private func loadBookmarksData() -> [String: Data] {
        guard let data = UserDefaults.standard.data(forKey: bookmarksKey),
              let bookmarks = try? JSONDecoder().decode([String: Data].self, from: data) else {
            return [:]
        }
        return bookmarks
    }

    private func saveBookmarksData(_ bookmarks: [String: Data]) {
        if let data = try? JSONEncoder().encode(bookmarks) {
            UserDefaults.standard.set(data, forKey: bookmarksKey)
        }
    }
}
