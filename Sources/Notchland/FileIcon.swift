import AppKit

/// Dosya ikonları için önbellek. `NSWorkspace.icon(forFile:)` her çağrıda ikon servisine gider;
/// raf ve pano satırları her çizimde (ör. üzerine gelince) yeniden sorar.
enum FileIcon {
    private static let cache = NSCache<NSString, NSImage>()

    static func icon(forFile path: String) -> NSImage {
        if let cached = cache.object(forKey: path as NSString) { return cached }
        let icon = NSWorkspace.shared.icon(forFile: path)
        cache.setObject(icon, forKey: path as NSString)
        return icon
    }
}
