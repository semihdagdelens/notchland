import SwiftUI

struct ShelfView: View {
    let state: NotchState
    let shelf: ShelfStore
    let isDropTargeted: Bool

    @State private var didCopy = false

    /// Yapıldığı görünsün diye düğme kısa süre onay işaretine döner.
    private func copyAll() {
        Sharing.copy(shelf.items.map(\.url))
        didCopy = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { didCopy = false }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.white.opacity(0.15),
                    style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: shelf.items.isEmpty ? [6] : [])
                )
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isDropTargeted ? Color.accentColor.opacity(0.12) : Color.white.opacity(0.04))
                )

            if shelf.items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down.fill").font(.title2)
                    Text("Dosyaları buraya bırak").font(.callout)
                }
                .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 0) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(shelf.items) { item in
                                ShelfItemView(item: item, state: state, shelf: shelf)
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                    VStack(spacing: 0) {
                        BulkDragHandle(urls: shelf.items.map(\.url)) {
                            state.isDraggingFromShelf = true
                        } label: {
                            Image(systemName: "square.stack.3d.up.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 30, height: 28)
                        }
                        .frame(width: 30, height: 28)
                        .help("Tümünü başka yere sürükle")
                        Button(action: copyAll) {
                            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(didCopy ? Color.green : Color.secondary)
                                .frame(width: 30, height: 26)
                        }
                        .buttonStyle(.plain)
                        .help("Tümünü kopyala (⌘V ile yapıştır)")
                        Button {
                            shelf.airDrop(shelf.items)
                        } label: {
                            AirDropIcon(size: 15)
                                .foregroundStyle(.secondary)
                                .frame(width: 30, height: 26)
                        }
                        .buttonStyle(.plain)
                        .help("Tümünü AirDrop ile gönder")
                        Button {
                            shelf.removeAll()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 30, height: 26)
                        }
                        .buttonStyle(.plain)
                        .help("Rafı temizle")
                    }
                    .padding(.trailing, 6)
                }
            }
        }
        .animation(.easeOut(duration: 0.15), value: isDropTargeted)
        // Klavyeyle gezinmede ⌘C rafın tamamını kopyalar.
        .onChange(of: state.keyCommand) { _, command in
            if command?.kind == .copy, !shelf.items.isEmpty { copyAll() }
        }
    }
}

private struct ShelfItemView: View {
    let item: ShelfStore.Item
    let state: NotchState
    let shelf: ShelfStore

    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: item.icon)
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
            Text(item.name)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 72)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(isHovering ? 0.12 : 0))
        )
        .overlay(alignment: .topTrailing) {
            if isHovering {
                Button {
                    shelf.remove(item)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.gray)
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(alignment: .topLeading) {
            if isHovering {
                Button {
                    shelf.airDrop([item])
                } label: {
                    AirDropIcon(size: 12)
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(Circle().fill(Color.blue))
                }
                .buttonStyle(.plain)
                .help("AirDrop ile gönder")
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2) { shelf.open(item) }
        .onDrag {
            state.isDraggingFromShelf = true
            return NSItemProvider(contentsOf: item.url) ?? NSItemProvider()
        }
        .contextMenu {
            Button("Aç") { shelf.open(item) }
            Button("Finder'da Göster") { shelf.revealInFinder(item) }
            Button("Kopyala") { Sharing.copy([item.url]) }
            Button("AirDrop ile Gönder") { shelf.airDrop([item]) }
            if FormatFamily(url: item.url) != nil {
                Button("Formatını Değiştir…") { state.onConvert?([item.url]) }
            }
            Divider()
            Button("Raftan Kaldır") { shelf.remove(item) }
        }
        .help(item.url.path)
    }
}

/// SwiftUI `onDrag` tek öğe sürükler; birden çok dosya için AppKit sürükleme oturumu gerekir.
struct BulkDragHandle<Label: View>: NSViewRepresentable {
    let urls: [URL]
    let onBegin: () -> Void
    @ViewBuilder let label: () -> Label

    func makeNSView(context: Context) -> HandleView {
        let view = HandleView()
        let hosting = NSHostingView(rootView: label())
        hosting.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hosting.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        return view
    }

    func updateNSView(_ view: HandleView, context: Context) {
        view.urls = urls
        view.onBegin = onBegin
    }

    final class HandleView: NSView, NSDraggingSource {
        var urls: [URL] = []
        var onBegin: (() -> Void)?

        /// Olaylar içteki SwiftUI görünümüne değil, sürüklemeyi başlatan bu görünüme gelsin.
        override func hitTest(_ point: NSPoint) -> NSView? {
            frame.contains(point) ? self : nil
        }

        override func mouseDown(with event: NSEvent) {}

        override func mouseDragged(with event: NSEvent) {
            guard !urls.isEmpty else { return }
            onBegin?()
            let origin = convert(event.locationInWindow, from: nil)
            let items = urls.enumerated().map { index, url -> NSDraggingItem in
                let item = NSDraggingItem(pasteboardWriter: url as NSURL)
                // Dosyalar imlecin altında deste gibi hafifçe kayarak durur.
                let offset = CGFloat(min(index, 4)) * 6
                let frame = NSRect(x: origin.x - 24 + offset, y: origin.y - 24 - offset, width: 48, height: 48)
                item.setDraggingFrame(frame, contents: FileIcon.icon(forFile: url.path))
                return item
            }
            beginDraggingSession(with: items, event: event, source: self)
        }

        /// Dosyalar taşınmaz, kopyalanır: raftakiler ve asılları yerinde kalır.
        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            context == .outsideApplication ? .copy : []
        }
    }
}
