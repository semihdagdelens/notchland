import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Klavyeyle gezinme: kısayol notch'u açıp paneli klavye odağına alır; tuşlar sekmeleri
/// ve sekme içi eylemleri sürer. Fareyle açılan notch'ta da panel odaktadır; ilk yön tuşu klavye modunu başlatır.
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
        guard state.isExpanded, event.window is NotchPanel else { return false }
        // Bir metin alanında yazarken tuşlar alana gider (Esc alanın kendi işi).
        if state.isEditingText || event.window?.firstResponder is NSText { return false }
        // Fareyle açıkken gezinme tuşu klavye modunu açar: seçim görünür, fare çıkınca da notch açık kalır.
        if !state.isKeyboardActive {
            let starters = [kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow, kVK_Tab, kVK_Escape]
            guard starters.contains(Int(event.keyCode)) else { return false }
            state.isKeyboardActive = true
        }

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

        // Kısayol tablosu sekmenin önünde durur; tuşlar arkadaki sekmeye gitmesin.
        if state.showsShortcuts {
            guard key == kVK_LeftArrow || key == kVK_RightArrow else { return false }
            state.selectAdjacent(key == kVK_RightArrow ? 1 : -1)
            return true
        }

        switch state.tab {
        // Hesap makinesi rakam ve işlem tuşlarını kendisi alır; Return yalnızca bir durak seçiliyken bizim.
        case .calculator:
            let isArrow = [kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow].contains(key)
            let isStopReturn = state.focusedStop != nil && (key == kVK_Return || key == kVK_ANSI_KeypadEnter)
            guard isArrow || isStopReturn else { return false }
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
        // Bir öğe seçili değilse ⌘C rafın tamamını kopyalar.
        case .shelf:
            if command && key == kVK_ANSI_C && state.focusedStop?.onCopy == nil {
                state.keyCommand = NotchState.KeyCommand(kind: .copy)
                return true
            }
        default:
            break
        }

        return handleStop(key: key, command: command)
    }

    /// Sayfanın durakları arasında gezinme; kurallar `KeyStop`'ta.
    private func handleStop(key: Int, command: Bool) -> Bool {
        let stop = state.focusedStop
        let axis = stop?.contentAxis
        let send = { [state] (kind: NotchState.KeyCommand.Kind) in
            state.keyCommand = NotchState.KeyCommand(kind: kind)
        }

        switch key {
        case kVK_DownArrow, kVK_UpArrow:
            let isDown = key == kVK_DownArrow
            if axis == .vertical {
                send(isDown ? .down : .up)
            } else {
                state.moveKeyFocus(rowBy: isDown ? 1 : -1)
            }
            return true
        case kVK_LeftArrow, kVK_RightArrow:
            let offset = key == kVK_RightArrow ? 1 : -1
            if axis == .horizontal {
                send(offset > 0 ? .down : .up)
            } else if !state.moveKeyFocus(orderBy: offset) && stop?.clampsAtEdge != true {
                state.selectAdjacent(offset)
            }
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if axis != nil { send(.enter) } else { stop?.action() }
            return true
        case kVK_Delete, kVK_ForwardDelete:
            if axis != nil {
                send(.delete)
                return true
            }
            guard let onDelete = stop?.onDelete else { return false }
            // Silinen öğeyle odak kaybolmasın, komşusuna geçsin.
            if !state.moveKeyFocus(orderBy: 1) { state.moveKeyFocus(orderBy: -1) }
            onDelete()
            return true
        case kVK_ANSI_C where command:
            if axis != nil {
                send(.copy)
                return true
            }
            guard let onCopy = stop?.onCopy else { return false }
            onCopy()
            return true
        default:
            return false
        }
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
    var enabledTabs: [Tab] { Tab.ordered.filter(isTabEnabled) }

    /// Açık sekmeler arasında (başa/sona sararak) ileri veya geri gider.
    func selectAdjacent(_ offset: Int) {
        let tabs = enabledTabs
        guard let index = tabs.firstIndex(of: tab) else { return select(.home) }
        select(tabs[(index + offset + tabs.count) % tabs.count])
    }
}
