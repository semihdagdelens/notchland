import SwiftUI

struct NotchView: View {
    let state: NotchState
    let media: MediaController
    let shelf: ShelfStore
    let battery: BatteryMonitor
    let calendar: CalendarService
    let weather: WeatherService
    let clipboard: ClipboardStore
    let lyrics: LyricsService
    let stats: SystemStats
    let dictation: DictationService
    let headphones: HeadphoneMonitor
    let reminders: RemindersService
    let notes: NotesService
    let onDictationToggle: () -> Void

    @State private var isDropTargeted = false

    /// Notch açık mı (üzerine gelinerek veya dikte için).
    private var isOpen: Bool { state.isExpanded || dictation.isActive }

    /// Ana sayfada ve bir şey çalarken arka plan kapağın rengine bürünür.
    /// Görünürlük (`isExpanded`) ayrı tutulur ki renk, şekil açıldıktan sonra belirsin.
    private var artworkTint: NSColor? {
        guard !dictation.isActive, state.tab == .home,
              AppSettings.shared.artworkBackground, media.track != nil else { return nil }
        return media.artworkColor
    }

    private var size: CGSize {
        if dictation.isActive { return NotchWindowController.dictationSize }
        if state.isExpanded { return NotchWindowController.expandedSize }
        var size = state.closedSize
        if let hud = state.hud {
            size.width += hud.earWidth * 2
            size.height += hud.extraHeight
        }
        if showsLiveActivity { size.width += LiveActivity.earWidth(notchHeight: state.closedSize.height) * 2 }
        // Üzerine gelince açılmadan önce hafifçe "nefes alır".
        if state.isHovering {
            size.width += 14
            size.height += 3
        }
        return size
    }

    /// Ekrana yapışan üst köşelerin dışa kıvrılma yarıçapı.
    private var topRadius: CGFloat { isOpen ? 14 : 6 }
    private var bottomRadius: CGFloat {
        if isOpen { return 28 }
        if let hud = state.hud, hud.extraHeight > 0 { return 20 }
        return state.isHovering ? 12 : 10
    }

    private var showsLiveActivity: Bool {
        LiveActivity.isShown(state: state, media: media, isDictating: dictation.isActive)
    }

    /// İçerik değiştiğinde (sekme, bırakma alanları) geçişi tetikleyen kimlik.
    private var contentID: String {
        state.isDraggingContent && !state.isDraggingFromShelf ? "drop" : "\(state.tab)"
    }

    var body: some View {
        let size = size
        let shape = NotchShape(topRadius: topRadius, bottomRadius: bottomRadius)

        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                if dictation.isActive {
                    DictationView(
                        dictation: dictation,
                        notchWidth: state.closedSize.width,
                        notchHeight: state.closedSize.height,
                        onToggle: onDictationToggle
                    )
                    .foregroundStyle(.white)
                    .environment(\.colorScheme, .dark)
                    .transition(.notchContent)
                } else if !state.isExpanded, let hud = state.hud, !hud.usesBubble {
                    HUDContent(hud: hud, notchWidth: state.closedSize.width, notchHeight: state.closedSize.height)
                        .frame(height: state.closedSize.height + hud.extraHeight)
                        .transition(.blurFade(scale: 0.9))
                } else if showsLiveActivity, let track = media.track {
                    LiveActivityView(
                        track: track, tint: media.artworkColor,
                        notchWidth: state.closedSize.width, notchHeight: state.closedSize.height
                    )
                    .transition(.blurFade(scale: 0.9))
                }

                if state.isExpanded && !dictation.isActive {
                    VStack(spacing: 10) {
                        TabBar(state: state, battery: battery, headphones: headphones, closedWidth: state.closedSize.width)
                            .frame(height: state.closedSize.height)
                        Group {
                            if state.isDraggingContent && !state.isDraggingFromShelf {
                                DropZonesView(shelf: shelf)
                            } else {
                            switch state.tab {
                            case .home:
                                HomeContent(state: state, media: media, weather: weather, lyrics: lyrics)
                            case .calendar:
                                CalendarTabView(calendar: calendar, weather: weather)
                            case .clipboard:
                                ClipboardView(clipboard: clipboard)
                            case .stats:
                                StatsView(stats: stats)
                            case .notes:
                                NotesTabView(state: state, reminders: reminders, notes: notes)
                            case .calculator:
                                CalculatorView()
                            case .shelf:
                                ShelfView(state: state, shelf: shelf, isDropTargeted: isDropTargeted)
                            }
                            }
                        }
                        .id(contentID)
                        .transition(.blurFade(scale: 0.97))
                        .frame(maxHeight: .infinity)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                    .foregroundStyle(.white)
                    .environment(\.colorScheme, .dark)
                    .transition(.notchContent)
                }
            }
            .frame(width: size.width, height: size.height)
            .frame(width: size.width + topRadius * 2)
            .mask { shape }
            .background {
                shape
                    .fill(Color.black)
                    .overlay { ArtworkTint(color: artworkTint, isVisible: state.isExpanded, shape: shape) }
                    .shadow(color: .black.opacity(isOpen ? 0.5 : 0), radius: 16, y: 6)
            }
            // Ses/parlaklık/pil baloncuğu: yerel x = 0, gövdenin sağ kenarına (omzun içine) oturur.
            .overlay(alignment: .topTrailing) {
                HUDBubble(hud: state.hud, isExpanded: isOpen, notchHeight: state.closedSize.height)
                    .alignmentGuide(.trailing) { _ in topRadius }
            }
            .onDrop(of: ShelfStore.acceptedTypes, isTargeted: $isDropTargeted) { providers in
                guard state.isTabEnabled(.shelf) else { return false }
                state.tab = .shelf
                return shelf.handleDrop(providers)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: isDropTargeted) { _, targeted in
            if targeted && state.isTabEnabled(.shelf) { state.select(.shelf) }
        }
    }
}

/// Notch'un iki yanındaki "kulaklara" yerleşen sekme düğmeleri.
private struct TabBar: View {
    let state: NotchState
    let battery: BatteryMonitor
    let headphones: HeadphoneMonitor
    let closedWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 14) {
                TabButton(symbol: "house.fill", isSelected: state.tab == .home) { state.select(.home) }
                if state.isTabEnabled(.calendar) {
                    TabButton(symbol: "calendar", isSelected: state.tab == .calendar) { state.select(.calendar) }
                }
                if state.isTabEnabled(.clipboard) {
                    TabButton(symbol: "doc.on.clipboard.fill", isSelected: state.tab == .clipboard) { state.select(.clipboard) }
                }
                if state.isTabEnabled(.stats) {
                    TabButton(symbol: "gauge.with.dots.needle.50percent", isSelected: state.tab == .stats) { state.select(.stats) }
                }
                if state.isTabEnabled(.notes) {
                    TabButton(symbol: "checklist", isSelected: state.tab == .notes) { state.select(.notes) }
                }
                if state.isTabEnabled(.calculator) {
                    TabButton(symbol: "plus.forwardslash.minus", isSelected: state.tab == .calculator) { state.select(.calculator) }
                }
                if state.isTabEnabled(.shelf) {
                    TabButton(symbol: "tray.fill", isSelected: state.tab == .shelf) { state.select(.shelf) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Gerçek notch'un altında kalan bölge boş kalır.
            Color.clear.frame(width: closedWidth)
            HStack(spacing: 12) {
                if let device = headphones.current, let level = device.budsLevel {
                    HStack(spacing: 4) {
                        Text("%\(level)")
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        Image(systemName: device.symbol)
                            .font(.system(size: 12))
                    }
                    .help(device.caseLevel.map { "\(device.name) · Kutu %\($0)" } ?? device.name)
                }
                BatteryBadge(battery: battery)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

private struct TabButton: View {
    let symbol: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.4))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Ana sayfa

private struct HomeContent: View {
    let state: NotchState
    let media: MediaController
    let weather: WeatherService
    let lyrics: LyricsService

    var body: some View {
        HStack(spacing: 16) {
            if let track = media.track, state.showLyrics {
                NowPlayingView(track: track, media: media, state: state)
                    .frame(width: 250)
                LyricsView(track: track, lyrics: lyrics, media: media)
            } else if let track = media.track {
                NowPlayingView(track: track, media: media, state: state)
            } else {
                Text("Çalan bir şey yok")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if media.track == nil || !state.showLyrics {
                VStack(alignment: .trailing, spacing: 6) {
                    ClockView()
                    WeatherBadge(weather: weather)
                }
            }
        }
    }
}

private struct NowPlayingView: View {
    let track: MediaController.Track
    let media: MediaController
    let state: NotchState

    var body: some View {
        HStack(spacing: 14) {
            ArtworkView(track: track)
                .frame(width: 72, height: 72)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(track.title).font(.headline).lineLimit(1)
                    Spacer(minLength: 0)
                    if AppSettings.shared.liveActivity {
                        VisualizerBars(
                            isPlaying: track.isPlaying,
                            color: Color(nsColor: media.artworkColor.map(LiveActivity.barColor) ?? .white)
                        )
                        .frame(width: 20, height: 14)
                    }
                }
                Text(track.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                if track.duration > 0 {
                    ProgressBar(track: track)
                }
                HStack(spacing: 22) {
                    MediaButton(symbol: "backward.fill") { media.previous() }
                    MediaButton(symbol: track.isPlaying ? "pause.fill" : "play.fill") { media.playPause() }
                    MediaButton(symbol: "forward.fill") { media.next() }
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { state.showLyrics.toggle() }
                    } label: {
                        Image(systemName: "quote.bubble.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(state.showLyrics ? Color.white : Color.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .help("Şarkı sözleri")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ArtworkView: View {
    let track: MediaController.Track

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let artwork = track.artwork {
                    Image(nsImage: artwork).resizable().scaledToFill()
                } else {
                    Image(systemName: "music.note")
                        .font(.title)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.white.opacity(0.1))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Hangi uygulamadan çaldığını gösteren küçük ikon (Chrome, Safari, Spotify…).
            if let icon = SourceAppIcon.icon(for: track.bundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 24, height: 24)
                    .offset(x: 6, y: 6)
            }
        }
    }
}

enum SourceAppIcon {
    private static var cache: [String: NSImage] = [:]

    static func icon(for bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = cache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleID] = icon
        return icon
    }
}

private struct ProgressBar: View {
    let track: MediaController.Track

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let elapsed = track.elapsed(at: context.date)
            HStack(spacing: 8) {
                Text(Self.format(elapsed))
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.2))
                        Capsule().fill(Color.white)
                            .frame(width: proxy.size.width * min(1, elapsed / track.duration))
                    }
                }
                .frame(height: 4)
                Text(Self.format(track.duration))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct MediaButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16, weight: .semibold))
        }
        .buttonStyle(.plain)
    }
}

private struct ClockView: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .trailing, spacing: 2) {
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(context.date, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Üst köşeleri ekrana doğru dışa kıvrılan, alt köşeleri yuvarlatılmış notch şekli.
/// Gövde, `topRadius` kadar içeriden başlar; kıvrımlar bu payın içine çizilir.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let t = min(topRadius, rect.width / 4, rect.height / 2)
        let left = rect.minX + t
        let right = rect.maxX - t
        let b = min(bottomRadius, (rect.height - t), (right - left) / 2)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: left, y: rect.minY + t), control: CGPoint(x: left, y: rect.minY))
        path.addLine(to: CGPoint(x: left, y: rect.maxY - b))
        path.addQuadCurve(to: CGPoint(x: left + b, y: rect.maxY), control: CGPoint(x: left, y: rect.maxY))
        path.addLine(to: CGPoint(x: right - b, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: right, y: rect.maxY - b), control: CGPoint(x: right, y: rect.maxY))
        path.addLine(to: CGPoint(x: right, y: rect.minY + t))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: right, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Geçişler

/// Bulanıklık, saydamlık ve ölçeği birlikte süren geçiş durumu.
private struct BlurFade: ViewModifier {
    let blur: CGFloat
    let opacity: Double
    let scale: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale, anchor: .top)
            .blur(radius: blur)
            .opacity(opacity)
    }
}

extension AnyTransition {
    static func blurFade(scale: CGFloat) -> AnyTransition {
        .modifier(
            active: BlurFade(blur: 8, opacity: 0, scale: scale),
            identity: BlurFade(blur: 0, opacity: 1, scale: 1)
        )
    }

    /// Açılışta şekil önce genişler, içerik biraz gecikmeyle bulanıklıktan netleşir;
    /// kapanışta içerik şekilden önce hızla söner.
    static var notchContent: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: BlurFade(blur: 12, opacity: 0, scale: 0.92),
                identity: BlurFade(blur: 0, opacity: 1, scale: 1)
            )
            .animation(.spring(response: 0.42, dampingFraction: 0.86).delay(0.07)),
            removal: .modifier(
                active: BlurFade(blur: 8, opacity: 0, scale: 0.95),
                identity: BlurFade(blur: 0, opacity: 1, scale: 1)
            )
            .animation(.easeOut(duration: 0.15))
        )
    }
}
