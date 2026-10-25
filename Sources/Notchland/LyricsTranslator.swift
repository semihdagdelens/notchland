import AppKit
import NaturalLanguage
import Translation

/// Yabancı şarkı sözlerini satır satır Türkçeye çevirir. macOS'un cihaz içi çevirisi kullanılır, ağa çıkmaz.
/// Dil paketi yüklü değilse indirmek kullanıcıya bırakılır (Sistem Ayarları › Dil ve Bölge).
@Observable
final class LyricsTranslator {
    enum State: Equatable {
        case idle
        /// Sözler zaten Türkçe ya da dili anlaşılamadı.
        case notNeeded
        case translating
        /// Dil paketi indirilmemiş; dilin Türkçe adı.
        case needsDownload(String)
        case unsupported
        case failed
        /// Satır kimliği → çeviri; çevirisi kaynakla aynı olan satırlar yok.
        case done([Int: String])
    }

    private(set) var state: State = .idle

    @ObservationIgnored private var key: String?
    @ObservationIgnored private var lines: [LyricsService.Line] = []
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var cache: [String: State] = [:]

    private static let target = Locale.Language(identifier: "tr")

    init() {
        observeSetting()
    }

    /// Bulunan sözler değişince çağrılır; ayar kapalıysa sözler yalnızca saklanır.
    func update(key: String?, lines: [LyricsService.Line]) {
        guard key != self.key || lines != self.lines else { return }
        self.key = key
        self.lines = lines
        task?.cancel()
        state = .idle
        refresh()
    }

    /// Ayar açılınca ya da dil paketi indirildikten sonra (indirme ve hata sonuçları önbelleğe yazılmaz) yeniden dener.
    func refresh() {
        guard AppSettings.shared.translateLyrics, let key, !lines.isEmpty else { return }
        if let cached = cache[key] {
            state = cached
            return
        }
        guard state != .translating else { return }
        state = .translating
        let lines = lines
        task = Task {
            let result = await Self.translate(lines)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self, self.key == key else { return }
                switch result {
                case .done, .notNeeded, .unsupported: self.cache[key] = result
                default: break
                }
                self.state = result
            }
        }
    }

    /// Dil paketlerinin indirildiği Dil ve Bölge ayarlarını açar.
    static func openLanguageSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    private func observeSetting() {
        _ = withObservationTracking {
            AppSettings.shared.translateLyrics
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.observeSetting()
                self?.refresh()
            }
        }
    }

    // MARK: - Çeviri

    private static func translate(_ lines: [LyricsService.Line]) async -> State {
        let texts = lines.map(\.text).filter { $0 != "♪" && !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(texts.joined(separator: "\n"))
        guard let language = recognizer.dominantLanguage, language != .undetermined, language != .turkish else {
            return .notNeeded
        }
        // Yalnızca yüklü dil paketiyle, arayüz göstermeden oturum açmak macOS 26 ister.
        guard #available(macOS 26.0, *) else { return .unsupported }

        let source = Locale.Language(identifier: language.rawValue)
        switch await LanguageAvailability().status(from: source, to: target) {
        case .installed: break
        case .supported:
            let name = Locale(identifier: "tr").localizedString(forLanguageCode: language.rawValue) ?? language.rawValue
            return .needsDownload(name)
        case .unsupported: return .unsupported
        @unknown default: return .unsupported
        }

        // Nakarat gibi tekrarlanan satırlar bir kez çevrilir.
        let unique = Array(Set(texts))
        let session = TranslationSession(installedSource: source, target: target)
        do {
            let responses = try await session.translations(from: unique.map { .init(sourceText: $0) })
            var byText: [String: String] = [:]
            for response in responses { byText[response.sourceText] = response.targetText }
            var result: [Int: String] = [:]
            for line in lines {
                guard let translated = byText[line.text],
                      translated.caseInsensitiveCompare(line.text) != .orderedSame else { continue }
                result[line.id] = translated
            }
            return .done(result)
        } catch {
            NSLog("[Notchland] Sözler çevrilemedi: \(error.localizedDescription)")
            return .failed
        }
    }
}
