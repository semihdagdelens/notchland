import Foundation

/// Çalan parçanın şarkı sözlerini LRCLIB'den (lrclib.net, anahtarsız) bulur.
/// YouTube gibi kaynaklardan gelen "Sanatçı - Şarkı (Official Video)" başlıkları temizlenerek aranır.
@Observable
final class LyricsService {
    struct Line: Identifiable, Equatable {
        let id: Int
        /// Satırın başladığı saniye; senkron olmayan sözlerde nil.
        let time: TimeInterval?
        let text: String
    }

    enum State: Equatable {
        case idle
        case loading
        case found([Line], synced: Bool)
        case notFound
    }

    private(set) var state: State = .idle

    @ObservationIgnored private var currentKey: String?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var cache: [String: State] = [:]

    private static let userAgent = "Notchland/0.1 (kişisel notch uygulaması)"

    func update(for track: MediaController.Track?) {
        guard let track else {
            task?.cancel()
            currentKey = nil
            state = .idle
            return
        }
        let key = "\(track.title)|\(track.artist)"
        guard key != currentKey else { return }
        currentKey = key
        task?.cancel()

        if let cached = cache[key] {
            state = cached
            return
        }
        state = .loading
        let title = track.title, artist = track.artist, duration = track.duration
        task = Task {
            let result = await Self.fetch(title: title, artist: artist, duration: duration)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self, self.currentKey == key else { return }
                // Ağ hatasında önbelleğe yazma; parça yeniden çalınınca tekrar denensin.
                if let result {
                    self.cache[key] = result
                    self.state = result
                } else {
                    self.state = .notFound
                }
            }
        }
    }

    /// Verilen andaki satırın indeksi (senkron sözlerde).
    static func currentIndex(in lines: [Line], at time: TimeInterval) -> Int? {
        var low = 0, high = lines.count - 1, found: Int?
        while low <= high {
            let mid = (low + high) / 2
            if let t = lines[mid].time, t <= time {
                found = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return found
    }

    // MARK: - Arama

    private struct Record: Decodable {
        let trackName: String?
        let artistName: String?
        let duration: Double?
        let instrumental: Bool?
        let plainLyrics: String?
        let syncedLyrics: String?
    }

    /// nil: ağ hatası, `.notFound`: bulunamadı.
    private static func fetch(title: String, artist: String, duration: TimeInterval) async -> State? {
        var sawNetworkError = false
        for query in queries(title: title, artist: artist) {
            guard let records = await search(query) else {
                sawNetworkError = true
                continue
            }
            if let best = bestMatch(records, duration: duration), let state = state(from: best) {
                return state
            }
        }
        return sawNetworkError ? nil : .notFound
    }

    private static func search(_ items: [URLQueryItem]) async -> [Record]? {
        var components = URLComponents(string: "https://lrclib.net/api/search")!
        components.queryItems = items
        guard let url = components.url else { return [] }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        // LRCLIB yoğunken 503/429 döner; kısa bir beklemeyle birkaç kez dene.
        for attempt in 0..<3 {
            if attempt > 0 { try? await Task.sleep(for: .seconds(Double(attempt) * 1.5)) }
            guard !Task.isCancelled else { return nil }
            guard let (data, response) = try? await URLSession.shared.data(for: request) else { continue }
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            if status == 200 { return (try? JSONDecoder().decode([Record].self, from: data)) ?? [] }
            if status != 429 && status < 500 { return [] }
        }
        return nil
    }

    /// Senkron sözü olanı ve süresi en yakın olanı tercih eder.
    private static func bestMatch(_ records: [Record], duration: TimeInterval) -> Record? {
        let usable = records.filter { $0.syncedLyrics?.isEmpty == false || $0.plainLyrics?.isEmpty == false }
        func score(_ r: Record) -> Double {
            let durationGap = duration > 0 ? abs((r.duration ?? 0) - duration) : 0
            let syncedBonus = r.syncedLyrics?.isEmpty == false ? 0 : 30
            return durationGap + Double(syncedBonus)
        }
        return usable.min { score($0) < score($1) }
    }

    private static func state(from record: Record) -> State? {
        if let synced = record.syncedLyrics, !synced.isEmpty {
            let lines = parseLRC(synced)
            if !lines.isEmpty { return .found(lines, synced: true) }
        }
        if let plain = record.plainLyrics, !plain.isEmpty {
            let lines = plain.components(separatedBy: .newlines).enumerated()
                .map { Line(id: $0.offset, time: nil, text: $0.element) }
            return .found(lines, synced: false)
        }
        return nil
    }

    /// "[01:23.45] metin" satırlarını ayrıştırır; bir satırda birden çok zaman damgası olabilir.
    static func parseLRC(_ lrc: String) -> [Line] {
        let stamp = try! NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]"#)
        var entries: [(TimeInterval, String)] = []
        for raw in lrc.components(separatedBy: .newlines) {
            let ns = raw as NSString
            let matches = stamp.matches(in: raw, range: NSRange(location: 0, length: ns.length))
            guard let last = matches.last else { continue }
            let text = ns.substring(from: last.range.location + last.range.length)
                .trimmingCharacters(in: .whitespaces)
            for match in matches {
                let minutes = Double(ns.substring(with: match.range(at: 1))) ?? 0
                let seconds = Double(ns.substring(with: match.range(at: 2))) ?? 0
                var fraction = 0.0
                if match.range(at: 3).location != NSNotFound {
                    let digits = ns.substring(with: match.range(at: 3))
                    fraction = (Double(digits) ?? 0) / pow(10, Double(digits.count))
                }
                entries.append((minutes * 60 + seconds + fraction, text))
            }
        }
        return entries.sorted { $0.0 < $1.0 }.enumerated()
            .map { Line(id: $0.offset, time: $0.element.0, text: $0.element.1.isEmpty ? "♪" : $0.element.1) }
    }

    // MARK: - Başlık temizleme

    /// Denenecek aramalar, en kesinden en gevşeğe.
    static func queries(title: String, artist: String) -> [[URLQueryItem]] {
        var pairs: [(String, String)] = [(title, artist)]

        let cleanArtist = cleanArtistName(artist)
        var cleanTitle = stripDecorations(title)
        var titleArtist = cleanArtist
        // "Sanatçı - Şarkı" biçimindeki video başlıkları.
        if let range = cleanTitle.range(of: " - ") ?? cleanTitle.range(of: " – ") ?? cleanTitle.range(of: " — ") {
            let before = String(cleanTitle[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let after = String(cleanTitle[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !before.isEmpty, !after.isEmpty {
                titleArtist = before
                cleanTitle = after
            }
        }
        pairs.append((cleanTitle, titleArtist))
        if titleArtist != cleanArtist { pairs.append((cleanTitle, cleanArtist)) }

        var seen = Set<String>()
        var result: [[URLQueryItem]] = []
        for (t, a) in pairs where !t.isEmpty {
            let key = "\(t.lowercased())|\(a.lowercased())"
            guard seen.insert(key).inserted else { continue }
            result.append(a.isEmpty
                ? [URLQueryItem(name: "q", value: t)]
                : [URLQueryItem(name: "track_name", value: t), URLQueryItem(name: "artist_name", value: a)])
        }
        // Son çare: serbest metin araması.
        result.append([URLQueryItem(name: "q", value: "\(titleArtist) \(cleanTitle)")])
        return result
    }

    /// "(Official Video)", "[Lyrics]", "| Live" , "ft. X" gibi eklentileri atar.
    private static func stripDecorations(_ title: String) -> String {
        var s = title
        for pattern in [#"\s*[\(\[【][^\)\]】]*[\)\]】]"#, #"\s*\|.*$"#, #"\s+(ft\.?|feat\.?|featuring)\s+.*$"#] {
            s = s.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    private static func cleanArtistName(_ artist: String) -> String {
        var s = artist
        for pattern in [#"\s*-\s*Topic$"#, #"VEVO$"#, #"\s*(Official|Resmi)(\s+(Channel|Kanal[ıi]?))?$"#] {
            s = s.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        return s.trimmingCharacters(in: .whitespaces)
    }
}
