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
            if synced {
                SyncedLyrics(lines: lines, track: track, media: media)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(lines) { line in
                            Text(line.text).font(.system(size: 12))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
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
    let track: MediaController.Track
    let media: MediaController

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { context in
            let time = track.elapsed(at: context.date) + AppSettings.shared.lyricsOffset
            SyncedLyricsList(lines: lines, current: LyricsService.currentIndex(in: lines, at: time), media: media)
                .equatable()
        }
    }
}

/// Zaman çizelgesi saniyede 5 kez işler; liste yalnızca vurgulanan satır değişince yeniden kurulur.
private struct SyncedLyricsList: View, Equatable {
    let lines: [LyricsService.Line]
    let current: Int?
    let media: MediaController

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.current == rhs.current && lhs.lines == rhs.lines && lhs.media === rhs.media
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(lines) { line in
                        let isCurrent = line.id == current
                        Text(line.text)
                            .font(.system(size: isCurrent ? 15 : 13, weight: isCurrent ? .bold : .medium))
                            .foregroundStyle(isCurrent ? Color.white : Color.white.opacity(0.35))
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
