import AppKit
import UniformTypeIdentifiers

/// Notch'a bırakılan dosyaları tutan raf. Finder'dan gelen dosyalar yerinde referans edilir;
/// tarayıcıdan gelen görsel/metin gibi dosyası olmayan içerikler uygulama klasörüne kaydedilir.
@Observable
final class ShelfStore {
    struct Item: Identifiable, Hashable {
        let url: URL
        var id: URL { url }
        var name: String { url.lastPathComponent }
        var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }
    }

    static let acceptedTypes: [UTType] = [.fileURL, .image, .plainText, .url]

    private(set) var items: [Item] = []

    @ObservationIgnored private let defaultsKey = "shelf.paths"

    /// Dosyası olmayan içeriklerin kaydedildiği klasör.
    @ObservationIgnored private let storageDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Notchland/Shelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    init() {
        let paths = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        items = paths
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { Item(url: URL(fileURLWithPath: $0)) }
    }

    // MARK: - Ekleme / çıkarma

    func add(_ url: URL) {
        guard !items.contains(where: { $0.url == url }) else { return }
        items.append(Item(url: url))
        save()
    }

    func remove(_ item: Item) {
        items.removeAll { $0 == item }
        // Raf için bizim oluşturduğumuz geçici dosyaları da sil.
        if item.url.deletingLastPathComponent().standardizedFileURL == storageDirectory.standardizedFileURL {
            try? FileManager.default.removeItem(at: item.url)
        }
        save()
    }

    func removeAll() {
        items.forEach(remove)
    }

    private func save() {
        UserDefaults.standard.set(items.map(\.url.path), forKey: defaultsKey)
    }

    // MARK: - Bırakma

    /// SwiftUI `onDrop` sağlayıcılarını rafa ekler. En az bir öğe kabul edildiyse true döner.
    @discardableResult
    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        resolveURLs(from: providers, storingIn: storageDirectory) { [weak self] urls in
            urls.forEach { self?.add($0) }
        }
    }

    /// Bırakılan içerikleri AirDrop ile gönderir (rafa eklemeden).
    @discardableResult
    func airDrop(_ providers: [NSItemProvider]) -> Bool {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("NotchlandAirDrop", isDirectory: true)
        try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        return resolveURLs(from: providers, storingIn: temp) { urls in
            Sharing.airDrop(urls)
        }
    }

    func airDrop(_ items: [Item]) {
        Sharing.airDrop(items.map(\.url))
    }

    /// Sağlayıcıları dosya URL'lerine çevirir; dosyası olmayan içerik (görsel, bağlantı, metin)
    /// `directory` içine kaydedilir. Tamamlanınca ana kuyrukta çağrılır.
    @discardableResult
    private func resolveURLs(
        from providers: [NSItemProvider],
        storingIn directory: URL,
        completion: @escaping ([URL]) -> Void
    ) -> Bool {
        let group = DispatchGroup()
        let lock = NSLock()
        var results: [(Int, URL)] = []
        let collect: (Int, URL?) -> Void = { index, url in
            if let url {
                lock.lock()
                results.append((index, url))
                lock.unlock()
            }
            group.leave()
        }

        var accepted = false
        for (index, provider) in providers.enumerated() {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                accepted = true
                group.enter()
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    collect(index, url?.isFileURL == true ? url : nil)
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                accepted = true
                group.enter()
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    let url = data.flatMap {
                        Self.write($0, to: directory, name: provider.suggestedName ?? "Görsel", ext: Self.imageExtension(for: $0))
                    }
                    collect(index, url)
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                accepted = true
                group.enter()
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    let webloc = url.flatMap {
                        try? PropertyListSerialization.data(
                            fromPropertyList: ["URL": $0.absoluteString], format: .xml, options: 0
                        )
                    }
                    collect(index, webloc.flatMap {
                        Self.write($0, to: directory, name: url?.host ?? "Bağlantı", ext: "webloc")
                    })
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                accepted = true
                group.enter()
                _ = provider.loadObject(ofClass: String.self) { text, _ in
                    let title = text.map { String($0.prefix(24)).components(separatedBy: .newlines).first ?? "Metin" }
                    collect(index, text?.data(using: .utf8).flatMap {
                        Self.write($0, to: directory, name: title ?? "Metin", ext: "txt")
                    })
                }
            }
        }

        group.notify(queue: .main) {
            completion(results.sorted { $0.0 < $1.0 }.map(\.1))
        }
        return accepted
    }

    private static func write(_ data: Data, to directory: URL, name: String, ext: String) -> URL? {
        let safeName = name.replacingOccurrences(of: "/", with: "-")
        var url = directory.appendingPathComponent(safeName).appendingPathExtension(ext)
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(safeName) \(counter)").appendingPathExtension(ext)
            counter += 1
        }
        return (try? data.write(to: url)) != nil ? url : nil
    }

    private static func imageExtension(for data: Data) -> String {
        if data.starts(with: [0xFF, 0xD8]) { return "jpg" }
        if data.starts(with: [0x47, 0x49, 0x46]) { return "gif" }
        return "png"
    }

    // MARK: - Eylemler

    func open(_ item: Item) {
        NSWorkspace.shared.open(item.url)
    }

    func revealInFinder(_ item: Item) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }
}
