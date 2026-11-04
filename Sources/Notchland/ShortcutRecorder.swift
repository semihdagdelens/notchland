import AppKit
import Carbon

/// Carbon tuş kodu ve değiştiricileri.
typealias KeyCombo = (keyCode: UInt32, modifiers: UInt32)

/// Tuş birleşimini ekranda gösterilecek metne çevirir.
enum KeyComboLabel {
    private static let functionKeys: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7",
        kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13", kVK_F14: "F14",
        kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
    ]

    /// Yazı üretmeyen tuşlar; adları klavye düzeninden okunamaz.
    private static let specialKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Escape: "⎋",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_ANSI_KeypadEnter: "⌤",
    ]

    static func text(for combo: KeyCombo) -> String {
        let code = Int(combo.keyCode)
        let key = functionKeys[code] ?? specialKeys[code] ?? character(for: combo.keyCode) ?? "#\(code)"
        var modifiers = ""
        if combo.modifiers & UInt32(controlKey) != 0 { modifiers += "⌃" }
        if combo.modifiers & UInt32(optionKey) != 0 { modifiers += "⌥" }
        if combo.modifiers & UInt32(shiftKey) != 0 { modifiers += "⇧" }
        if combo.modifiers & UInt32(cmdKey) != 0 { modifiers += "⌘" }
        return modifiers.isEmpty ? key : "\(modifiers) \(key)"
    }

    /// Yazıyı bozmayacak birleşim mi? ⇧ büyük harf, ⌥ ise özel karakter yazar (Türkçe Q'da @ ⌥Q'dur).
    static func isAllowed(_ combo: KeyCombo) -> Bool {
        let code = Int(combo.keyCode)
        if combo.modifiers & UInt32(cmdKey | controlKey) != 0 || functionKeys[code] != nil { return true }
        return combo.modifiers & UInt32(optionKey) != 0 && specialKeys[code] != nil
    }

    /// Fiziksel tuşun o anki klavye düzenindeki harfi; böylece Türkçe F gibi düzenlerde de doğru görünür.
    private static func character(for keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var deadKeys: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let status = UCKeyTranslate(
            layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeys, characters.count, &length, &characters
        )
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length).uppercased(with: Locale(identifier: "tr"))
    }
}

/// Ayarlarda kısayol değiştirme: satıra tıklanınca basılan ilk birleşimi yakalar.
@Observable
final class ShortcutRecorder {
    /// Yeni tuşları beklenen kısayol.
    private(set) var target: AppShortcut?
    /// Reddedilen birleşimin nedeni; ilgili satırın altında görünür.
    private(set) var notice: (shortcut: AppShortcut, text: String)?

    private var monitor: Any?
    private var resignObserver: Any?

    func toggle(_ shortcut: AppShortcut) {
        let wasRecording = target == shortcut
        cancel()
        if !wasRecording { start(shortcut) }
    }

    func cancel() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        monitor = nil
        resignObserver = nil
        notice = nil
        guard target != nil else { return }
        target = nil
        GlobalHotKey.setSuspended(false)
    }

    func reset(_ shortcut: AppShortcut) {
        cancel()
        if let owner = shortcut.conflict(with: shortcut.defaultCombo) {
            notice = (shortcut, "Varsayılanı şu an \(owner) kullanıyor")
        } else {
            AppSettings.shared.customShortcuts[shortcut.rawValue] = nil
        }
    }

    func resetAll() {
        cancel()
        AppSettings.shared.customShortcuts = [:]
    }

    private func start(_ shortcut: AppShortcut) {
        target = shortcut
        // Kayıtlı kısayollar tuşu pencereden önce yakalar; mevcut bir birleşime basılınca panel açılmasın.
        GlobalHotKey.setSuspended(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
            return nil
        }
        // Başka pencereye veya uygulamaya geçilirse kısayollar askıda kalmasın.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.cancel() }
    }

    private func handle(_ event: NSEvent) {
        guard let target else { return }
        let flags = event.modifierFlags
        var modifiers = 0
        if flags.contains(.control) { modifiers |= controlKey }
        if flags.contains(.option) { modifiers |= optionKey }
        if flags.contains(.shift) { modifiers |= shiftKey }
        if flags.contains(.command) { modifiers |= cmdKey }
        if Int(event.keyCode) == kVK_Escape && modifiers == 0 { return cancel() }

        let combo: KeyCombo = (UInt32(event.keyCode), UInt32(modifiers))
        guard KeyComboLabel.isAllowed(combo) else {
            notice = (target, "⌘ veya ⌃ ile birlikte bas; ⌥ ve ⇧ tek başına yazı yazmayı bozar")
            return
        }
        if let owner = target.conflict(with: combo) {
            notice = (target, "\(KeyComboLabel.text(for: combo)) zaten \(owner) için kullanılıyor")
            return
        }
        target.setCombo(combo)
        cancel()
    }
}
