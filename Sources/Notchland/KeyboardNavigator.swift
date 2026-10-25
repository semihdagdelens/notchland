import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Klavyeyle gezinme: kısayol notch'u açıp paneli klavye odağına alır; tuşlar sekmeleri
/// ve sekme içi eylemleri sürer. Fare ile açılan notch'ta odak yine öndeki uygulamada kalır.
final class KeyboardNavigator {
    /// Kısayola basıldı (controller notch'u klavye modunda açar ya da kapatır).
    var onToggle: (() -> Void)?
    /// Esc veya başka bir uygulamaya geçiş.
    var onClose: (() -> Void)?

    private let state: NotchState
    private let media: MediaController
    private let hotKey = GlobalHotKey(id: 2)
    private var keyMonitor: Any?
    private var activationObserver: Any?

    init(state: NotchState, media: MediaController) {
        self.state = state
        self.media = media
    }

    func start() {
        hotKey.onPress = { [weak self] in self?.onToggle?() }
        observeHotKeySetting()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.handle(event) else { return event }
            return nil
        }
        // ⌘Tab vb. ile başka uygulamaya geçilirse klavye modu biter.
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let self, self.state.isKeyboardActive, app != .current else { return }
            self.onClose?()
        }
    }

    /// Ayardaki kısayolu kaydeder ve ayar her değiştiğinde yeniden kaydeder.
    private func observeHotKeySetting() {
        let combo = withObservationTracking {
            AppSettings.shared.navigationHotKey.combo
        } onChange: { [weak self] in
            DispatchQueue.main.async { self?.observeHotKeySetting() }
        }
        hotKey.register(combo)
    }

    /// Tuş işlendiyse (yutulmalıysa) true döner.
    private func handle(_ event: NSEvent) -> Bool {
        guard state.isKeyboardActive, state.isExpanded, event.window is NotchPanel else { return false }
        // Bir metin alanında yazarken tuşlar alana gider (Esc alanın kendi işi).
        if state.isEditingText || event.window?.firstResponder is NSText { return false }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let command = flags.contains(.command)
        let key = Int(event.keyCode)
        let characters = event.charactersIgnoringModifiers?.lowercased() ?? ""

        switch key {
        case kVK_Escape:
            onClose?()
            return true
        case kVK_Tab:
            state.selectAdjacent(flags.contains(.shift) ? -1 : 1)
            return true
        default:
            break
        }
        if command, let number = Int(characters), (1...9).contains(number) {
            let tabs = state.enabledTabs
            if number <= tabs.count { state.select(tabs[number - 1]) }
            return true
        }

        switch state.tab {
        // Hesap makinesi rakam ve işlem tuşlarını kendisi alır; yön tuşlarını kullanmaz.
        case .calculator:
            guard key == kVK_LeftArrow || key == kVK_RightArrow else { return false }
        case .home:
            if key == kVK_Space {
                media.playPause()
                return true
            }
            if command && (key == kVK_LeftArrow || key == kVK_RightArrow) {
                key == kVK_RightArrow ? media.next() : media.previous()
                return true
            }
            if characters == "l" && flags.isDisjoint(with: [.command, .control, .option]) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { state.showLyrics.toggle() }
                return true
            }
            if characters == "t" && flags.isDisjoint(with: [.command, .control, .option]) && state.showLyrics {
                AppSettings.shared.translateLyrics.toggle()
                return true
            }
        // Panoda liste, notlarda yeni hatırlatıcı / yeni not arasında seçim.
        case .clipboard, .notes:
            let isClipboard = state.tab == .clipboard
            let kind: NotchState.KeyCommand.Kind? = switch key {
            case kVK_UpArrow: .up
            case kVK_DownArrow: .down
            case kVK_Return, kVK_ANSI_KeypadEnter: .enter
            case kVK_Delete, kVK_ForwardDelete where isClipboard: .delete
            case kVK_ANSI_C where command && isClipboard: .copy
            default: nil
            }
            if let kind {
                state.keyCommand = NotchState.KeyCommand(kind: kind)
                return true
            }
        default:
            break
        }

        if key == kVK_LeftArrow || key == kVK_RightArrow {
            state.selectAdjacent(key == kVK_RightArrow ? 1 : -1)
            return true
        }
        return false
    }
}

extension NotchState {
    /// Klavyeyle gezinmede sekme içeriğine iletilen komut; her basış yeni bir kimlik taşır.
    struct KeyCommand: Equatable {
        enum Kind { case up, down, enter, copy, delete }
        let kind: Kind
        let id = UUID()
    }

    /// Ayarlarda açık sekmeler, sekme çubuğundaki sırayla.
    var enabledTabs: [Tab] { Tab.allCases.filter(isTabEnabled) }

    /// Açık sekmeler arasında (başa/sona sararak) ileri veya geri gider.
    func selectAdjacent(_ offset: Int) {
        let tabs = enabledTabs
        guard let index = tabs.firstIndex(of: tab) else { return select(.home) }
        select(tabs[(index + offset + tabs.count) % tabs.count])
    }
}
