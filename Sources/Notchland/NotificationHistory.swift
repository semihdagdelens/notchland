import AppKit

/// Notch'a yansıtılan bildirimlerin geçmişi. Sistem balonu kapatılınca bildirim Bildirim Merkezi'nden
/// de kalktığı için geçmiş burada tutulur. Yalnızca bu Mac'te, Application Support altında saklanır.
@Observable
final class NotificationHistory {
    struct Entry: Identifiable, Codable, Equatable {
        let id: UUID
        let appName: String?
        let title: String
        let body: String
        let bundleID: String?
        let date: Date
    }

    private static let maxEntries = 200

    private(set) var entries: [Entry] = []

    @ObservationIgnored private let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Notchland/Notifications", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }()

    init() { load() }

    func add(_ notice: NotificationMirror.Notice) {
        let entry = Entry(id: UUID(), appName: notice.appName, title: notice.title, body: notice.body,
                          bundleID: notice.bundleID, date: Date())
        entries.insert(entry, at: 0)
        if entries.count > Self.maxEntries { entries.removeLast(entries.count - Self.maxEntries) }
        save()
    }

    func remove(_ entry: Entry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func removeAll() {
        entries.removeAll()
        save()
    }

    /// Bildirimi gönderen uygulamayı öne getirir (balona tıklamanın en yakın karşılığı).
    func open(_ entry: Entry) {
        guard let bundleID = entry.bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? JSONDecoder().decode([Entry].self, from: data) else { return }
        entries = saved
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
