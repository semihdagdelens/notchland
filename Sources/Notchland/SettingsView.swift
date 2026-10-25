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
        }
        .frame(width: 520, height: 460)
    }
}

private struct GeneralSettings: View {
    @Bindable private var settings = AppSettings.shared

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
                Toggle("Açılırken titreşim (trackpad)", isOn: $settings.hapticFeedback)
            }

            Section {
                Picker("Kısayol", selection: $settings.navigationHotKey) {
                    ForEach(AppSettings.NavigationHotKey.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Klavyeyle gezinme")
            } footer: {
                Text("Kısayol notch'u açar. ← → veya Tab ile sekme değiştir, ⌘1… ile sekmeye atla, Esc ile kapat. Ana sayfada Space oynat/duraklat, ⌘← ⌘→ önceki/sonraki parça, L şarkı sözleri, T Türkçe çeviri. Panoda ↑ ↓ ile seç, Return yapıştırır, ⌘C kopyalar, ⌫ siler. Notlarda ↓ yeni hatırlatıcıyı, bir daha ↓ yeni notu seçer; Return başlatır.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Sekmeler") {
                Toggle("Takvim", isOn: $settings.showCalendarTab)
                Toggle("Pano geçmişi", isOn: $settings.showClipboardTab)
                Toggle("Sistem istatistikleri", isOn: $settings.showStatsTab)
                Toggle("Hatırlatıcılar ve notlar", isOn: $settings.showNotesTab)
                Toggle("Hesap makinesi", isOn: $settings.showCalculatorTab)
                Toggle("Dosya rafı", isOn: $settings.showShelfTab)
            }
        }
        .formStyle(.grouped)
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
            } header: {
                Text("Bildirimler")
            } footer: {
                Text("Ekrana gelen bildirim balonu Erişilebilirlik izniyle okunur ve notch'tan kısa süre gösterilir. Sistemin kendi balonu yine çıkar.")
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
                RhythmFolderRow()
            } header: {
                Text("Müzik")
            } footer: {
                Text("Bir şarkı ilk çaldığında sesi dinlenir ve ritmi klasöre kaydedilir; sonraki çalışlarda dinleme ve internet kullanılmaz. Kapalıysa dalga yapay olarak oynar.")
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
