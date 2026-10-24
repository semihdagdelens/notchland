import AppKit
import ApplicationServices
import os

/// Ekrana gelen bildirim balonlarını Erişilebilirlik API'siyle okur ve notch'ta yansıtır.
/// macOS üçüncü parti uygulamalara başka uygulamaların bildirimlerini vermez; bu yüzden
/// Bildirim Merkezi sürecinin (com.apple.notificationcenterui) pencereleri izlenir.
/// Ses tuşları için verilen Erişilebilirlik izni burada da yeterlidir.
final class NotificationMirror {
    struct Notice: Equatable {
        let appName: String?
        let title: String
        let body: String
        /// Uygulama adı çalışan bir uygulamayla eşleşirse ikonunu bulmak için.
        let bundleID: String?
    }

    var onNotice: ((Notice) -> Void)?

    private static let centerBundleID = "com.apple.notificationcenterui"

    private var observer: AXObserver?
    private var observedPID: pid_t = 0
    private var retryTimer: Timer?
    private var pendingScan: DispatchWorkItem?
    /// Görülmüş bildirimler; aynı balon (veya Bildirim Merkezi'nde tekrar görünen) yeniden yansıtılmasın.
    private var seen: Set<String> = []
    private var isPrimed = false

    func start() {
        attach()
        // İzin sonradan verilirse veya süreç yeniden başlarsa tekrar bağlan.
        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in self?.attach() }
        timer.tolerance = 3
        RunLoop.main.add(timer, forMode: .common)
        retryTimer = timer
    }

    private func attach() {
        guard AXIsProcessTrusted(),
              let center = NSRunningApplication.runningApplications(withBundleIdentifier: Self.centerBundleID).first
        else { return }
        guard center.processIdentifier != observedPID || observer == nil else { return }
        detach()

        let pid = center.processIdentifier
        var created: AXObserver?
        let callback: AXObserverCallback = { _, _, _, context in
            guard let context else { return }
            Unmanaged<NotificationMirror>.fromOpaque(context).takeUnretainedValue().scheduleScan()
        }
        guard AXObserverCreate(pid, callback, &created) == .success, let created else { return }
        let app = AXUIElementCreateApplication(pid)
        let context = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXWindowCreatedNotification, kAXCreatedNotification, kAXUIElementDestroyedNotification,
                     kAXLayoutChangedNotification] {
            AXObserverAddNotification(created, app, name as CFString, context)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
        observer = created
        observedPID = pid
        isPrimed = false
        scan()
    }

    private func detach() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        observedPID = 0
    }

    /// Bir balon art arda birçok AX olayı üretir; metinler dolsun diye kısa bir süre bekle.
    private func scheduleScan() {
        pendingScan?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.scan() }
        pendingScan = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func scan() {
        guard observedPID != 0 else { return }
        let app = AXUIElementCreateApplication(observedPID)
        let windows = Self.elements(app, kAXWindowsAttribute)
        var fresh: [Notice] = []
        for banner in windows.flatMap(Self.banners(in:)) {
            guard let notice = Self.notice(from: banner) else { continue }
            // Her balonun kendine özgü bir tanımlayıcısı (UUID) var; yoksa içerikten imza.
            let key = Self.string(banner, kAXIdentifierAttribute)
                ?? [notice.appName ?? "", notice.title, notice.body].joined(separator: "\u{1F}")
            if seen.insert(key).inserted { fresh.append(notice) }
        }
        if seen.count > 500 { seen.removeAll() }
        if UserDefaults.standard.bool(forKey: "debugNotificationAX") {
            windows.forEach { Self.dump($0, depth: 0) }
        }
        // İlk taramada ekranda kalmış olanlar yeni sayılmaz.
        guard isPrimed else {
            isPrimed = true
            return
        }
        // Aynı anda birden fazla yeni bildirim görünmesi, kullanıcının Bildirim Merkezi'ni açıp
        // eski bildirimleri listelediği anlamına gelir; onlar yansıtılmaz.
        guard fresh.count == 1 else { return }
        if UserDefaults.standard.bool(forKey: "debugNotificationAX") {
            Self.debugLog.notice("yansıtıldı: \(fresh[0].appName ?? "-", privacy: .public) | \(fresh[0].title, privacy: .public) | \(fresh[0].body, privacy: .public)")
        }
        onNotice?(fresh[0])
    }

    // MARK: - AX ağacı

    /// Bildirim balonları "AXNotificationCenterBanner"/"…Alert" alt rolüyle gelir.
    private static func banners(in root: AXUIElement) -> [AXUIElement] {
        var found: [AXUIElement] = []
        func walk(_ element: AXUIElement, depth: Int) {
            guard depth < 12 else { return }
            let subrole = string(element, kAXSubroleAttribute) ?? ""
            if subrole.hasPrefix("AXNotificationCenterBanner") || subrole.hasPrefix("AXNotificationCenterAlert") {
                if !subrole.hasSuffix("Stack") {
                    found.append(element)
                    return
                }
            }
            for child in elements(element, kAXChildrenAttribute) { walk(child, depth: depth + 1) }
        }
        walk(root, depth: 0)
        return found
    }

    private static func notice(from banner: AXUIElement) -> Notice? {
        var texts: [(id: String, value: String)] = []
        func collect(_ element: AXUIElement, depth: Int) {
            guard depth < 8 else { return }
            if string(element, kAXRoleAttribute) == kAXStaticTextRole,
               let value = string(element, kAXValueAttribute)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                texts.append((string(element, kAXIdentifierAttribute) ?? "", value))
            }
            for child in elements(element, kAXChildrenAttribute) { collect(child, depth: depth + 1) }
        }
        collect(banner, depth: 0)

        // Tanımlayıcılar varsa (title/subtitle/body) onları, yoksa sırayı kullan.
        let byID = Dictionary(texts.map { ($0.id, $0.value) }, uniquingKeysWith: { first, _ in first })
        var title = byID["title"]
        var body = [byID["subtitle"], byID["body"]].compactMap { $0 }.joined(separator: " · ")
        if title == nil {
            let values = texts.map(\.value)
            guard let first = values.first else { return nil }
            title = first
            body = values.dropFirst().joined(separator: " · ")
        }
        guard let title else { return nil }

        // Balonun açıklaması genelde "Uygulama, Başlık, Gövde" biçimindedir.
        let description = string(banner, kAXDescriptionAttribute) ?? ""
        let candidate = description.components(separatedBy: ", ").first?.trimmingCharacters(in: .whitespaces)
        let app = candidate.flatMap(runningApp(named:)) ?? runningApp(named: title)
        let appName = app?.localizedName ?? (candidate?.isEmpty == false && candidate != title ? candidate : nil)
        return Notice(appName: appName, title: title, body: body, bundleID: app?.bundleIdentifier)
    }

    private static func runningApp(named name: String) -> NSRunningApplication? {
        guard !name.isEmpty else { return nil }
        return NSWorkspace.shared.runningApplications.first { $0.localizedName == name }
    }

    private static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static let debugLog = Logger(subsystem: "com.best.notchland", category: "notifications")

    /// `defaults write com.best.notchland debugNotificationAX -bool true` ile ağacı günlüğe yazar.
    private static func dump(_ element: AXUIElement, depth: Int) {
        guard depth < 12 else { return }
        let parts = [kAXRoleAttribute, kAXSubroleAttribute, kAXIdentifierAttribute, kAXDescriptionAttribute,
                     kAXTitleAttribute, kAXValueAttribute].map { string(element, $0) ?? "-" }
        var actions: CFArray?
        AXUIElementCopyActionNames(element, &actions)
        let line = String(repeating: "  ", count: depth) + parts.joined(separator: " | ")
            + " | actions: " + ((actions as? [String]) ?? []).joined(separator: ",")
        debugLog.notice("\(line, privacy: .public)")
        for child in elements(element, kAXChildrenAttribute) { dump(child, depth: depth + 1) }
    }
}
