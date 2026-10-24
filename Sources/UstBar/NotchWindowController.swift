import AppKit
import ApplicationServices
import SwiftUI

/// Notch'un etrafında duran, saydam ve odak çalmayan panel.
final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar + 1
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = true
    }

    /// Klavye odağı normalde öndeki uygulamada kalır (pano ⌘V'si oraya gitsin); yalnızca
    /// yazı yazılabilen sekmede (notlar) bir metin alanına tıklanınca panel odak alır.
    var allowsKeyFocus: () -> Bool = { false }

    override var canBecomeKey: Bool { allowsKeyFocus() }
    override var canBecomeMain: Bool { false }

    /// Klavye odağını öndeki uygulamaya geri verir. Panel uygulamayı etkinleştirmediği için
    /// kısa bir an gizleyip göstermek, odağın etkin uygulamanın penceresine dönmesini sağlar.
    static func releaseKeyFocus() {
        for case let panel as NotchPanel in NSApp.windows where panel.isKeyWindow {
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
    }
}

final class NotchWindowController {
    static let expandedSize = CGSize(width: 600, height: 190)
    /// Dikte paneli; panel çerçevesi `expandedSize`'a göre olduğundan ondan büyük olmamalı.
    static let dictationSize = CGSize(width: 520, height: 120)
    /// Dışa kıvrılan üst köşeler ve gölge için panelin notch'tan taşan payı.
    private static let panelMargin: CGFloat = 32
    /// Sürükleme sırasında notch'u açan, notch'tan daha geniş bölge.
    private static let dragActivationSize = CGSize(width: 360, height: 90)

    private let state = NotchState()
    private let media = MediaController()
    private let shelf = ShelfStore()
    private let battery = BatteryMonitor()
    private let volume = VolumeController()
    private let brightness = BrightnessController()
    let keyTap = MediaKeyTap()
    private let calendar = CalendarService()
    private let weather = WeatherService()
    private let clipboard = ClipboardStore()
    private let lyrics = LyricsService()
    private let stats = SystemStats()
    private let dictation = DictationService()
    private let headphones = HeadphoneMonitor()
    private let reminders = RemindersService()
    private let notes = NotesService()
    private let notificationMirror = NotificationMirror()
    private let hotKey = GlobalHotKey()
    private var panel: NotchPanel?
    private var mouseMonitors: [Any] = []
    private let settings = AppSettings.shared
    /// Açılma gecikmesi ayarı için bekleyen açılış.
    private var pendingExpand: DispatchWorkItem?

    /// Fare basıldığında sürükleme panosunun sayacı; değişirse içerik sürükleniyor demektir.
    private var dragChangeCountAtMouseDown = NSPasteboard(name: .drag).changeCount

    func show() {
        let panel = NotchPanel(contentRect: .zero)
        let root = NotchView(
            state: state, media: media, shelf: shelf, battery: battery, calendar: calendar, weather: weather,
            clipboard: clipboard, lyrics: lyrics, stats: stats,
            dictation: dictation, headphones: headphones,
            reminders: reminders, notes: notes,
            onDictationToggle: { [weak self] in self?.toggleDictation() }
        )
        panel.contentView = NSHostingView(rootView: root)
        panel.allowsKeyFocus = { [weak self] in
            guard let self else { return false }
            return self.state.isExpanded && (self.state.tab == .notes || self.state.tab == .calculator)
        }
        self.panel = panel
        reposition()
        panel.orderFrontRegardless()
        startMouseTracking()
        media.onTrackChange = { [weak self] track in self?.lyrics.update(for: track) }
        media.start()
        startSystemHUDs()

        calendar.onUpcoming = { [weak self] event in self?.state.present(.event(event)) }
        calendar.start()
        weather.start()
        clipboard.start()
        startDictation()

        headphones.onConnect = { [weak self] device in
            guard self?.settings.headphoneHUD == true else { return }
            self?.state.present(.headphones(device))
        }
        headphones.start()
        notificationMirror.onNotice = { [weak self] notice in
            guard let self, self.settings.mirrorNotifications, !self.state.isExpanded, !self.dictation.isActive else { return }
            self.state.present(.notification(notice))
        }
        notificationMirror.start()
    }


    // MARK: - Dikte

    private func startDictation() {
        dictation.onFinish = { [weak self] text in self?.deliver(text) ?? false }
        dictation.onClose = { [weak self] in
            guard let self else { return }
            self.panel?.ignoresMouseEvents = !self.state.isExpanded
            self.updateHover()
        }
        hotKey.onPress = { [weak self] in self?.toggleDictation() }
        observeHotKeySetting()
    }

    /// Ayardaki kısayolu kaydeder ve ayar her değiştiğinde yeniden kaydeder.
    private func observeHotKeySetting() {
        let combo = withObservationTracking {
            settings.dictationHotKey.combo
        } onChange: { [weak self] in
            DispatchQueue.main.async { self?.observeHotKeySetting() }
        }
        hotKey.register(combo)
    }

    private func toggleDictation() {
        switch dictation.phase {
        case .idle, .done, .failed:
            pendingExpand?.cancel()
            pendingExpand = nil
            withAnimation(.spring(response: 0.42, dampingFraction: 0.76)) {
                state.isHovering = false
                state.isExpanded = false
                dictation.start()
            }
            panel?.ignoresMouseEvents = false
        case .listening:
            dictation.stop()
        case .preparing:
            dictation.cancel()
        case .finishing:
            break
        }
    }

    /// Metni panoya koyar, izin ve ayar varsa öndeki uygulamaya ⌘V gönderir.
    /// Panel odak almadığı için klavye odağı hâlâ dikteden önceki uygulamadadır.
    private func deliver(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        guard settings.dictationAutoPaste, AXIsProcessTrusted() else { return false }
        // Kısayolun değiştirici tuşları hâlâ basılı olabilir; bayraklar açıkça yalnızca ⌘.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let source = CGEventSource(stateID: .combinedSessionState)
            let vKey: CGKeyCode = 9
            for isDown in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: isDown)
                event?.flags = .maskCommand
                event?.post(tap: .cghidEventTap)
            }
        }
        return true
    }

    // MARK: - Ses, parlaklık, pil

    private func startSystemHUDs() {
        battery.onPowerSourceChange = { [weak self] status in
            guard self?.settings.batteryHUD == true else { return }
            self?.state.present(.battery(status))
        }
        battery.onLowBattery = { [weak self] status in self?.state.present(.battery(status)) }
        battery.start()

        // HUD ses değişikliğinin kendisinden tetiklenir; böylece başka yerden yapılan değişiklikler de görünür.
        volume.onChange = { [weak self] s in
            guard self?.settings.volumeHUD == true else { return }
            self?.state.present(.volume(level: s.level, isMuted: s.isMuted, isHeadphones: s.isHeadphones))
        }
        volume.start()

        keyTap.onKey = { [weak self] key, fine in
            self?.handleKey(key, fine: fine) ?? false
        }
        keyTap.start()
    }

    /// Olay yutulduysa (sistem HUD'u bastırıldıysa) true döner.
    private func handleKey(_ key: MediaKeyTap.Key, fine: Bool) -> Bool {
        let step: Float = fine ? 1 / 64 : 1 / 16
        switch key {
        case .volumeUp, .volumeDown:
            guard settings.volumeHUD else { return false }
            let direction: Float = key == .volumeUp ? 1 : -1
            // Adım ızgarasına oturt ki 16 basışta tam 0/1'e ulaşılsın.
            let before = volume.state
            volume.setLevel(((before.level / step).rounded() + direction) * step)
            let after = volume.state
            if after == before {
                // Zaten sınırdaysa (0 veya 1) dinleyici tetiklenmez; HUD'u yine de göster.
                state.present(.volume(level: after.level, isMuted: after.isMuted, isHeadphones: after.isHeadphones))
            }
            return true
        case .mute:
            guard settings.volumeHUD else { return false }
            volume.setMuted(!volume.isMuted)
            return true
        case .brightnessUp, .brightnessDown:
            guard settings.brightnessHUD, brightness.isAvailable else { return false }
            let direction: Float = key == .brightnessUp ? 1 : -1
            let target = min(max(((brightness.level / step).rounded() + direction) * step, 0), 1)
            brightness.setLevel(target)
            state.present(.brightness(level: target))
            return true
        }
    }

    /// Paneli notch'lu (yoksa ana) ekranın üst ortasına yerleştirir.
    func reposition() {
        guard let panel, let screen = Self.targetScreen() else { return }
        state.closedSize = Self.notchSize(on: screen)
        let size = CGSize(
            width: Self.expandedSize.width + Self.panelMargin * 2,
            height: Self.expandedSize.height + Self.panelMargin
        )
        let frame = screen.frame
        panel.setFrame(
            NSRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height, width: size.width, height: size.height),
            display: true
        )
    }

    private static func targetScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    /// Fiziksel notch boyutu; notch yoksa menü çubuğu yüksekliğinde sahte bir notch.
    private static func notchSize(on screen: NSScreen) -> CGSize {
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            return CGSize(width: screen.frame.width - left.width - right.width, height: screen.safeAreaInsets.top)
        }
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        return CGSize(width: 200, height: max(menuBarHeight, 24))
    }

    // MARK: - Fare takibi

    private func startMouseTracking() {
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] event in
            self?.handle(event)
        }) {
            mouseMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            self?.handle(event)
            return event
        }) {
            mouseMonitors.append(local)
        }
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            dragChangeCountAtMouseDown = NSPasteboard(name: .drag).changeCount
            // Yazarken notch dışına tıklanırsa yazmayı bırak; notch fare çıkınca kapanabilsin.
            if state.isEditingText, let panel, !Self.expandedRect(in: panel.frame).contains(NSEvent.mouseLocation) {
                state.isEditingText = false
                NotchPanel.releaseKeyFocus()
            }
        case .leftMouseUp:
            // Bırakma alanları, bırakma işlenmeden kaybolmasın diye biraz bekle.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, NSEvent.pressedMouseButtons & 1 == 0 else { return }
                self.state.isDraggingContent = false
                self.state.isDraggingFromShelf = false
                self.updateHover()
            }
            return
        case .leftMouseDragged:
            if NSPasteboard(name: .drag).changeCount != dragChangeCountAtMouseDown {
                state.isDraggingContent = true
            }
        default:
            break
        }
        updateHover()
    }

    private func updateHover() {
        guard let panel else { return }
        // Raftan bir dosya dışarı sürüklenirken notch kapanırsa sürükleme kaynağı kaybolur.
        if state.isDraggingFromShelf { return }
        // Dikte paneli fareden bağımsız; kısayol veya düğmeyle kapanır.
        if dictation.isActive { return }
        // Not yazılırken fare dışarı kaysa da açık kalır; dışarı tıklanınca kapanır.
        if state.isEditingText && state.isExpanded { return }

        let mouse = NSEvent.mouseLocation
        let frame = panel.frame
        let activeSize: CGSize
        if state.isExpanded {
            activeSize = Self.expandedSize
        } else if state.isDraggingContent {
            activeSize = Self.dragActivationSize
        } else {
            // Kapalıyken notch'un biraz altına kadar tetikleme payı bırak; çalarken yanlardaki kapak ve dalga da dahil.
            let ears = LiveActivity.isShown(state: state, media: media, isDictating: dictation.isActive)
                ? LiveActivity.earWidth(notchHeight: state.closedSize.height) * 2 : 0
            activeSize = CGSize(width: state.closedSize.width + ears, height: state.closedSize.height + 6)
        }
        let activeRect = NSRect(
            x: frame.midX - activeSize.width / 2,
            y: frame.maxY - activeSize.height,
            width: activeSize.width,
            height: activeSize.height
        )
        let inside = activeRect.contains(mouse)
        let peeking = inside && !state.isExpanded
        if peeking != state.isHovering {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { state.isHovering = peeking }
        }
        if !inside {
            pendingExpand?.cancel()
            pendingExpand = nil
        }
        guard inside != state.isExpanded else { return }

        // Sürüklerken gecikme yok; normal üzerine gelmede ayardaki kadar bekle.
        if inside && !state.isDraggingContent && settings.hoverDelay > 0 {
            guard pendingExpand == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                self?.pendingExpand = nil
                self?.setExpanded(true)
            }
            pendingExpand = work
            DispatchQueue.main.asyncAfter(deadline: .now() + settings.hoverDelay, execute: work)
            return
        }
        setExpanded(inside)
    }

    private static func expandedRect(in frame: NSRect) -> NSRect {
        NSRect(
            x: frame.midX - expandedSize.width / 2, y: frame.maxY - expandedSize.height,
            width: expandedSize.width, height: expandedSize.height
        )
    }

    private func setExpanded(_ expanded: Bool) {
        guard let panel, expanded != state.isExpanded else { return }
        if expanded {
            if state.isDraggingContent && settings.showShelfTab {
                state.tab = .shelf
            }
            if !state.isTabEnabled(state.tab) { state.tab = .home }
            if settings.hapticFeedback {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
        } else {
            state.isEditingText = false
            NotchPanel.releaseKeyFocus()
        }
        // Açılış hafif sekerek, kapanış sekmeden ve biraz daha çabuk.
        let animation: Animation = expanded
            ? .spring(response: 0.42, dampingFraction: 0.76)
            : .spring(response: 0.36, dampingFraction: 0.95)
        withAnimation(animation) {
            state.isHovering = false
            state.isExpanded = expanded
        }
        panel.ignoresMouseEvents = !expanded
    }

    func reloadWeather() {
        weather.reload()
    }
}

@Observable
final class NotchState {
    enum Tab: Hashable {
        case home
        case calendar
        case clipboard
        case stats
        case notes
        case calculator
        case shelf
    }

    var isExpanded = false
    /// Notlar sekmesinde bir metin alanı odakta (notch fare çıksa da açık kalır).
    var isEditingText = false
    /// Fare kapalı notch'un üzerinde (açılma gecikmesi sırasında hafif büyüme).
    var isHovering = false
    var closedSize = CGSize(width: 200, height: 32)
    var tab: Tab = .home
    /// Ana sayfada şarkı sözleri paneli açık mı (kalıcı).
    var showLyrics = UserDefaults.standard.bool(forKey: "showLyrics") {
        didSet { UserDefaults.standard.set(showLyrics, forKey: "showLyrics") }
    }
    /// Başka bir uygulamadan dosya/içerik sürükleniyor.
    var isDraggingContent = false
    /// Raftaki bir öğe dışarı sürükleniyor.
    var isDraggingFromShelf = false
    /// Kapalı notch'ta gösterilen kısa bildirim (ses, parlaklık, pil).
    private(set) var hud: HUD?

    @ObservationIgnored private var hudDismissal: DispatchWorkItem?

    func isTabEnabled(_ tab: Tab) -> Bool {
        let settings = AppSettings.shared
        switch tab {
        case .home: return true
        case .calendar: return settings.showCalendarTab
        case .clipboard: return settings.showClipboardTab
        case .stats: return settings.showStatsTab
        case .notes: return settings.showNotesTab
        case .calculator: return settings.showCalculatorTab
        case .shelf: return settings.showShelfTab
        }
    }

    func select(_ newTab: Tab) {
        guard newTab != tab else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) { tab = newTab }
    }

    func present(_ newHUD: HUD) {
        let animate = hud == nil
        if animate {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { hud = newHUD }
        } else {
            hud = newHUD
        }
        hudDismissal?.cancel()
        let dismissal = DispatchWorkItem { [weak self] in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { self?.hud = nil }
        }
        hudDismissal = dismissal
        DispatchQueue.main.asyncAfter(deadline: .now() + newHUD.duration, execute: dismissal)
    }
}
