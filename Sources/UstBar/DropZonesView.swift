import SwiftUI

/// Notch'a içerik sürüklenirken gösterilen iki bırakma alanı: raf ve AirDrop.
struct DropZonesView: View {
    let shelf: ShelfStore

    var body: some View {
        HStack(spacing: 12) {
            if AppSettings.shared.showShelfTab {
                DropZone(title: "Rafa Ekle", symbol: "tray.and.arrow.down.fill", tint: .white) {
                    shelf.handleDrop($0)
                }
            }
            DropZone(title: "AirDrop", symbol: "airplayaudio", tint: .blue, customIcon: AnyView(AirDropIcon())) {
                shelf.airDrop($0)
            }
        }
    }
}

private struct DropZone: View {
    let title: String
    let symbol: String
    let tint: Color
    var customIcon: AnyView?
    let onDrop: ([NSItemProvider]) -> Bool

    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 8) {
            if let customIcon {
                customIcon
            } else {
                Image(systemName: symbol).font(.system(size: 24, weight: .semibold))
            }
            Text(title).font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(isTargeted ? tint : .white.opacity(0.7))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isTargeted ? tint.opacity(0.15) : Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isTargeted ? tint : Color.white.opacity(0.2),
                    style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: isTargeted ? [] : [6])
                )
        )
        .scaleEffect(isTargeted ? 1.03 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isTargeted)
        .onDrop(of: ShelfStore.acceptedTypes, isTargeted: $isTargeted, perform: onDrop)
    }
}

/// AirDrop'un iç içe halkalı ikonu (SF Symbols'te genel bir AirDrop sembolü yok).
struct AirDropIcon: View {
    var size: CGFloat = 26

    var body: some View {
        ZStack {
            ForEach(0..<3) { ring in
                Circle()
                    .trim(from: 0.0, to: 0.75)
                    .rotation(.degrees(135))
                    .stroke(style: StrokeStyle(lineWidth: size * 0.08, lineCap: .round))
                    .frame(width: size * (0.35 + CGFloat(ring) * 0.3), height: size * (0.35 + CGFloat(ring) * 0.3))
            }
            Circle().frame(width: size * 0.14, height: size * 0.14)
        }
        .frame(width: size, height: size)
    }
}
