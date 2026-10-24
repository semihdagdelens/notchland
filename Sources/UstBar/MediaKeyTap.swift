import AppKit
import ApplicationServices

/// Ses ve parlaklık tuşlarını CGEventTap ile yakalar; sistem HUD'u çıkmasın diye olayı yutar.
/// Erişilebilirlik izni gerekir; izin yoksa tuşlar sisteme bırakılır.
final class MediaKeyTap {
    enum Key {
        case volumeUp, volumeDown, mute, brightnessUp, brightnessDown
    }

    /// Tuş basıldığında (basılı tutma tekrarları dahil) çağrılır.
    /// `fine`: Option+Shift basılıysa ince adım. Olay yutulacaksa true dönmeli.
    var onKey: ((Key, _ fine: Bool) -> Bool)?

    /// Tuşlar yakalanıyor mu (izin verildi ve tap kuruldu).
    var isActive: Bool { tap != nil }

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var trustTimer: Timer?
    private var swallowedKeys: Set<Key> = []

    // IOKit/hidsystem/ev_keymap.h
    private static let systemDefinedType = CGEventType(rawValue: 14)!
    private static let keyCodes: [Int: Key] = [
        0: .volumeUp, 1: .volumeDown, 7: .mute, 2: .brightnessUp, 3: .brightnessDown,
    ]

    func start() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) { install() }
        // İzin uygulama çalışırken verilebilir veya geri alınabilir; ikisini de izle.
        // Geri alındığında tap kalırsa tuşlar ne bize ne sisteme düzgün ulaşır.
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.reconcileTrust() }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        trustTimer = timer
    }

    private func reconcileTrust() {
        let trusted = AXIsProcessTrusted()
        if trusted && tap == nil {
            install()
        } else if !trusted && tap != nil {
            uninstall()
        }
    }

    private func uninstall() {
        guard let port = tap else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        CFMachPortInvalidate(port)
        tap = nil
        runLoopSource = nil
        swallowedKeys.removeAll()
        NSLog("[UstBar] Erişilebilirlik izni kalktı; medya tuşları sisteme bırakıldı.")
    }

    private func install() {
        guard tap == nil else { return }
        let mask = CGEventMask(1) << Self.systemDefinedType.rawValue
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let tap = Unmanaged<MediaKeyTap>.fromOpaque(userInfo).takeUnretainedValue()
            return tap.handle(type: type, event: event)
        }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("[UstBar] Event tap kurulamadı.")
            return
        }
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = port
        runLoopSource = source
        NSLog("[UstBar] Medya tuşları yakalanıyor.")
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if AXIsProcessTrusted() {
                if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            } else {
                DispatchQueue.main.async { [weak self] in self?.uninstall() }
            }
            return Unmanaged.passUnretained(event)
        }
        guard type == Self.systemDefinedType,
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == 8
        else { return Unmanaged.passUnretained(event) }

        let data = nsEvent.data1
        guard let key = Self.keyCodes[(data & 0xFFFF_0000) >> 16] else {
            return Unmanaged.passUnretained(event)
        }
        let isKeyDown = (data & 0xFF00) >> 8 == 0x0A
        let fine = nsEvent.modifierFlags.isSuperset(of: [.option, .shift])

        if isKeyDown {
            if onKey?(key, fine) == true {
                swallowedKeys.insert(key)
                return nil
            }
            swallowedKeys.remove(key)
            return Unmanaged.passUnretained(event)
        }
        // Tuş bırakma olayını, basma olayına verilen kararla aynı şekilde ele al.
        return swallowedKeys.remove(key) != nil ? nil : Unmanaged.passUnretained(event)
    }
}
