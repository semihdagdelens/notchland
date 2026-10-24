import SwiftUI

/// Kısayolla açılan dikte paneli: mikrofon düğmesi ve canlı döküm.
struct DictationView: View {
    let dictation: DictationService
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let onToggle: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            // Notch'un iki yanındaki kulaklar: durum ve kısayol ipucu.
            HStack(spacing: 0) {
                StatusLabel(phase: dictation.phase)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(width: notchWidth)
                Text(hint)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(height: notchHeight)

            HStack(spacing: 14) {
                MicButton(phase: dictation.phase, level: dictation.level, action: onToggle)
                transcript
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: dictation.cancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .help("İptal")
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private var hint: String {
        let key = AppSettings.shared.dictationHotKey
        switch dictation.phase {
        case .listening where key != .off: return "\(key.title) ile bitir"
        default: return ""
        }
    }

    @ViewBuilder private var transcript: some View {
        switch dictation.phase {
        case let .failed(message):
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.red)
                .lineLimit(3)
        case let .done(pasted):
            VStack(alignment: .leading, spacing: 4) {
                Label(pasted ? "Yapıştırıldı" : "Panoya kopyalandı", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)
                Text(dictation.committed)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        default:
            if dictation.text.isEmpty {
                Text(dictation.phase == .preparing ? "Hazırlanıyor…" : "Dinliyorum, konuşmaya başla…")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            } else {
                let separator = dictation.committed.isEmpty || dictation.partial.isEmpty ? "" : " "
                (Text(dictation.committed + separator) + Text(dictation.partial).foregroundStyle(.white.opacity(0.6)))
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(3)
                    .truncationMode(.head)
            }
        }
    }
}

private struct StatusLabel: View {
    let phase: DictationService.Phase

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(phase == .listening ? Color.red : Color.white.opacity(0.3))
                .frame(width: 7, height: 7)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
        }
    }

    private var title: String {
        switch phase {
        case .listening: "Dikte · Türkçe"
        case .finishing: "Tamamlanıyor…"
        case .failed: "Dikte başarısız"
        default: "Dikte"
        }
    }
}

private struct MicButton: View {
    let phase: DictationService.Phase
    let level: Float
    let action: () -> Void

    private var isListening: Bool { phase == .listening }

    var body: some View {
        Button(action: action) {
            ZStack {
                // Sesle büyüyüp küçülen hale.
                Circle()
                    .fill(Color.red.opacity(isListening ? 0.3 : 0))
                    .scaleEffect(1 + CGFloat(level) * 0.55)
                Circle()
                    .fill(isListening ? Color.red : Color.white.opacity(0.15))
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .disabled(phase == .finishing || phase == .preparing)
        .animation(.easeOut(duration: 0.1), value: level)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: phase)
        .help(isListening ? "Bitir" : "Yeniden başlat")
    }

    private var symbol: String {
        switch phase {
        case .listening: "mic.fill"
        case .done: "checkmark"
        case .failed: "mic.slash.fill"
        case .finishing: "ellipsis"
        default: "mic"
        }
    }
}
