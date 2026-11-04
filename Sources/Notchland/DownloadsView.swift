import SwiftUI

/// Son indirilenler: en yenisi solda. Tıkla aç, sürükle başka yere bırak, sağ tıkla rafa ekle.
struct DownloadsView: View {
    let state: NotchState
    let downloads: DownloadsStore
    let shelf: ShelfStore

    /// Klavyeyle seçilen dosya; yoksa ilk dosya seçili sayılır.
    @State private var selection: DownloadsStore.Item.ID?

    private var selectedItem: DownloadsStore.Item? {
        downloads.items.first { $0.id == selection } ?? downloads.items.first
    }

    var body: some View {
        VStack(spacing: 4) {
            header
            if downloads.items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: downloads.isUnavailable ? "lock.fill" : "arrow.down.circle").font(.title3)
                    Text(downloads.isUnavailable ? "İndirilenler klasörüne izin gerekli (Sistem Ayarları › Gizlilik)" : "İndirilenler boş")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { area in
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 6) {
                            ForEach(downloads.items) { item in
                                DownloadTile(
                                    state: state, downloads: downloads, shelf: shelf, item: item,
                                    // Ad ve tarih satırlarına kalan yükseklik kadar.
                                    side: max(58, area.size.height - 38),
                                    isSelected: state.isKeyboardActive && item.id == selectedItem?.id
                                )
                                .id(item.id)
                            }
                        }
                    }
                    .onChange(of: selection) { _, id in
                        guard let id else { return }
                        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .center) }
                    }
                }
                }
            }
        }
        .onAppear { downloads.start() }
        .onChange(of: state.keyCommand) { _, command in
            if let command { perform(command.kind) }
        }
    }

    /// Klavyeyle gezinme: ← → seçer, Return açar, ⌘C kopyalar.
    private func perform(_ command: NotchState.KeyCommand.Kind) {
        let items = downloads.items
        guard let current = selectedItem, let index = items.firstIndex(of: current) else { return }
        switch command {
        case .up, .down:
            selection = items[min(max(index + (command == .down ? 1 : -1), 0), items.count - 1)].id
        case .enter:
            state.onClose?()
            downloads.open(current)
        case .copy:
            Sharing.copy([current.url])
        case .delete:
            break
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("İndirilenler").font(.system(size: 13, weight: .bold))
            Spacer()
            Button {
                downloads.revealFolder()
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 18)
            }
            .buttonStyle(.plain)
            .help("Klasörü Finder'da aç")
        }
    }
}

private struct DownloadTile: View {
    let state: NotchState
    let downloads: DownloadsStore
    let shelf: ShelfStore
    let item: DownloadsStore.Item
    let side: CGFloat
    let isSelected: Bool

    @State private var isHovering = false
    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(spacing: 2) {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().scaledToFit()
                } else {
                    Image(nsImage: FileIcon.icon(forFile: item.url.path)).resizable().scaledToFit().padding(6)
                }
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(item.name)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(item.date, format: .relative(presentation: .named, unitsStyle: .abbreviated))
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: side + 26)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(isHovering || isSelected ? 0.12 : 0)))
        .overlay {
            if isSelected { RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.35), lineWidth: 1) }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture {
            if state.isKeyboardActive { state.onClose?() }
            downloads.open(item)
        }
        .onDrag {
            // Sürükleme sürerken notch kapanırsa kaynak kaybolur (raf ile aynı).
            state.isDraggingFromShelf = true
            return NSItemProvider(contentsOf: item.url) ?? NSItemProvider()
        }
        .contextMenu {
            Button("Aç") { downloads.open(item) }
            Button("Finder'da Göster") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
            Button("Kopyala") { Sharing.copy([item.url]) }
            Button("Rafa Ekle") { shelf.add(item.url) }
            if FormatFamily(url: item.url) != nil {
                Button("Formatını Değiştir…") { state.onConvert?([item.url]) }
            }
            Button("AirDrop ile Gönder") { Sharing.airDrop([item.url]) }
        }
        .help(item.name)
        .task(id: item.url) {
            thumbnail = await downloads.thumbnail(for: item)
        }
    }
}
