import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var notchController: NotchWindowController?
    private var statusItem: NSStatusItem?
    private var settingsController: SettingsWindowController?
    private let permissionItem = NSMenuItem()

    func applicationDidFinishLaunching(_ notification: Notification) {
        LegacyMigration.run()
        notchController = NotchWindowController()
        notchController?.show()
        setupStatusItem()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Notchland")
        let menu = NSMenu()
        menu.delegate = self
        permissionItem.target = self
        permissionItem.action = #selector(openAccessibilitySettings)
        menu.addItem(permissionItem)
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Ayarlar…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Notchland'den Çık", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    func menuWillOpen(_ menu: NSMenu) {
        let active = notchController?.keyTap.isActive == true
        permissionItem.title = active
            ? "Ses/parlaklık tuşları: Aktif"
            : "Ses/parlaklık tuşları: Erişilebilirlik izni gerekli…"
        permissionItem.image = NSImage(
            systemSymbolName: active ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
            accessibilityDescription: nil
        )
    }

    @objc private func openSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController { [weak self] in
                self?.notchController?.reloadWeather()
            }
        }
        settingsController?.show()
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @objc private func screensChanged() {
        notchController?.reposition()
    }
}
