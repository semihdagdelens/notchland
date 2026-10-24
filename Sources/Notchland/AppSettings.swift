import Foundation
import ServiceManagement

/// Uygulama ayarları; her değişiklik UserDefaults'a yazılır.
@Observable
final class AppSettings {
    static let shared = AppSettings()

    enum TemperatureUnit: String, CaseIterable, Identifiable {
        case celsius, fahrenheit
        var id: String { rawValue }
        var title: String { self == .celsius ? "Santigrat (°C)" : "Fahrenhayt (°F)" }
    }

    enum DictationHotKey: String, CaseIterable, Identifiable {
        case off, optionSpace, shiftOptionSpace, controlOptionSpace, controlOptionD
        var id: String { rawValue }

        var title: String {
            switch self {
            case .off: "Kapalı"
            case .optionSpace: "⌥ Space"
            case .shiftOptionSpace: "⇧⌥ Space"
            case .controlOptionSpace: "⌃⌥ Space"
            case .controlOptionD: "⌃⌥ D"
            }
        }

        /// Carbon tuş kodu ve değiştiricileri.
        var combo: (keyCode: UInt32, modifiers: UInt32)? {
            let space: UInt32 = 49, d: UInt32 = 2
            let option: UInt32 = 1 << 11, shift: UInt32 = 1 << 9, control: UInt32 = 1 << 12
            switch self {
            case .off: return nil
            case .optionSpace: return (space, option)
            case .shiftOptionSpace: return (space, shift | option)
            case .controlOptionSpace: return (space, control | option)
            case .controlOptionD: return (d, control | option)
            }
        }
    }

    enum NavigationHotKey: String, CaseIterable, Identifiable {
        case off, controlOptionN, controlOptionDown, optionCommandN
        var id: String { rawValue }

        var title: String {
            switch self {
            case .off: "Kapalı"
            case .controlOptionN: "⌃⌥ N"
            case .controlOptionDown: "⌃⌥ ↓"
            case .optionCommandN: "⌥⌘ N"
            }
        }

        /// Carbon tuş kodu ve değiştiricileri.
        var combo: (keyCode: UInt32, modifiers: UInt32)? {
            let n: UInt32 = 45, down: UInt32 = 125
            let command: UInt32 = 1 << 8, option: UInt32 = 1 << 11, control: UInt32 = 1 << 12
            switch self {
            case .off: return nil
            case .controlOptionN: return (n, control | option)
            case .controlOptionDown: return (down, control | option)
            case .optionCommandN: return (n, option | command)
            }
        }
    }

    // MARK: Notch

    /// Fare notch'un üstünde bu kadar bekleyince açılır (saniye).
    var hoverDelay = AppSettings.value("hoverDelay", 0.0) { didSet { save("hoverDelay", hoverDelay) } }
    var hapticFeedback = AppSettings.value("hapticFeedback", false) { didSet { save("hapticFeedback", hapticFeedback) } }
    /// Notch'u klavyeyle açıp sekmeler arasında gezdiren kısayol.
    var navigationHotKey = NavigationHotKey(rawValue: AppSettings.value("navigationHotKey", "controlOptionN")) ?? .controlOptionN {
        didSet { save("navigationHotKey", navigationHotKey.rawValue) }
    }
    var showCalendarTab = AppSettings.value("showCalendarTab", true) { didSet { save("showCalendarTab", showCalendarTab) } }
    var showClipboardTab = AppSettings.value("showClipboardTab", true) { didSet { save("showClipboardTab", showClipboardTab) } }
    var showShelfTab = AppSettings.value("showShelfTab", true) { didSet { save("showShelfTab", showShelfTab) } }
    var showStatsTab = AppSettings.value("showStatsTab", true) { didSet { save("showStatsTab", showStatsTab) } }
    var showNotesTab = AppSettings.value("showNotesTab", true) { didSet { save("showNotesTab", showNotesTab) } }
    var showCalculatorTab = AppSettings.value("showCalculatorTab", true) { didSet { save("showCalculatorTab", showCalculatorTab) } }

    // MARK: Göstergeler

    var volumeHUD = AppSettings.value("volumeHUD", true) { didSet { save("volumeHUD", volumeHUD) } }
    var brightnessHUD = AppSettings.value("brightnessHUD", true) { didSet { save("brightnessHUD", brightnessHUD) } }
    var batteryHUD = AppSettings.value("batteryHUD", true) { didSet { save("batteryHUD", batteryHUD) } }
    /// 0: düşük pil uyarısı kapalı.
    var lowBatteryThreshold = AppSettings.value("lowBatteryThreshold", 20) { didSet { save("lowBatteryThreshold", lowBatteryThreshold) } }
    /// Bluetooth kulaklık bağlanınca pil seviyeleri.
    var headphoneHUD = AppSettings.value("headphoneHUD", true) { didSet { save("headphoneHUD", headphoneHUD) } }
    /// Ekrana gelen bildirimler notch'ta da gösterilsin.
    var mirrorNotifications = AppSettings.value("mirrorNotifications", true) {
        didSet { save("mirrorNotifications", mirrorNotifications) }
    }

    // MARK: Takvim ve hava

    /// 0: etkinlik hatırlatması kapalı.
    var calendarReminderMinutes = AppSettings.value("calendarReminderMinutes", 5) {
        didSet { save("calendarReminderMinutes", calendarReminderMinutes) }
    }
    var temperatureUnit = TemperatureUnit(rawValue: AppSettings.value("temperatureUnit", "celsius")) ?? .celsius {
        didSet { save("temperatureUnit", temperatureUnit.rawValue) }
    }
    /// Boşsa konum (veya saat dilimi) kullanılır.
    var weatherCity = AppSettings.value("weatherCity", "") { didSet { save("weatherCity", weatherCity) } }

    // MARK: Pano ve müzik

    var clipboardEnabled = AppSettings.value("clipboardEnabled", true) { didSet { save("clipboardEnabled", clipboardEnabled) } }
    var clipboardMaxItems = AppSettings.value("clipboardMaxItems", 60) { didSet { save("clipboardMaxItems", clipboardMaxItems) } }
    /// Kaydedilen ekran görüntüleri de pano geçmişine eklensin.
    var clipboardScreenshots = AppSettings.value("clipboardScreenshots", true) {
        didSet { save("clipboardScreenshots", clipboardScreenshots) }
    }
    /// Kaydedilen ekran görüntüsü panoya da konsun; ⌘V ile doğrudan yapıştırılabilsin.
    var screenshotToPasteboard = AppSettings.value("screenshotToPasteboard", true) {
        didSet { save("screenshotToPasteboard", screenshotToPasteboard) }
    }
    /// Senkron sözleri ileri (+) veya geri (−) kaydırır (saniye).
    var lyricsOffset = AppSettings.value("lyricsOffset", 0.0) { didSet { save("lyricsOffset", lyricsOffset) } }
    /// Açık notch'un arka planı çalan parçanın kapak rengine bürünsün.
    var artworkBackground = AppSettings.value("artworkBackground", true) {
        didSet { save("artworkBackground", artworkBackground) }
    }
    /// Çalarken kapalı notch'un yanlarında kapak ve ses dalgası.
    var liveActivity = AppSettings.value("liveActivity", true) { didSet { save("liveActivity", liveActivity) } }
    /// Ritmi bilinmeyen şarkılarda sistem sesini dinleyip ritmi kaydet.
    var listenSystemAudio = AppSettings.value("listenSystemAudio", true) {
        didSet { save("listenSystemAudio", listenSystemAudio) }
    }

    // MARK: Dikte

    var dictationHotKey = DictationHotKey(rawValue: AppSettings.value("dictationHotKey", "optionSpace")) ?? .optionSpace {
        didSet { save("dictationHotKey", dictationHotKey.rawValue) }
    }
    /// Bitince metni öndeki uygulamaya yapıştır (Erişilebilirlik izni gerekir); kapalıysa yalnızca panoya kopyalanır.
    var dictationAutoPaste = AppSettings.value("dictationAutoPaste", true) { didSet { save("dictationAutoPaste", dictationAutoPaste) } }

    // MARK: Açılışta başlat

    var launchAtLogin: Bool {
        get {
            access(keyPath: \.launchAtLogin)
            return SMAppService.mainApp.status == .enabled
        }
        set {
            withMutation(keyPath: \.launchAtLogin) {
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    launchAtLoginError = nil
                } catch {
                    launchAtLoginError = error.localizedDescription
                }
            }
        }
    }
    private(set) var launchAtLoginError: String?

    // MARK: - UserDefaults

    private static func value<T>(_ key: String, _ fallback: T) -> T {
        UserDefaults.standard.object(forKey: key) as? T ?? fallback
    }

    private func save(_ key: String, _ value: Any) {
        UserDefaults.standard.set(value, forKey: key)
    }
}
