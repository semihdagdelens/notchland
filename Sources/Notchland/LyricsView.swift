import SwiftUI

/// Çalan parçanın sözleri; senkron sözlerde o anki satır vurgulanır ve ortada tutulur.
struct LyricsView: View {
    let track: MediaController.Track
    let lyrics: LyricsService
    let media: MediaController

    var body: some View {
        switch lyrics.state {
        case .idle, .loading:
            placeholder("Sözler aranıyor…", symbol: "text.magnifyingglass")
        case .notFound:
            placeholder("Söz bulunamadı", symbol: "text.badge.xmark")
        case let .found(lines, synced):
            Group {
                if synced {
                    SyncedLyrics(lines: lines, translations: translations, track: track, media: media)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(lines) { line in
                                Text(line.text).font(.system(size: 12))
                                if let translation = translations[line.id] {
                                    Text(translation)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.white.opacity(0.45))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) { TranslationStatus(translator: lyrics.translator) }
            // Dil paketi Ayarlar'dan indirildiyse notch yeniden açılınca çeviriyi dene.
            .onAppear { lyrics.translator.refresh() }
        }
    }

    private var translations: [Int: String] {
        guard AppSettings.shared.translateLyrics, case let .done(map) = lyrics.translator.state else { return [:] }
        return map
    }

    private func placeholder(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SyncedLyrics: View {
    let lines: [LyricsService.Line]
    let translations: [Int: String]
    let track: MediaController.Track
    let media: MediaController

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { context in
            let time = track.elapsed(at: context.date) + AppSettings.shared.lyricsOffset
            SyncedLyricsList(lines: lines, translations: translations, current: LyricsService.currentIndex(in: lines, at: time), media: media)
                .equatable()
        }
    }
}

/// Zaman çizelgesi saniyede 5 kez işler; liste yalnızca vurgulanan satır değişince yeniden kurulur.
private struct SyncedLyricsList: View, Equatable {
    let lines: [LyricsService.Line]
    let translations: [Int: String]
    let current: Int?
    let media: MediaController

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.current == rhs.current && lhs.lines == rhs.lines && lhs.translations == rhs.translations
            && lhs.media === rhs.media
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(lines) { line in
                        let isCurrent = line.id == current
                        VStack(alignment: .leading, spacing: 1) {
                            Text(line.text)
                                .font(.system(size: isCurrent ? 15 : 13, weight: isCurrent ? .bold : .medium))
                                .foregroundStyle(isCurrent ? Color.white : Color.white.opacity(0.35))
                            if let translation = translations[line.id] {
                                Text(translation)
                                    .font(.system(size: isCurrent ? 12 : 11, weight: .medium))
                                    .foregroundStyle(Color.white.opacity(isCurrent ? 0.6 : 0.22))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        // Satıra tıklayınca o ana atla.
                        .onTapGesture { if let time = line.time { media.seek(to: time) } }
                        .id(line.id)
                    }
                }
                .padding(.vertical, 40)
                .animation(.easeOut(duration: 0.25), value: current)
            }
            .mask(
                LinearGradient(
                    stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.25),
                            .init(color: .black, location: 0.75), .init(color: .clear, location: 1)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .onChange(of: current) { _, index in
                guard let index else { return }
                withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(index, anchor: .center) }
            }
            .onAppear {
                if let current { proxy.scrollTo(current, anchor: .center) }
            }
        }
    }
}

/// Çeviri sürerken ya da dil paketi eksikken sözlerin köşesindeki küçük not.
private struct TranslationStatus: View {
    let translator: LyricsTranslator

    var body: some View {
        if AppSettings.shared.translateLyrics {
            switch translator.state {
            case .translating:
                chip("Çevriliyor…", symbol: "translate")
            case let .needsDownload(language):
                Button(action: LyricsTranslator.openLanguageSettings) {
                    chip("\(language) paketini indir", symbol: "arrow.down.circle")
                }
                .buttonStyle(.plain)
                .help("Sistem Ayarları › Dil ve Bölge › Çeviri Dilleri'nden indir; notch'u yeniden açınca çevrilir.")
            default:
                EmptyView()
            }
        }
    }

    private func chip(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.7))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.white.opacity(0.12)))
    }
}
