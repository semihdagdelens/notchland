import SwiftUI

struct ShelfView: View {
    let state: NotchState
    let shelf: ShelfStore
    let isDropTargeted: Bool

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
                    VStack(spacing: 2) {
                        Button {
                            shelf.airDrop(shelf.items)
                        } label: {
                            AirDropIcon(size: 16)
                                .foregroundStyle(.secondary)
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                        .help("Tümünü AirDrop ile gönder")
                        Button {
                            shelf.removeAll()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                        .help("Rafı temizle")
                    }
                    .padding(.trailing, 6)
                }
            }
        }
        .animation(.easeOut(duration: 0.15), value: isDropTargeted)
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
            Button("AirDrop ile Gönder") { shelf.airDrop([item]) }
            Divider()
            Button("Raftan Kaldır") { shelf.remove(item) }
        }
        .help(item.url.path)
    }
}
