import SwiftUI

/// Bildirim geçmişi: notch'a yansıyan bildirimler, en yenisi üstte. Tıklamak gönderen uygulamayı açar.
struct NotificationHistoryView: View {
    let state: NotchState
    let history: NotificationHistory

    var body: some View {
        VStack(spacing: 6) {
            header
            if history.entries.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "bell.slash").font(.title3)
                    Text(AppSettings.shared.mirrorNotifications
                         ? "Gelen bildirimler burada birikecek"
                         : "Bildirim yansıtma ayarlardan kapalı")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 5) {
                            ForEach(Array(history.entries.enumerated()), id: \.element.id) { index, entry in
                                NotificationRow(entry: entry, history: history)
                                    .id(KeyStop.id(.notifications, "entry\(entry.id)"))
                                    .keyStop(state, .notifications, "entry\(entry.id)", row: index + 1, order: 0, outset: 0,
                                             onDelete: { history.remove(entry) }) {
                                        history.open(entry)
                                    }
                            }
                        }
                    }
                    .scrollsToKeyFocus(state, proxy)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Bildirimler").font(.system(size: 13, weight: .bold))
                Text("\(history.entries.count) bildirim")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                history.removeAll()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 20)
            }
            .buttonStyle(.plain)
            .help("Geçmişi temizle")
            .disabled(history.entries.isEmpty)
            .keyStop(state, .notifications, "clear", order: 0, outset: 0) { history.removeAll() }
        }
    }
}

private struct NotificationRow: View {
    let entry: NotificationHistory.Entry
    let history: NotificationHistory

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let icon = SourceAppIcon.icon(for: entry.bundleID) {
                    Image(nsImage: icon).resizable().scaledToFit()
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.12))
                        Image(systemName: "bell.fill").font(.system(size: 13, weight: .semibold))
                    }
                }
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if let app = entry.appName, app != entry.title {
                        Text(app).foregroundStyle(.secondary)
                        Text("·").foregroundStyle(.secondary)
                    }
                    Text(entry.date, format: .relative(presentation: .named, unitsStyle: .abbreviated))
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                Text(entry.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                if !entry.body.isEmpty {
                    Text(entry.body)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isHovering {
                Button {
                    history.remove(entry)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("Sil")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(isHovering ? 0.12 : 0.06))
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .onTapGesture { history.open(entry) }
        .contextMenu {
            Button("Uygulamayı Aç") { history.open(entry) }
                .disabled(entry.bundleID == nil)
            Button("Metni Kopyala") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString([entry.title, entry.body].filter { !$0.isEmpty }.joined(separator: "\n"),
                                               forType: .string)
            }
            Divider()
            Button("Sil") { history.remove(entry) }
        }
        .help("Tıkla: uygulamayı aç · Sağ tık: diğer seçenekler")
    }
}
