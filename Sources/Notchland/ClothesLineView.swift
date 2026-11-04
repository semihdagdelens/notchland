import SwiftUI

/// Panonun çamaşır ipi görünümü: ekran görüntüleri ve kopyalanan her şey mandalla ipe asılır.
/// Kısayolla açılır; fareyle açılan pano sekmesi listeyle başlar, ikisi arasında düğmeyle geçilir.
struct ClothesLineView: View {
    let state: NotchState
    let clipboard: ClipboardStore
    let items: [ClipboardStore.Item]
    let selectedID: ClipboardStore.Item.ID?

    /// Bir kartın ipte kapladığı genişlik; ip parçaları bu aralıkla birbirine eklenir.
    /// En küçük panelde 116; panel uzadıkça kart oranı bozulmasın diye genişlik de büyür.
    private static func pitch(forHeight height: CGFloat) -> CGFloat {
        max(116, height * 0.92)
    }

    var body: some View {
        HStack(spacing: 0) {
            GeometryReader { proxy in
                let pitch = Self.pitch(forHeight: proxy.size.height)
                ScrollViewReader { scroller in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                HangingCard(
                                    state: state, clipboard: clipboard, item: item, order: index, width: pitch - 16,
                                    isSelected: state.isKeyboardActive && item.id == selectedID
                                )
                                .frame(width: pitch, height: proxy.size.height, alignment: .top)
                                .background(alignment: .top) { Rope() }
                                .id(item.id)
                            }
                            // İp az öğede de görünümün sonuna kadar uzansın.
                            ForEach(0..<fillerCount(width: proxy.size.width, pitch: pitch), id: \.self) { _ in
                                Rope().frame(width: pitch, height: proxy.size.height, alignment: .top)
                            }
                        }
                    }
                    .onChange(of: selectedID) { _, id in
                        guard let id else { return }
                        withAnimation(.easeOut(duration: 0.18)) { scroller.scrollTo(id, anchor: .center) }
                    }
                }
                .overlay {
                    if items.isEmpty {
                        Label("İp boş; kopyaladıkların buraya asılacak", systemImage: "tshirt")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            controls
        }
    }

    private func fillerCount(width: CGFloat, pitch: CGFloat) -> Int {
        max(Int((width / pitch).rounded(.up)) - items.count, 0) + 1
    }

    private var controls: some View {
        VStack(spacing: 2) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { state.showsClothesline = false }
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("Liste görünümü")
            Button {
                clipboard.removeAll()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("Geçmişi temizle")
        }
        .foregroundStyle(.secondary)
        .padding(.leading, 4)
    }
}

/// İpin bir kartlık parçası: mandalın olduğu orta nokta ağırlıkla hafifçe aşağı iner.
private struct Rope: View {
    /// Mandalın ipi kavradığı yükseklik.
    static let pinY: CGFloat = 8

    var body: some View {
        Canvas { context, size in
            let baseline = Self.pinY - 2.5
            var path = Path()
            path.move(to: CGPoint(x: 0, y: baseline - 2.5))
            // Son nokta tam kenara düşsün: parça genişliği 4'e bölünmese de ip kopuk görünmesin.
            for x in Array(stride(from: CGFloat(0), to: size.width, by: 4)) + [size.width] {
                let phase = 2 * CGFloat.pi * (x - size.width / 2) / size.width
                path.addLine(to: CGPoint(x: x, y: baseline + 2.5 * cos(phase)))
            }
            context.stroke(path, with: .color(Color(red: 0.85, green: 0.8, blue: 0.7)), lineWidth: 1.4)
        }
        .frame(height: 20)
        .allowsHitTesting(false)
    }
}

private struct HangingCard: View {
    let state: NotchState
    let clipboard: ClipboardStore
    let item: ClipboardStore.Item
    let order: Int
    let width: CGFloat
    let isSelected: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHanging = false
    @State private var isSwaying = false
    @State private var isHovering = false
    @State private var preview: NSImage?

    /// Kimlikten türetilir: her kart hep aynı açıyla asılı durur, yeniden çizimde zıplamaz.
    private var seed: Double { Double(item.id.uuid.0) / 255 }
    private var tilt: Double { (seed - 0.5) * 6 }
    private var isFocused: Bool { isHovering || isSelected }
    /// Büyük kartta yazılar da büyür; en küçük panelde 1.
    private var textScale: CGFloat { width / 100 }

    var body: some View {
        ZStack(alignment: .top) {
            card.padding(.top, Rope.pinY + 8).padding(.bottom, 6)
            Clothespin().padding(.top, Rope.pinY - 5)
        }
        .frame(width: width)
        .scaleEffect(isFocused ? 1.04 : 1, anchor: .top)
        .rotationEffect(.degrees(isFocused ? 0 : tilt), anchor: .top)
        .animation(.spring(response: 0.34, dampingFraction: 0.5), value: isFocused)
        // Hafif esinti: yalnızca döndürme canlandırılır, kart ip üzerinde sallanır.
        .rotationEffect(.degrees(reduceMotion ? 0 : isSwaying ? 1.4 : -1.4), anchor: .top)
        .animation(.easeInOut(duration: 1.9 + seed).repeatForever(autoreverses: true), value: isSwaying)
        .offset(y: isHanging ? 0 : -400)
        .opacity(isHanging ? 1 : 0)
        .zIndex(isFocused ? 1 : 0)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { state.paste(item, using: clipboard) }
        .onDrag {
            // Sürükleme sürerken notch kapanırsa kaynak kaybolur (raf ile aynı).
            state.isDraggingFromShelf = true
            return item.dragProvider(using: clipboard)
        }
        .contextMenu { ClipboardItemMenu(state: state, clipboard: clipboard, item: item) }
        .help("Tıkla: yapıştır · Sürükle: başka yere bırak · Sağ tık: diğer seçenekler")
        .onAppear {
            // Kartlar sırayla, ipe asılır gibi yukarıdan iner.
            let delay = reduceMotion ? 0 : 0.045 * Double(min(order, 6))
            withAnimation(.spring(response: 0.5, dampingFraction: 0.62).delay(delay)) { isHanging = true }
            isSwaying = true
        }
        .task(id: item.id) {
            if item.kind == .image { preview = await clipboard.preview(for: item) }
        }
    }

    private var card: some View {
        VStack(spacing: 3) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            HStack(spacing: 3) {
                Circle().fill(item.tint).frame(width: 5, height: 5)
                Text(item.date, format: .relative(presentation: .named, unitsStyle: .abbreviated))
                    .lineLimit(1)
            }
            .font(.system(size: 8 * textScale, weight: .medium))
            .foregroundStyle(.black.opacity(0.5))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(5)
        .background(RoundedRectangle(cornerRadius: 3).fill(Color(red: 0.97, green: 0.95, blue: 0.9)))
        .overlay {
            if isSelected { RoundedRectangle(cornerRadius: 3).strokeBorder(Color.accentColor, lineWidth: 2) }
        }
        .shadow(color: .black.opacity(0.45), radius: 3, x: 1, y: 2)
    }

    @ViewBuilder private var content: some View {
        switch item.kind {
        case .image:
            if let preview {
                // Doldururken kartı genişletmesin: boyutu zemin belirler, görsel taşanı kırpılır.
                Color.clear.overlay { Image(nsImage: preview).resizable().scaledToFill() }.clipped()
            } else {
                Image(systemName: "photo").foregroundStyle(.black.opacity(0.3))
            }
        case .text:
            // Uzun kopyalar kart başına binlerce satır dizmesin.
            Text(String((item.text ?? "").prefix(220)))
                .font(.system(size: 9 * textScale, weight: .regular, design: .serif))
                .foregroundStyle(.black.opacity(0.82))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .link:
            VStack(alignment: .leading, spacing: 3) {
                Image(systemName: "link").font(.system(size: 13 * textScale, weight: .bold))
                Text(item.title)
                    .font(.system(size: 9 * textScale, weight: .medium))
                    .lineLimit(5)
            }
            .foregroundStyle(Color(red: 0.05, green: 0.38, blue: 0.62))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .files:
            VStack(spacing: 3) {
                if let first = item.filePaths?.first {
                    Image(nsImage: FileIcon.icon(forFile: first)).resizable().scaledToFit().frame(width: 40 * textScale, height: 40 * textScale)
                }
                Text(item.title)
                    .font(.system(size: 9 * textScale, weight: .medium))
                    .foregroundStyle(.black.opacity(0.8))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

/// Tahta mandal: iki yanak ve ortasında metal yay.
private struct Clothespin: View {
    var body: some View {
        ZStack {
            HStack(spacing: 0.8) {
                RoundedRectangle(cornerRadius: 1.5).fill(Color(red: 0.8, green: 0.62, blue: 0.42))
                RoundedRectangle(cornerRadius: 1.5).fill(Color(red: 0.7, green: 0.52, blue: 0.34))
            }
            .frame(width: 8, height: 21)
            RoundedRectangle(cornerRadius: 0.8)
                .fill(Color(white: 0.78))
                .frame(width: 10, height: 2.6)
                .offset(y: -1)
        }
        .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
    }
}
