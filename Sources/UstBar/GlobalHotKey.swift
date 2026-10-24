import Carbon.HIToolbox

/// Sistem genelinde çalışan klavye kısayolu (Carbon). Erişilebilirlik izni gerektirmez.
final class GlobalHotKey {
    var onPress: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// Önceki kısayolu kaldırıp yenisini kaydeder; `nil` yalnızca kaldırır.
    func register(_ combo: (keyCode: UInt32, modifiers: UInt32)?) {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        guard let combo else { return }
        installHandlerIfNeeded()
        let id = EventHotKeyID(signature: OSType(0x5553_5442), id: 1) // "USTB"
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            NSLog("[UstBar] Kısayol kaydedilemedi (başka bir uygulama kullanıyor olabilir): \(status)")
        }
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, _, userInfo in
            guard let userInfo else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userInfo).takeUnretainedValue()
            DispatchQueue.main.async { hotKey.onPress?() }
            return noErr
        }
        InstallEventHandler(
            GetApplicationEventTarget(), callback, 1, &spec,
            Unmanaged.passUnretained(self).toOpaque(), &handlerRef
        )
    }
}
