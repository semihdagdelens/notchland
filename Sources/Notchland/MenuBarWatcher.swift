import AppKit

/// Öndeki uygulamanın menüleri notch'un soluna kadar uzanıyor mu?
/// macOS, notch'un yanına eklenen kulakları bilmez; Chrome gibi çok menülü uygulamalarda
/// son menüler (Pencere, Yardım) sol kulağın altında kalır. O uygulamadayken canlı etkinlik sağa geçer.
final class MenuBarWatcher {
    /// Menüler sol kulağın gireceği alana taşıyor.
    private(set) var isCrowded = false
    var onChange: ((Bool) -> Void)?

    /// Menülerin bitebileceği en sağ x (global, Cocoa); bunu aşan menü kulağın altında kalır.
    var limitX: () -> CGFloat? = { nil }
    /// Notch'un sol kenarı; bunun sağındaki menüleri macOS zaten gizler, onlar sayılmaz.
    var notchMinX: () -> CGFloat? = { nil }

    private var activationObserver: NSObjectProtocol?
    private var pendingCheck: DispatchWorkItem?

    func start() {
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            // Notch odak aldığında menü çubuğu öndeki uygulamanınki gibi kalır; sonucu değiştirme.
            guard let app, app != .current else { return }
            self?.scheduleCheck(pid: app.processIdentifier)
        }
        if let app = NSWorkspace.shared.frontmostApplication, app != .current {
            scheduleCheck(pid: app.processIdentifier)
        }
    }

    /// Menü çubuğu, etkinleşmeden hemen sonra yeniden dizildiğinden biraz bekleyip okur.
    private func scheduleCheck(pid: pid_t) {
        pendingCheck?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.check(pid: pid) }
        pendingCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func check(pid: pid_t) {
        guard AXIsProcessTrusted(), let limit = limitX(), let notchLeft = notchMinX() else {
            update(false)
            return
        }
        update(Self.menuEdges(pid: pid).contains { $0.minX < notchLeft && $0.maxX > limit })
    }

    private func update(_ crowded: Bool) {
        guard crowded != isCrowded else { return }
        isCrowded = crowded
        onChange?(crowded)
    }

    /// Menü başlıklarının yatay aralıkları. AX y'yi ters tutar ama x her iki sistemde aynıdır.
    private static func menuEdges(pid: pid_t) -> [(minX: CGFloat, maxX: CGFloat)] {
        let app = AXUIElementCreateApplication(pid)
        var menuBar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &menuBar) == .success,
              let menuBar else { return [] }
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(menuBar as! AXUIElement, kAXChildrenAttribute as CFString, &children) == .success,
              let items = children as? [AXUIElement] else { return [] }
        return items.compactMap { item in
            var position: CFTypeRef?, size: CFTypeRef?
            guard AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &position) == .success,
                  AXUIElementCopyAttributeValue(item, kAXSizeAttribute as CFString, &size) == .success,
                  let position, let size else { return nil }
            var point = CGPoint.zero, extent = CGSize.zero
            AXValueGetValue(position as! AXValue, .cgPoint, &point)
            AXValueGetValue(size as! AXValue, .cgSize, &extent)
            guard extent.width > 0 else { return nil }
            return (point.x, point.x + extent.width)
        }
    }
}
