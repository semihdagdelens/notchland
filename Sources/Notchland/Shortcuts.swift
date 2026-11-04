import Carbon.HIToolbox
import SwiftUI

/// Sekmeleri ve araçları doğrudan açan genel kısayollar. Hepsi ⌃⌥ + Türkçe adının bir harfi:
/// Ana sayfa, Pano, Raf, Takvim, nOtlar, Hesap makinesi, Wrapped, İstatistik, Kısayollar.
enum AppShortcut: String, CaseIterable, Identifiable {
    case home, clipboard, shelf, calendar, notes, calculator, wrapped, stats, shortcuts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Ana sayfa"
        case .clipboard: "Pano (çamaşır ipi)"
        case .shelf: "Dosya rafı"
        case .calendar: "Takvim"
        case .notes: "Notlar"
        case .calculator: "Hesap makinesi"
        case .wrapped: "Dinleme özeti"
        case .stats: "Sistem"
        case .shortcuts: "Bu tablo"
        }
    }

    var symbol: String {
        switch self {
        case .shortcuts: "keyboard"
        default: tab?.symbol ?? "circle"
        }
    }

    /// Kısayolun açtığı sekme; tablo sekme değildir.
    var tab: NotchState.Tab? {
        switch self {
        case .home: .home
        case .clipboard: .clipboard
        case .shelf: .shelf
        case .calendar: .calendar
        case .notes: .notes
        case .calculator: .calculator
        case .wrapped: .wrapped
        case .stats: .stats
        case .shortcuts: nil
        }
    }

    private var key: (code: Int, label: String) {
        switch self {
        case .home: (kVK_ANSI_A, "A")
        case .clipboard: (kVK_ANSI_P, "P")
        case .shelf: (kVK_ANSI_R, "R")
        case .calendar: (kVK_ANSI_T, "T")
        case .notes: (kVK_ANSI_O, "O")
        case .calculator: (kVK_ANSI_H, "H")
        case .wrapped: (kVK_ANSI_W, "W")
        case .stats: (kVK_ANSI_I, "I")
        case .shortcuts: (kVK_ANSI_K, "K")
        }
    }

    var keyLabel: String { "⌃⌥ \(key.label)" }

    /// Carbon tuş kodu ve değiştiricileri.
    var combo: (keyCode: UInt32, modifiers: UInt32) {
        (UInt32(key.code), UInt32(controlKey | optionKey))
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
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 3) {
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
                    .frame(height: 18)
                }
            }
            Spacer(minLength: 0)
            Text("Aynı kısayol kapatır · ← → sekme değiştirir · Esc kapatır")
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

/// Ayarlar penceresinde kısayolları tek tek kapatma (başka bir uygulamayla çakışırsa).
struct ShortcutSettings: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                ForEach(AppShortcut.allCases) { shortcut in
                    Toggle(isOn: binding(for: shortcut)) {
                        HStack {
                            Text(shortcut.title)
                            Spacer()
                            KeyCap(text: shortcut.keyLabel)
                        }
                    }
                }
            } header: {
                Text("Genel kısayollar")
            } footer: {
                Text("Başka bir uygulamayla çakışan kısayolu buradan kapatabilirsin. Klavyeyle gezinme ve dikte kısayolları kendi ayarlarından seçilir.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
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
