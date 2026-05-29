import Foundation
import AppKit

enum BookmarkManager {
    static func saveBookmark(for url: URL) -> Data? {
        do {
            let data = try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            return data
        } catch {
            print("Failed to create bookmark: \(error)")
            return nil
        }
    }

    static func resolveBookmark(_ data: Data) -> URL? {
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                print("Bookmark is stale, needs refresh")
            }
            return url
        } catch {
            print("Failed to resolve bookmark: \(error)")
            return nil
        }
    }

    static func startAccessing(_ url: URL) -> Bool {
        return false
    }

    static func stopAccessing(_ url: URL) {
    }
}
