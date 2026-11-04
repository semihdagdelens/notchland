import Carbon.HIToolbox
import SwiftUI

/// Sekmeleri ve araçları doğrudan açan genel kısayollar. Varsayılanları ⌃⌥ + Türkçe adının bir harfi:
/// Ana sayfa, Pano, Raf, indiriLenler, Takvim, nOtlar, Hesap makinesi, Wrapped, İstatistik, Format, Kısayollar.
enum AppShortcut: String, CaseIterable, Identifiable {
    case home, clipboard, shelf, downloads, calendar, notes, calculator, wrapped, stats, formatWheel, shortcuts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Ana sayfa"
        case .clipboard: "Pano (çamaşır ipi)"
        case .shelf: "Dosya rafı"
        case .downloads: "İndirilenler"
        case .calendar: "Takvim"
        case .notes: "Notlar"
        case .calculator: "Hesap makinesi"
        case .wrapped: "Dinleme özeti"
        case .stats: "Sistem"
        case .formatWheel: "Format çarkı"
        case .shortcuts: "Bu tablo"
        }
    }

    var symbol: String {
        switch self {
        case .formatWheel: "circle.dotted.circle"
        case .shortcuts: "keyboard"
        default: tab?.symbol ?? "circle"
        }
    }

    /// Kısayolun açtığı sekme; çark ve tablo sekme değildir.
    var tab: NotchState.Tab? {
        switch self {
        case .home: .home
        case .clipboard: .clipboard
        case .shelf: .shelf
        case .downloads: .downloads
        case .calendar: .calendar
        case .notes: .notes
        case .calculator: .calculator
        case .wrapped: .wrapped
        case .stats: .stats
        case .formatWheel, .shortcuts: nil
        }
    }

    private var defaultKeyCode: Int {
        switch self {
        case .home: kVK_ANSI_A
        case .clipboard: kVK_ANSI_P
        case .shelf: kVK_ANSI_R
        case .downloads: kVK_ANSI_L
        case .calendar: kVK_ANSI_T
        case .notes: kVK_ANSI_O
        case .calculator: kVK_ANSI_H
        case .wrapped: kVK_ANSI_W
        case .stats: kVK_ANSI_I
        case .formatWheel: kVK_ANSI_F
        case .shortcuts: kVK_ANSI_K
        }
    }

    var defaultCombo: KeyCombo { (UInt32(defaultKeyCode), UInt32(controlKey | optionKey)) }

    var keyLabel: String { KeyComboLabel.text(for: combo) }

    /// Ayarlardan değiştirilmişse o, yoksa varsayılan.
    var combo: KeyCombo {
        guard let custom = AppSettings.shared.customShortcuts[rawValue], custom.count == 2 else { return defaultCombo }
        return (UInt32(custom[0]), UInt32(custom[1]))
    }

    var isCustomized: Bool { AppSettings.shared.customShortcuts[rawValue] != nil }

    func setCombo(_ combo: KeyCombo) {
        AppSettings.shared.customShortcuts[rawValue] = combo == defaultCombo ? nil : [Int(combo.keyCode), Int(combo.modifiers)]
    }

    /// Bu birleşimi kullanan başka bir kısayolun adı. Kapalı olanlar da sayılır; açılınca çakışmasınlar.
    func conflict(with combo: KeyCombo) -> String? {
        if let other = Self.allCases.first(where: { $0 != self && $0.combo == combo }) { return other.title }
        let settings = AppSettings.shared
        if let navigation = settings.navigationHotKey.combo, navigation == combo { return "Klavyeyle gezinme" }
        if let dictation = settings.dictationHotKey.combo, dictation == combo { return "Dikte" }
        return nil
    }

    /// Ayarlardan kapatılmamış.
    var isEnabled: Bool { !AppSettings.shared.disabledShortcuts.contains(rawValue) }
}

/// Bütün genel kısayolların tablosu; çentiğin içine sığacak şekilde üç sütun.
struct ShortcutsView: View {
    let state: NotchState

    private struct Row: Identifiable {
        let id: String
        let title: String
        let symbol: String
        let keys: String
    }

    /// Kapalı kısayollar ve gizli sekmelerinkiler listelenmez; yalnızca gerçekten çalışanlar görünür.
    private var rows: [Row] {
        let settings = AppSettings.shared
        var rows = AppShortcut.allCases
            .filter { $0.isEnabled && ($0.tab.map(state.isTabEnabled) ?? true) }
            .map { Row(id: $0.id, title: $0.title, symbol: $0.symbol, keys: $0.keyLabel) }
        if settings.navigationHotKey != .off {
            rows.append(Row(id: "navigation", title: "Klavyeyle gezinme", symbol: "arrow.left.arrow.right", keys: settings.navigationHotKey.title))
        }
        if settings.dictationHotKey != .off {
            rows.append(Row(id: "dictation", title: "Dikte", symbol: "mic.fill", keys: settings.dictationHotKey.title))
        }
        return rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Kısayollar").font(.system(size: 13, weight: .bold))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 2) {
                ForEach(rows) { row in
                    HStack(spacing: 6) {
                        Image(systemName: row.symbol)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))
                            .frame(width: 14)
                        Text(row.title)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Spacer(minLength: 2)
                        KeyCap(text: row.keys)
                    }
                    .frame(height: 16)
                }
            }
            Spacer(minLength: 0)
            Text("Aynı kısayol kapatır · ← → sekme değiştirir · ↓ sayfadaki düğmelere iner · Esc kapatır · Format çarkının kısayolunu basılı tut, dilime kaydır, bırak")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.14)))
    }
}

/// Ayarlar penceresinde kısayolları değiştirme ve tek tek kapatma (başka bir uygulamayla çakışırsa).
struct ShortcutSettings: View {
    @Bindable private var settings = AppSettings.shared
    @State private var recorder = ShortcutRecorder()

    var body: some View {
        Form {
            Section {
                ForEach(AppShortcut.allCases) { shortcut in
                    row(for: shortcut)
                }
                if !settings.customShortcuts.isEmpty {
                    Button("Tümünü varsayılana döndür") { recorder.resetAll() }
                }
            } header: {
                Text("Genel kısayollar")
            } footer: {
                Text("Değiştirmek için kısayola tıklayıp yeni tuşlara bas; Esc vazgeçer. Başka bir uygulamayla çakışan kısayolu buradan kapatabilirsin. Klavyeyle gezinme ve dikte kısayolları kendi ayarlarından seçilir. Format çarkı Finder'daki seçimi okur; ilk kullanımda macOS izin sorar. MP3, WebP, WebM ve MKV için ffmpeg, video bağlantılarını indirmek için yt-dlp gerekir (brew install ffmpeg yt-dlp).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onDisappear { recorder.cancel() }
    }

    private func row(for shortcut: AppShortcut) -> some View {
        let isRecording = recorder.target == shortcut
        return VStack(alignment: .trailing, spacing: 4) {
            HStack {
                Text(shortcut.title)
                Spacer()
                Button { recorder.toggle(shortcut) } label: {
                    KeyCap(text: isRecording ? "Tuşlara bas…" : shortcut.keyLabel)
                        .overlay {
                            if isRecording {
                                RoundedRectangle(cornerRadius: 4).strokeBorder(Color.accentColor, lineWidth: 1.5)
                            }
                        }
                }
                .buttonStyle(.plain)
                .help("Değiştirmek için tıkla")
                // Düğme yer tutmaya devam eder; sağdaki sütun hizası bozulmasın.
                Button { recorder.reset(shortcut) } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Varsayılana döndür")
                .opacity(shortcut.isCustomized ? 1 : 0)
                .disabled(!shortcut.isCustomized)
                Toggle(shortcut.title, isOn: binding(for: shortcut))
                    .labelsHidden()
            }
            if let notice = recorder.notice, notice.shortcut == shortcut {
                Text(notice.text)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func binding(for shortcut: AppShortcut) -> Binding<Bool> {
        Binding {
            !settings.disabledShortcuts.contains(shortcut.rawValue)
        } set: { isOn in
            settings.disabledShortcuts.removeAll { $0 == shortcut.rawValue }
            if !isOn { settings.disabledShortcuts.append(shortcut.rawValue) }
        }
    }
}
