import Carbon.HIToolbox

/// Sistem genelinde çalışan klavye kısayolu (Carbon). Erişilebilirlik izni gerektirmez.
/// Her örnek kendi kimliğiyle kaydolur; böylece birden çok kısayol birbirini yutmaz.
final class GlobalHotKey {
    var onPress: (() -> Void)?

    private let id: UInt32
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init(id: UInt32 = 1) {
        self.id = id
    }

    /// Önceki kısayolu kaldırıp yenisini kaydeder; `nil` yalnızca kaldırır.
    func register(_ combo: (keyCode: UInt32, modifiers: UInt32)?) {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        guard let combo else { return }
        installHandlerIfNeeded()
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            NSLog("[UstBar] Kısayol kaydedilemedi (başka bir uygulama kullanıyor olabilir): \(status)")
        }
    }

    private static let signature = OSType(0x5553_5442) // "USTB"

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userInfo in
            guard let event, let userInfo else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userInfo).takeUnretainedValue()
            var pressed = EventHotKeyID()
            GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed
            )
            // Başka bir örneğin kısayoluysa olayı sıradaki işleyiciye bırak.
            guard pressed.signature == GlobalHotKey.signature, pressed.id == hotKey.id else { return OSStatus(eventNotHandledErr) }
            DispatchQueue.main.async { hotKey.onPress?() }
            return noErr
        }
        InstallEventHandler(
            GetApplicationEventTarget(), callback, 1, &spec,
            Unmanaged.passUnretained(self).toOpaque(), &handlerRef
        )
    }
}
