import AppKit

/// Ne kadar, neyi dinlediğinin kaydı (Wrapped sekmesi için). Yalnızca başlık, sanatçı, süre ve küçük kapak
/// saklanır; `~/Library/Application Support/Notchland/Dinleme/` altında durur, hiçbir yere gönderilmez.
@Observable
final class ListeningHistory {
    struct Song: Codable {
        var title: String
        var artist: String
        /// `Kapaklar/` altındaki küçük kapak.
        var artworkFile: String?
    }

    /// Bir günün dinlemeleri; anahtarlar `Song` anahtarıdır.
    private struct Day: Codable {
        var seconds: [String: Double] = [:]
        var plays: [String: Int] = [:]
        /// Saat başına dinleme süresi (0…23).
        var hours = [Double](repeating: 0, count: 24)
    }

    private struct Store: Codable {
        var songs: [String: Song] = [:]
        /// "yyyy-MM-dd" → gün.
        var days: [String: Day] = [:]
    }

    enum Period: String, CaseIterable, Identifiable {
        case today, week, month, all
        var id: String { rawValue }

        var title: String {
            switch self {
            case .today: "Bugün"
            case .week: "Hafta"
            case .month: "Ay"
            case .all: "Tümü"
            }
        }
    }

    struct Summary {
        struct SongStat: Identifiable {
            let id: String
            let song: Song
            var seconds: Double
            var plays: Int
        }

        struct ArtistStat: Identifiable {
            let id: String
            let name: String
            var seconds: Double
        }

        var seconds: Double = 0
        var songCount = 0
        var topSongs: [SongStat] = []
        var topArtists: [ArtistStat] = []
        /// En çok dinlenen saat.
        var peakHour: Int?
        /// Bugünle biten, her gün müzik dinlenen gün sayısı.
        var streak = 0
    }

    /// Bir şarkı bu kadar dinlenince bir kez "çalındı" sayılır.
    private static let playThreshold: TimeInterval = 30
    /// Uyku gibi kopukluklar sayılmasın diye iki ölçüm arasındaki en uzun süre.
    private static let maxGap: TimeInterval = 20

    /// Görünümler özeti bu değiştikçe yeniden hesaplar.
    private(set) var revision = 0

    @ObservationIgnored private var store = Store()
    @ObservationIgnored private var currentKey: String?
    @ObservationIgnored private var lastMark: Date?
    @ObservationIgnored private var sessionKey: String?
    @ObservationIgnored private var sessionSeconds: TimeInterval = 0
    @ObservationIgnored private var sessionCounted = false
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var isDirty = false
    @ObservationIgnored private var lastSave = Date.now
    @ObservationIgnored private var artworkCache: [String: NSImage] = [:]

    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notchland/Dinleme", isDirectory: true)
    }

    private static var storeURL: URL { folder.appendingPathComponent("gecmis.json") }
    private static var artworkFolder: URL { folder.appendingPathComponent("Kapaklar", isDirectory: true) }

    init() {
        if let data = try? Data(contentsOf: Self.storeURL),
           let decoded = try? JSONDecoder().decode(Store.self, from: data) {
            store = decoded
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.accumulate(at: .now)
            self?.save()
        }
        NotificationCenter.default.addObserver(
            forName: Self.resetNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.reset() }
    }

    private static let resetNotification = Notification.Name("NotchlandListeningHistoryReset")

    /// Ayarlar penceresi servise erişmeden geçmişi sildirir.
    static func requestReset() {
        NotificationCenter.default.post(name: resetNotification, object: nil)
    }

    /// Çalan parça her değiştiğinde (oynat/duraklat, konum dahil) çağrılır.
    func update(_ track: MediaController.Track?) {
        let now = Date.now
        accumulate(at: now)
        guard AppSettings.shared.listeningHistory, let track, !track.title.isEmpty else {
            pause()
            return
        }
        let key = Self.key(title: track.title, artist: track.artist)
        // Aynı şarkı baştan çalınıyorsa yeni bir dinleme sayılır.
        if key != sessionKey || (track.elapsed < 2 && sessionSeconds > Self.playThreshold) {
            sessionKey = key
            sessionSeconds = 0
            sessionCounted = false
        }
        register(track, key: key)
        guard track.isPlaying else { return pause() }
        currentKey = key
        lastMark = now
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.tick() }
        }
    }

    func summary(for period: Period) -> Summary {
        let days = dayKeys(for: period).compactMap { store.days[$0] }
        var songs: [String: Summary.SongStat] = [:]
        var artists: [String: Summary.ArtistStat] = [:]
        var hours = [Double](repeating: 0, count: 24)
        var summary = Summary()
        for day in days {
            for (key, seconds) in day.seconds {
                guard let song = store.songs[key] else { continue }
                summary.seconds += seconds
                songs[key, default: .init(id: key, song: song, seconds: 0, plays: 0)].seconds += seconds
                songs[key]!.plays += day.plays[key] ?? 0
                let artist = song.artist.isEmpty ? "Bilinmeyen" : song.artist
                let artistKey = artist.lowercased()
                artists[artistKey, default: .init(id: artistKey, name: artist, seconds: 0)].seconds += seconds
            }
            for hour in 0..<min(24, day.hours.count) { hours[hour] += day.hours[hour] }
        }
        summary.songCount = songs.count
        summary.topSongs = Array(songs.values.sorted { $0.seconds > $1.seconds }.prefix(3))
        summary.topArtists = Array(artists.values.sorted { $0.seconds > $1.seconds }.prefix(3))
        if let peak = hours.indices.max(by: { hours[$0] < hours[$1] }), hours[peak] > 0 { summary.peakHour = peak }
        summary.streak = streak()
        return summary
    }

    func artwork(for song: Song) -> NSImage? {
        guard let file = song.artworkFile else { return nil }
        if let cached = artworkCache[file] { return cached }
        let image = NSImage(contentsOf: Self.artworkFolder.appendingPathComponent(file))
        if let image { artworkCache[file] = image }
        return image
    }

    /// Tüm geçmişi ve kapakları siler.
    private func reset() {
        store = Store()
        artworkCache = [:]
        sessionKey = nil
        isDirty = false
        try? FileManager.default.removeItem(at: Self.folder)
        revision += 1
    }

    // MARK: - Sayma

    private func tick() {
        accumulate(at: .now)
        if isDirty, lastSave.timeIntervalSinceNow < -60 { save() }
    }

    private func pause() {
        currentKey = nil
        lastMark = nil
        timer?.invalidate()
        timer = nil
        save()
    }

    /// Son ölçümden bu yana geçen süreyi çalan şarkıya yazar.
    private func accumulate(at now: Date) {
        guard let key = currentKey, let mark = lastMark else { return }
        lastMark = now
        let delta = min(now.timeIntervalSince(mark), Self.maxGap)
        guard delta > 0 else { return }
        let dayKey = Self.dayFormatter.string(from: now)
        let hour = Calendar.current.component(.hour, from: now)
        var day = store.days[dayKey] ?? Day()
        day.seconds[key, default: 0] += delta
        day.hours[hour] += delta
        sessionSeconds += delta
        if !sessionCounted, sessionSeconds >= Self.playThreshold {
            sessionCounted = true
            day.plays[key, default: 0] += 1
        }
        store.days[dayKey] = day
        isDirty = true
        revision += 1
    }

    /// Şarkıyı ilk görüşte kaydeder; kapak sonradan gelirse küçültüp ekler.
    private func register(_ track: MediaController.Track, key: String) {
        if store.songs[key] == nil {
            store.songs[key] = Song(title: track.title, artist: track.artist)
            isDirty = true
        }
        guard store.songs[key]?.artworkFile == nil, let artwork = track.artwork,
              let cgImage = artwork.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let file = Self.fileName(for: key)
        store.songs[key]?.artworkFile = file
        isDirty = true
        let url = Self.artworkFolder.appendingPathComponent(file)
        DispatchQueue.global(qos: .utility).async {
            guard let data = Self.thumbnail(cgImage, side: 96) else { return }
            try? FileManager.default.createDirectory(at: Self.artworkFolder, withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }

    private func save() {
        guard isDirty, let data = try? JSONEncoder().encode(store) else { return }
        isDirty = false
        lastSave = .now
        DispatchQueue.global(qos: .utility).async {
            do {
                try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
                try data.write(to: Self.storeURL, options: .atomic)
            } catch {
                NSLog("[Notchland] Dinleme geçmişi kaydedilemedi: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Yardımcılar

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private func dayKeys(for period: Period) -> [String] {
        let count: Int
        switch period {
        case .today: count = 1
        case .week: count = 7
        case .month: count = 30
        case .all: return Array(store.days.keys)
        }
        let calendar = Calendar.current
        let today = Date.now
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
            .map(Self.dayFormatter.string(from:))
    }

    /// Bugün henüz dinlenmediyse dünden geriye sayar.
    private func streak() -> Int {
        let calendar = Calendar.current
        var date = Date.now
        if store.days[Self.dayFormatter.string(from: date)] == nil {
            date = calendar.date(byAdding: .day, value: -1, to: date) ?? date
        }
        var count = 0
        while store.days[Self.dayFormatter.string(from: date)] != nil {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: date) else { break }
            date = previous
        }
        return count
    }

    private static func key(title: String, artist: String) -> String {
        "\(title)|\(artist)".lowercased()
    }

    /// Anahtardan kararlı dosya adı (FNV-1a).
    private static func fileName(for key: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16) + ".jpg"
    }

    private static func thumbnail(_ image: CGImage, side: Int) -> Data? {
        guard let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        // Kare olmayan kapaklar ortadan kırpılır.
        let scale = CGFloat(side) / CGFloat(min(image.width, image.height))
        let width = CGFloat(image.width) * scale, height = CGFloat(image.height) * scale
        context.draw(image, in: CGRect(x: (CGFloat(side) - width) / 2, y: (CGFloat(side) - height) / 2, width: width, height: height))
        guard let scaled = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: scaled).representation(using: .jpeg, properties: [.compressionFactor: 0.8])
    }
}
