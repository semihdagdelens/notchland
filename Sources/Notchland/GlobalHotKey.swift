import Carbon.HIToolbox
import Foundation

/// Sistem genelinde çalışan klavye kısayolu (Carbon). Erişilebilirlik izni gerektirmez.
/// Her örnek kendi kimliğiyle kaydolur; böylece birden çok kısayol birbirini yutmaz.
final class GlobalHotKey {
    var onPress: (() -> Void)?
    /// Tuş bırakıldı (basılı tutup bırakarak çalışan format çarkı için).
    var onRelease: (() -> Void)?

    private let id: UInt32
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var combo: KeyCombo?

    private static let instances = NSHashTable<GlobalHotKey>.weakObjects()
    private static var isSuspended = false

    init(id: UInt32 = 1) {
        self.id = id
    }

    /// Ayarlarda yeni kısayol kaydedilirken hepsini geçici olarak bırakır; basılan tuşlar pencereye ulaşsın diye.
    static func setSuspended(_ suspended: Bool) {
        isSuspended = suspended
        instances.allObjects.forEach { $0.apply() }
    }

    /// Önceki kısayolu kaldırıp yenisini kaydeder; `nil` yalnızca kaldırır.
    func register(_ combo: KeyCombo?) {
        self.combo = combo
        Self.instances.add(self)
        apply()
    }

    private func apply() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        guard !Self.isSuspended, let combo else { return }
        installHandlerIfNeeded()
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            NSLog("[Notchland] Kısayol kaydedilemedi (başka bir uygulama kullanıyor olabilir): \(status)")
        }
    }

    private static let signature = OSType(0x5553_5442) // "USTB"

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        let specs = [kEventHotKeyPressed, kEventHotKeyReleased].map {
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32($0))
        }
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
            let isRelease = GetEventKind(event) == UInt32(kEventHotKeyReleased)
            DispatchQueue.main.async { isRelease ? hotKey.onRelease?() : hotKey.onPress?() }
            return noErr
        }
        InstallEventHandler(
            GetApplicationEventTarget(), callback, specs.count, specs,
            Unmanaged.passUnretained(self).toOpaque(), &handlerRef
        )
    }
}
