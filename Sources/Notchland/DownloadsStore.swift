import AppKit
import QuickLookThumbnailing

/// İndirilenler klasöründeki son dosyalar. Klasör izni ilk açılışta değil, sekme ilk görününce istenir.
@Observable
final class DownloadsStore {
    struct Item: Identifiable, Hashable {
        let url: URL
        let date: Date
        var id: URL { url }
        var name: String { url.lastPathComponent }
    }

    private static let maxItems = 30
    /// Tarayıcıların ve yt-dlp'nin yarım dosyaları; bitince adları değişir ve listeye o zaman girer.
    private static let partialExtensions: Set<String> = ["part", "crdownload", "download", "tmp", "ytdl", "opdownload"]

    private(set) var items: [Item] = []
    /// Klasör okunamadı (izin verilmedi).
    private(set) var isUnavailable = false

    let directory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]

    @ObservationIgnored private var source: DispatchSourceFileSystemObject?
    @ObservationIgnored private var pendingScan: DispatchWorkItem?
    @ObservationIgnored private let thumbnails: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = DownloadsStore.maxItems * 2
        return cache
    }()

    func start() {
        scan()
        guard source == nil else { return }
        let descriptor = Darwin.open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        // Tarama yerine olay: klasöre dosya girip çıkınca (veya yarım dosyanın adı değişince) uyanır.
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main
        )
        source.setEventHandler { [weak self] in self?.scheduleScan() }
        source.setCancelHandler { Darwin.close(descriptor) }
        source.resume()
        self.source = source
    }

    /// Bir indirme art arda çok olay üretir; hepsi tek taramada birleşsin.
    private func scheduleScan() {
        pendingScan?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.scan() }
        pendingScan = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func scan() {
        let directory = directory
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let keys: [URLResourceKey] = [.addedToDirectoryDateKey, .creationDateKey]
            let urls = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
            )
            let found = (urls ?? [])
                .filter { !Self.partialExtensions.contains($0.pathExtension.lowercased()) }
                .map { url -> Item in
                    let values = try? url.resourceValues(forKeys: Set(keys))
                    return Item(url: url, date: values?.addedToDirectoryDate ?? values?.creationDate ?? .distantPast)
                }
                .sorted { $0.date > $1.date }
                .prefix(Self.maxItems)
            DispatchQueue.main.async {
                guard let self else { return }
                self.isUnavailable = urls == nil
                self.items = Array(found)
            }
        }
    }

    /// Görsel, video ve PDF için içerik önizlemesi; yoksa dosya ikonu.
    func thumbnail(for item: Item) async -> NSImage? {
        if let cached = thumbnails.object(forKey: item.url as NSURL) { return cached }
        // Tek boyutta üretilir: en büyük panelin kutucuğuna göre, panel büyüyünce bulanmasın.
        let request = QLThumbnailGenerator.Request(
            fileAt: item.url, size: CGSize(width: 280, height: 280), scale: 2, representationTypes: .all
        )
        guard let image = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage else { return nil }
        thumbnails.setObject(image, forKey: item.url as NSURL)
        return image
    }

    // MARK: - Eylemler

    func open(_ item: Item) {
        NSWorkspace.shared.open(item.url)
    }

    func revealFolder() {
        NSWorkspace.shared.open(directory)
    }
}
