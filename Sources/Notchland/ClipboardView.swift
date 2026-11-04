import SwiftUI

/// Pano geçmişi: türe göre renklenen satırlar, görsel önizlemesi, boyut ve tür filtresi.
struct ClipboardView: View {
    let state: NotchState
    let clipboard: ClipboardStore

    enum Filter: CaseIterable {
        case all, text, image, link, files

        var symbol: String {
            switch self {
            case .all: "square.stack"
            case .text: "text.alignleft"
            case .image: "photo"
            case .link: "link"
            case .files: "doc"
            }
        }

        var title: String {
            switch self {
            case .all: "Tümü"
            case .text: "Metinler"
            case .image: "Görseller ve ekran görüntüleri"
            case .link: "Bağlantılar"
            case .files: "Dosyalar"
            }
        }

        func matches(_ item: ClipboardStore.Item) -> Bool {
            switch self {
            case .all: true
            case .text: item.kind == .text
            case .image: item.kind == .image
            case .link: item.kind == .link
            case .files: item.kind == .files
            }
        }
    }

    @State private var filter: Filter = .all
    /// Klavyeyle seçilen öğe; yoksa ilk öğe seçili sayılır.
    @State private var selection: ClipboardStore.Item.ID?

    private var visibleItems: [ClipboardStore.Item] {
        clipboard.items.filter(filter.matches)
    }

    var body: some View {
        VStack(spacing: 6) {
            if state.showsClothesline {
                ClothesLineView(
                    state: state, clipboard: clipboard, items: visibleItems,
                    selectedID: state.isKeyFocused(KeyStop.contentID(.clipboard)) ? selectedItem?.id : nil
                )
                .keyContent(.clipboard, row: 1, axis: .horizontal, isEnabled: !visibleItems.isEmpty)
            } else {
            header
            if visibleItems.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: filter == .all ? "doc.on.clipboard" : filter.symbol).font(.title3)
                    Text(filter == .all ? "Kopyaladıkların burada görünecek" : "Bu türde öğe yok")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 5) {
                            ForEach(visibleItems) { item in
                                ClipboardRow(
                                    state: state, item: item, clipboard: clipboard,
                                    isSelected: state.isKeyFocused(KeyStop.contentID(.clipboard)) && item.id == selectedItem?.id
                                )
                                .id(item.id)
                            }
                        }
                    }
                    .onChange(of: selection) { _, id in
                        guard let id else { return }
                        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) }
                    }
                }
                .keyContent(.clipboard, row: 1, axis: .vertical)
            }
            }
        }
        .onChange(of: state.keyCommand) { _, command in
            if let command { perform(command.kind) }
        }
    }

    private var selectedItem: ClipboardStore.Item? {
        visibleItems.first { $0.id == selection } ?? visibleItems.first
    }

    /// Klavyeyle gezinme: ↑ ↓ seçer (listenin başında ↑ düğmelere çıkar), Return yapıştırır, ⌘C kopyalar, ⌫ siler.
    private func perform(_ command: NotchState.KeyCommand.Kind) {
        let items = visibleItems
        guard let current = selectedItem, let index = items.firstIndex(of: current) else { return }
        switch command {
        case .up, .down:
            if command == .up && index == 0 && !state.showsClothesline {
                state.moveKeyFocus(rowBy: -1)
                return
            }
            let next = min(max(index + (command == .down ? 1 : -1), 0), items.count - 1)
            selection = items[next].id
        case .enter, .copy:
            // Önce notch kapanıp odak öndeki uygulamaya dönsün, sonra yapıştırılsın.
            state.onClose?()
            clipboard.copy(current, paste: command == .enter)
        case .delete:
            selection = items.indices.contains(index + 1) ? items[index + 1].id : (index > 0 ? items[index - 1].id : nil)
            clipboard.remove(current)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Pano").font(.system(size: 13, weight: .bold))
                Text("\(clipboard.items.count) öğe")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 2) {
                ForEach(Array(Filter.allCases.enumerated()), id: \.element) { index, option in
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { filter = option }
                    } label: {
                        Image(systemName: option.symbol)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(filter == option ? Color.white : Color.white.opacity(0.4))
                            .frame(width: 22, height: 20)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.white.opacity(filter == option ? 0.16 : 0))
                            )
                    }
                    .buttonStyle(.plain)
                    .help(option.title)
                    .keyStop(state, .clipboard, "filter\(index)", order: index, outset: 0) {
                        withAnimation(.easeOut(duration: 0.15)) { filter = option }
                    }
                }
            }
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { state.showsClothesline = true }
            } label: {
                Image(systemName: "tshirt")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 20)
            }
            .buttonStyle(.plain)
            .help("Çamaşır ipi görünümü")
            // İp görünümündeki karşılığıyla aynı ad: görünüm değişince seçim düğmede kalsın.
            .keyStop(state, .clipboard, "view", order: Filter.allCases.count, outset: 0) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { state.showsClothesline = true }
            }
            Button {
                clipboard.removeAll()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 20)
            }
            .buttonStyle(.plain)
            .help("Geçmişi temizle")
            .keyStop(state, .clipboard, "clear", order: Filter.allCases.count + 1, outset: 0) { clipboard.removeAll() }
        }
    }
}

private struct ClipboardRow: View {
    let state: NotchState
    let item: ClipboardStore.Item
    let clipboard: ClipboardStore
    var isSelected = false

    @State private var isHovering = false

    private var isHighlighted: Bool { isHovering || isSelected }

    var body: some View {
        HStack(spacing: 10) {
            thumbnail
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 4) {
                    Text(item.kindLabel)
                        .foregroundStyle(tint)
                    Text("·")
                    Text(item.date, format: .relative(presentation: .named, unitsStyle: .abbreviated))
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isHovering {
                Button {
                    clipboard.remove(item)
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
            Button {
                clipboard.copy(item, paste: false)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .help("Sadece kopyala")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(isHighlighted ? 0.32 : 0.22), tint.opacity(isHighlighted ? 0.14 : 0.08)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.white.opacity(isSelected ? 0.35 : isHovering ? 0.14 : 0.06), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .onTapGesture { state.paste(item, using: clipboard) }
        .onDrag { item.dragProvider(using: clipboard) }
        .contextMenu { ClipboardItemMenu(state: state, clipboard: clipboard, item: item) }
        .help("Tıkla: yapıştır · Sürükle: başka yere bırak · Sağ tık: diğer seçenekler")
    }

    // MARK: - İçerik

    @ViewBuilder private var thumbnail: some View {
        switch item.kind {
        case .image:
            if let image = clipboard.thumbnail(for: item) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                iconTile("photo")
            }
        case .files:
            if let first = item.filePaths?.first {
                Image(nsImage: FileIcon.icon(forFile: first)).resizable().scaledToFit().padding(2)
            } else {
                iconTile("doc")
            }
        case .link:
            iconTile("link")
        case .text:
            iconTile("doc.text")
        }
    }

    private func iconTile(_ symbol: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.35))
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    private var tint: Color { item.tint }
}

/// Satırların ve ipteki kartların ortak sağ tık menüsü.
struct ClipboardItemMenu: View {
    let state: NotchState
    let clipboard: ClipboardStore
    let item: ClipboardStore.Item

    var body: some View {
        Button("Yapıştır") { state.paste(item, using: clipboard) }
        Button("Sadece Kopyala") { clipboard.copy(item, paste: false) }
        if let url = item.originalFileURL {
            Button("Finder'da Göster") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
        if item.kind == .image || item.kind == .files {
            Button("Formatını Değiştir…") { state.onConvert?(clipboard.fileURLs(for: item)) }
        }
        if let link = item.videoLink, ExternalTool.ytDlp.path != nil {
            Button("Videoyu İndir…") { state.onConvert?([link]) }
        }
        Divider()
        Button("Sil") { clipboard.remove(item) }
    }
}

extension NotchState {
    /// Klavyeyle açıkken panel odaktadır; ⌘V öndeki uygulamaya gitsin diye önce notch kapanır.
    func paste(_ item: ClipboardStore.Item, using clipboard: ClipboardStore) {
        if isKeyboardActive { onClose?() }
        clipboard.copy(item, paste: true)
    }
}

extension ClipboardStore.Item {
    var title: String {
        switch kind {
        case .text:
            let firstLine = (text ?? "").split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            return firstLine.trimmingCharacters(in: .whitespaces)
        case .link:
            return text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        case .image:
            let base = isScreenshot == true ? "Ekran görüntüsü" : "Görsel"
            if let w = pixelWidth, let h = pixelHeight { return "\(base) \(w)×\(h)" }
            return base
        case .files:
            let paths = filePaths ?? []
            return paths.count == 1 ? (paths[0] as NSString).lastPathComponent : "\(paths.count) dosya"
        }
    }

    var kindLabel: String {
        switch kind {
        case .text: "Metin"
        case .link: "Bağlantı"
        case .image: isScreenshot == true ? "Ekran görüntüsü" : "Görsel"
        case .files: "Dosya"
        }
    }

    var tint: Color {
        switch kind {
        case .text: Color(red: 0.25, green: 0.45, blue: 0.95)
        case .link: Color(red: 0.15, green: 0.65, blue: 0.75)
        case .image: Color(red: 0.62, green: 0.3, blue: 0.9)
        case .files: Color(red: 0.9, green: 0.55, blue: 0.2)
        }
    }

    /// Ekran görüntüsü veya tek dosyanın diskteki asıl konumu.
    var originalFileURL: URL? {
        guard kind == .files || isScreenshot == true,
              let path = filePaths?.first, FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    func dragProvider(using clipboard: ClipboardStore) -> NSItemProvider {
        switch kind {
        case .text, .link:
            return NSItemProvider(object: (text ?? "") as NSString)
        case .image:
            if let image = clipboard.image(for: self) { return NSItemProvider(object: image) }
            return NSItemProvider()
        case .files:
            return filePaths?.first.flatMap { NSItemProvider(contentsOf: URL(fileURLWithPath: $0)) } ?? NSItemProvider()
        }
    }
}
