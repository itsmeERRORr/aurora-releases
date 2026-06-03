import Foundation
import AppKit

enum BookmarkManager {
    static func saveBookmark(for url: URL) -> Data? {
        do {
            let data = try url.bookmarkData(
                options: [.withSecurityScope],
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
        if let url = resolveBookmark(data, options: [.withSecurityScope]) {
            return url
        }
        return resolveBookmark(data, options: [])
    }

    /// Resolves a bookmark without triggering macOS to mount the host volume
    /// (e.g. by prompting the user to connect to a network share). Returns nil
    /// when the volume isn't already mounted instead of showing a connection
    /// dialog.
    static func resolveBookmarkWithoutMounting(_ data: Data) -> URL? {
        if let url = resolveBookmark(data, options: [.withSecurityScope, .withoutMounting]) {
            return url
        }
        return resolveBookmark(data, options: [.withoutMounting])
    }

    private static func resolveBookmark(_ data: Data, options: URL.BookmarkResolutionOptions) -> URL? {
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: options,
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
        url.startAccessingSecurityScopedResource()
    }

    static func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
}
