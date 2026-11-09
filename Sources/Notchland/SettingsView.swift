import AppKit
import SwiftUI

final class SettingsWindowController {
    private var window: NSWindow?
    private let onWeatherChange: () -> Void

    init(onWeatherChange: @escaping () -> Void) {
        self.onWeatherChange = onWeatherChange
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(onWeatherChange: onWeatherChange))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Notchland Ayarları"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 520, height: 460))
            window.center()
            self.window = window
        }
        // Arka plan (LSUIElement) uygulaması olduğumuz için pencereyi öne getir.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    let onWeatherChange: () -> Void

    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("Genel", systemImage: "gearshape") }
            HUDSettings()
                .tabItem { Label("Göstergeler", systemImage: "speaker.wave.2") }
            CalendarWeatherSettings(onWeatherChange: onWeatherChange)
                .tabItem { Label("Takvim ve Hava", systemImage: "calendar") }
            ClipboardMusicSettings()
                .tabItem { Label("Pano ve Müzik", systemImage: "doc.on.clipboard") }
            DictationSettings()
                .tabItem { Label("Dikte", systemImage: "mic") }
            ShortcutSettings()
                .tabItem { Label("Kısayollar", systemImage: "keyboard") }
        }
        .frame(width: 520, height: 460)
    }
}

struct GeneralSettings: View {
    @Bindable fileprivate var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                Toggle("Oturum açılınca başlat", isOn: $settings.launchAtLogin)
                if let error = settings.launchAtLoginError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            } footer: {
                Text("En sağlıklısı uygulamanın /Applications klasöründe olmasıdır (scripts/install.sh).")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Notch") {
                LabeledContent("Açılma gecikmesi") {
                    HStack {
                        Slider(value: $settings.hoverDelay, in: 0...0.6, step: 0.05)
                            .frame(width: 180)
                        Text(settings.hoverDelay == 0 ? "Hemen" : String(format: "%.2f sn", settings.hoverDelay))
                            .monospacedDigit()
                            .frame(width: 60, alignment: .trailing)
                    }
                }
                PanelSizeSlider(title: "Panel genişliği", value: $settings.panelWidth, range: AppSettings.panelWidthRange)
                PanelSizeSlider(title: "Panel yüksekliği", value: $settings.panelHeight, range: AppSettings.panelHeightRange)
                if settings.panelWidth != AppSettings.panelWidthRange.lowerBound || settings.panelHeight != AppSettings.panelHeightRange.lowerBound {
                    Button("Varsayılan boyuta dön") {
                        settings.panelWidth = AppSettings.panelWidthRange.lowerBound
                        settings.panelHeight = AppSettings.panelHeightRange.lowerBound
                    }
                }
                Picker("Sekmelerin yeri", selection: $settings.tabBarPlacement) {
                    ForEach(AppSettings.TabBarPlacement.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Açılırken titreşim (trackpad)", isOn: $settings.hapticFeedback)
                Toggle("Koci (notch'ta yaşayan piksel kedi)", isOn: $settings.showKoci)
            }

            Section {
                Picker("Kısayol", selection: $settings.navigationHotKey) {
                    ForEach(AppSettings.NavigationHotKey.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Klavyeyle gezinme")
            } footer: {
                Text("Kısayol notch'u açar. ← → veya Tab ile sekme değiştir, ⌘1… ile sekmeye atla, Esc ile kapat. Ana sayfada Space oynat/duraklat, ⌘← ⌘→ önceki/sonraki parça, L şarkı sözleri, T Türkçe çeviri. Her sayfada ↓ önce düğmelere, bir daha ↓ öğelere iner; ↑ geri çıkar, ← → düğmeler arasında gezer, satırın ucunda sekme değiştirir, Return seçileni çalıştırır. Pano, indirilenler ve raf öğelerinde ⌘C kopyalar; pano ve rafta ⌫ siler.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                ForEach(Array(NotchState.Tab.ordered.enumerated()), id: \.element) { index, tab in
                    TabRow(tab: tab, canMoveUp: index > 0, canMoveDown: index < NotchState.Tab.allCases.count - 1) { offset in
                        move(tab, by: offset)
                    }
                }
                if !settings.tabOrder.isEmpty {
                    Button("Varsayılan sıraya dön") { settings.tabOrder = [] }
                }
            } header: {
                Text("Sekmeler")
            } footer: {
                Text("Oklar sırayı değiştirir; klavyede ⌘1… da bu sırayı izler.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

extension GeneralSettings {
    /// Kayıtlı sıra hep tüm sekmeleri içerir; böylece gizli sekmenin yeri de korunur.
    private func move(_ tab: NotchState.Tab, by offset: Int) {
        var order = NotchState.Tab.ordered
        guard let index = order.firstIndex(of: tab), order.indices.contains(index + offset) else { return }
        order.swapAt(index, index + offset)
        settings.tabOrder = order.map(\.rawValue)
    }
}

private struct TabRow: View {
    let tab: NotchState.Tab
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMove: (Int) -> Void
    @Bindable private var settings = AppSettings.shared

    /// Ana sayfa kapatılamaz: başka sekme kalmazsa notch boş açılırdı.
    private var isOn: Binding<Bool>? {
        switch tab {
        case .home: nil
        case .clipboard: $settings.showClipboardTab
        case .shelf: $settings.showShelfTab
        case .downloads: $settings.showDownloadsTab
        case .calendar: $settings.showCalendarTab
        case .notes: $settings.showNotesTab
        case .calculator: $settings.showCalculatorTab
        case .wrapped: $settings.showWrappedTab
        case .stats: $settings.showStatsTab
        case .agents: $settings.showAgentsTab
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            arrow("chevron.up", enabled: canMoveUp, help: "Yukarı taşı") { onMove(-1) }
            arrow("chevron.down", enabled: canMoveDown, help: "Aşağı taşı") { onMove(1) }
            Image(systemName: tab.symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            if let isOn {
                Toggle(tab.title, isOn: isOn)
            } else {
                Text(tab.title)
            }
        }
    }

    private func arrow(_ symbol: String, enabled: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.35))
        .help(help)
    }
}

private struct PanelSizeSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        LabeledContent(title) {
            HStack {
                Slider(value: $value, in: range, step: 10)
                    .frame(width: 180)
                Text("\(Int(value)) pt")
                    .monospacedDigit()
                    .frame(width: 60, alignment: .trailing)
            }
        }
    }
}

private struct HUDSettings: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                Toggle("Ses göstergesi", isOn: $settings.volumeHUD)
                Toggle("Parlaklık göstergesi", isOn: $settings.brightnessHUD)
            } footer: {
                Text("Kapatılan gösterge için tuşlar macOS'e bırakılır ve sistemin kendi göstergesi çıkar.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Pil") {
                Toggle("Şarj takılınca / çıkarılınca göster", isOn: $settings.batteryHUD)
                Picker("Düşük pil uyarısı", selection: $settings.lowBatteryThreshold) {
                    Text("Kapalı").tag(0)
                    ForEach([10, 15, 20, 30], id: \.self) { Text("%\($0)").tag($0) }
                }
                Toggle("Kulaklık bağlanınca pil durumunu göster", isOn: $settings.headphoneHUD)
            }

            Section {
                Toggle("Bildirimleri notch'ta da göster", isOn: $settings.mirrorNotifications)
                Toggle("Sistemin bildirim balonunu gizle", isOn: $settings.hideSystemBanners)
                    .disabled(!settings.mirrorNotifications)
            } header: {
                Text("Bildirimler")
            } footer: {
                Text("Ekrana gelen bildirim balonu Erişilebilirlik izniyle okunur ve notch'tan kısa süre gösterilir. Balon gizlenirse sağ üstteki sistem balonu hemen kapatılır; bildirim Bildirim Merkezi'nden de kalkar. Yanıt/eylem düğmeli uyarılara dokunulmaz.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Ajan bitirince veya seni bekleyince göster", isOn: $settings.agentAlerts)
                    .disabled(!settings.showAgentsTab)
            } header: {
                Text("AI ajanları")
            } footer: {
                Text("Genel ayarlarda “AI ajanları” sekmesi açıkken çalışır. Yalnızca 20 saniyeden uzun süren işlerin bitişi gösterilir. Claude Code konuşmaları okunmaz, yalnızca oturum durumu okunur.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct CalendarWeatherSettings: View {
    let onWeatherChange: () -> Void
    @Bindable private var settings = AppSettings.shared
    @State private var city = AppSettings.shared.weatherCity

    var body: some View {
        Form {
            Section("Takvim") {
                Picker("Etkinlik hatırlatması", selection: $settings.calendarReminderMinutes) {
                    Text("Kapalı").tag(0)
                    ForEach([1, 5, 10, 15, 30], id: \.self) { Text("\($0) dk önce").tag($0) }
                }
            }

            Section {
                Picker("Sıcaklık birimi", selection: $settings.temperatureUnit) {
                    ForEach(AppSettings.TemperatureUnit.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: settings.temperatureUnit) { onWeatherChange() }
                HStack {
                    TextField("Şehir", text: $city, prompt: Text("Otomatik (konum)"))
                        .onSubmit(applyCity)
                    Button("Uygula", action: applyCity)
                        .disabled(city == settings.weatherCity)
                }
            } header: {
                Text("Hava durumu")
            } footer: {
                Text("Şehir boş bırakılırsa konum, konum izni yoksa saat dilimi kullanılır.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func applyCity() {
        settings.weatherCity = city.trimmingCharacters(in: .whitespaces)
        onWeatherChange()
    }
}

private struct DictationSettings: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                Picker("Kısayol", selection: $settings.dictationHotKey) {
                    ForEach(AppSettings.DictationHotKey.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Bitince öndeki uygulamaya yapıştır", isOn: $settings.dictationAutoPaste)
            } header: {
                Text("Sesle yazma")
            } footer: {
                Text("Kısayola bas, konuş, tekrar bas. Türkçe döküm canlı görünür; bitince metin panoya kopyalanır. Yapıştırma için Erişilebilirlik izni gerekir.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ClipboardMusicSettings: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("Pano geçmişi") {
                Toggle("Kopyalananları kaydet", isOn: $settings.clipboardEnabled)
                Picker("En fazla", selection: $settings.clipboardMaxItems) {
                    ForEach([20, 40, 60, 100, 200], id: \.self) { Text("\($0) öğe").tag($0) }
                }
                .disabled(!settings.clipboardEnabled)
                Toggle("Ekran görüntülerini de ekle", isOn: $settings.clipboardScreenshots)
                    .disabled(!settings.clipboardEnabled)
                Toggle("Ekran görüntüsünü panoya kopyala", isOn: $settings.screenshotToPasteboard)
                    .disabled(!settings.clipboardEnabled || !settings.clipboardScreenshots)
            }

            Section {
                Toggle("Çalarken notch'ta kapak ve ses dalgası", isOn: $settings.liveActivity)
                Toggle("Yeni şarkıların ritmini sistem sesinden öğren", isOn: $settings.listenSystemAudio)
                    .disabled(!settings.liveActivity)
                Toggle("Notch'un çevresinde ritimle atan ışık şovu", isOn: $settings.lightShow)
                RhythmFolderRow()
                Toggle("Ne dinlediğimi kaydet (Wrapped)", isOn: $settings.listeningHistory)
                ListeningHistoryRow()
            } header: {
                Text("Müzik")
            } footer: {
                Text("Bir şarkı ilk çaldığında sesi dinlenir ve ritmi klasöre kaydedilir; sonraki çalışlarda dinleme ve internet kullanılmaz. Kapalıysa dalga yapay olarak oynar. Dinleme geçmişi (şarkı adı, sanatçı, süre) yalnızca bu Mac'te tutulur.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Arka planı kapak rengine göre boya", isOn: $settings.artworkBackground)
                Toggle("Yabancı sözlerin Türkçe çevirisini göster", isOn: $settings.translateLyrics)
                LabeledContent("Söz kaydırma") {
                    HStack {
                        Slider(value: $settings.lyricsOffset, in: -3...3, step: 0.25)
                            .frame(width: 180)
                        Text(String(format: "%+.2f sn", settings.lyricsOffset))
                            .monospacedDigit()
                            .frame(width: 70, alignment: .trailing)
                    }
                }
                Button("Sıfırla") { settings.lyricsOffset = 0 }
                    .disabled(settings.lyricsOffset == 0)
            } header: {
                Text("Şarkı sözleri")
            } footer: {
                Text("Sözler sesten önce geliyorsa eksiye, geride kalıyorsa artıya kaydır. Çeviri macOS'un cihaz içi çevirisiyle yapılır; dil paketi yoksa Dil ve Bölge ayarlarından indirilir.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
