import AppKit

/// NSSharingService ile paylaşım. Servis, iş bitene kadar canlı tutulmalı; yoksa pencere hemen kapanır.
enum Sharing {
    private final class Delegate: NSObject, NSSharingServiceDelegate {
        var active: [NSSharingService] = []

        func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
            active.removeAll { $0 === sharingService }
        }

        func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
            active.removeAll { $0 === sharingService }
        }
    }

    private static let delegate = Delegate()

    static func airDrop(_ urls: [URL]) {
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        guard service.canPerform(withItems: urls) else {
            NSLog("[Notchland] AirDrop kullanılamıyor (Wi-Fi/Bluetooth kapalı olabilir).")
            return
        }
        service.delegate = delegate
        delegate.active.append(service)
        // AirDrop penceresi, arka plandaki (LSUIElement) uygulamada öne gelsin.
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: urls)
    }
}
