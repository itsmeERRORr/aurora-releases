import Foundation
import AppKit

/// Thread-safe thumbnail cache using NSCache for automatic LRU eviction
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache = NSCache<NSString, NSImage>()
    private let queue = DispatchQueue(label: "com.joaosphotos.thumbnailcache", attributes: .concurrent)

    private init() {
        // Keep enough previews hot without letting large imports consume laptop memory.
        cache.countLimit = 2500
        cache.totalCostLimit = 256 * 1024 * 1024
        
        print("ThumbnailCache initialized: max 2500 items, 256MB limit")
    }

    /// Get cached thumbnail if available
    func get(for url: URL) -> NSImage? {
        return queue.sync {
            cache.object(forKey: url.path as NSString)
        }
    }

    private var itemCount = 0
    private var totalCost = 0
    
    /// Store thumbnail in cache with cost based on image size
    func set(_ image: NSImage, for url: URL) {
        queue.sync(flags: .barrier) {
            // Estimate memory cost (width × height × 4 bytes per pixel)
            let size = image.size
            let cost = Int(size.width * size.height * 4)

            cache.setObject(image, forKey: url.path as NSString, cost: cost)
            
            itemCount += 1
            totalCost += cost
        }
    }

    /// Check if thumbnail exists in cache
    func contains(_ url: URL) -> Bool {
        return queue.sync {
            cache.object(forKey: url.path as NSString) != nil
        }
    }

    /// Clear all cached thumbnails
    func clearAll() {
        queue.async(flags: .barrier) { [weak self] in
            self?.cache.removeAllObjects()
            self?.itemCount = 0
            self?.totalCost = 0
        }
    }
    
    /// Get cache statistics for debugging
    func getStats() -> (count: Int, costMB: Double) {
        return queue.sync {
            let mb = Double(totalCost) / (1024 * 1024)
            return (itemCount, mb)
        }
    }
}
