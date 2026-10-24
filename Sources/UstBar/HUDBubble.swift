import SwiftUI

/// Notch'un sağ kenarından "damla gibi" ayrılan gösterge baloncuğu (ses, parlaklık, pil).
/// `presence` 0'dan 1'e giderken baloncuk notch'un içinden çıkar; yakınken incelen bir
/// boyunla notch'a bağlı kalır, sona doğru boyun kopar ve baloncuk ayrı durur.
/// Kaybolurken aynı yolu tersine izleyip notch'a geri karışır.
struct HUDBubble: View {
    let hud: HUD?
    let isExpanded: Bool
    /// Kapalı notch gövdesinin yüksekliği.
    let notchHeight: CGFloat

    /// Kaybolma animasyonu sürerken içerik boşalmasın diye son baloncuk HUD'u tutulur.
    @State private var lastHUD: HUD?

    static let gap: CGFloat = 7

    private var diameter: CGFloat { max(notchHeight - 6, 18) }
    private var isShowing: Bool { !isExpanded && hud?.usesBubble == true }

    var body: some View {
        let d = diameter
        let presence: CGFloat = isShowing ? 1 : 0
        BubbleSurface(presence: presence, diameter: d, notchHeight: notchHeight, gap: Self.gap)
            .fill(Color.black)
            .overlay(alignment: .topLeading) {
                if let shown = lastHUD {
                    BubbleContent(hud: shown, diameter: d)
                        .modifier(BubbleContentPlacement(
                            presence: presence, diameter: d, notchHeight: notchHeight, gap: Self.gap
                        ))
                }
            }
            .frame(width: Self.gap + d + 4, height: notchHeight, alignment: .topLeading)
            .allowsHitTesting(false)
            .animation(.spring(response: 0.55, dampingFraction: 0.68), value: isShowing)
            .onChange(of: hud) { _, newValue in
                if let newValue, newValue.usesBubble { lastHUD = newValue }
            }
            .onAppear { if let hud, hud.usesBubble { lastHUD = hud } }
    }
}

/// Baloncuk geometrisi; yerel koordinatta x = 0 notch gövdesinin sağ kenarıdır.
private struct BubbleGeometry {
    let presence: CGFloat
    let diameter: CGFloat
    let notchHeight: CGFloat
    let gap: CGFloat

    var radius: CGFloat { diameter / 2 * (0.55 + 0.45 * min(max(presence, 0), 1.1)) }
    /// p = 0'da merkez notch'un içinde (görünmez), p = 1'de kenardan `gap` kadar uzakta.
    var center: CGPoint {
        CGPoint(x: -diameter / 2 + presence * (diameter / 2 + gap + diameter / 2), y: notchHeight / 2)
    }
    var rect: CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }
}

private struct BubbleSurface: Shape {
    var presence: CGFloat
    let diameter: CGFloat
    let notchHeight: CGFloat
    let gap: CGFloat

    var animatableData: CGFloat {
        get { presence }
        set { presence = newValue }
    }

    func path(in _: CGRect) -> Path {
        let g = BubbleGeometry(presence: presence, diameter: diameter, notchHeight: notchHeight, gap: gap)
        guard presence > 0.01 else { return Path() }
        var path = Path(ellipseIn: g.rect)
        if let neck = neck(g) { path.addPath(neck) }
        return path
    }

    /// İki şekli birleştiren, ayrılma ilerledikçe incelen köprü (metaball etkisi).
    private func neck(_ g: BubbleGeometry) -> Path? {
        let bubble = g.rect
        let separation = bubble.minX
        let release = gap * 0.9
        guard separation > -bubble.width * 0.5, separation < release else { return nil }
        let s = max(0, separation) / release
        let half = bubble.height / 2
        let waist = half * 0.55 * pow(1 - s, 1.4)
        guard waist > 0.4 else { return nil }

        let midY = bubble.midY
        let anchorHalf = min(half * 0.8, notchHeight / 2 - 1)
        let x0 = -min(notchHeight / 2, half)
        var path = Path()
        path.move(to: CGPoint(x: x0, y: midY - anchorHalf))
        path.addCurve(
            to: CGPoint(x: bubble.midX, y: midY - half * 0.7),
            control1: CGPoint(x: 0, y: midY - waist),
            control2: CGPoint(x: bubble.minX, y: midY - waist)
        )
        path.addLine(to: CGPoint(x: bubble.midX, y: midY + half * 0.7))
        path.addCurve(
            to: CGPoint(x: x0, y: midY + anchorHalf),
            control1: CGPoint(x: bubble.minX, y: midY + waist),
            control2: CGPoint(x: 0, y: midY + waist)
        )
        path.closeSubpath()
        return path
    }
}

/// İçeriği baloncuğun merkezine taşır; baloncuk yeterince ayrılınca belirir.
private struct BubbleContentPlacement: ViewModifier, Animatable {
    var presence: CGFloat
    let diameter: CGFloat
    let notchHeight: CGFloat
    let gap: CGFloat

    var animatableData: CGFloat {
        get { presence }
        set { presence = newValue }
    }

    func body(content: Content) -> some View {
        let g = BubbleGeometry(presence: presence, diameter: diameter, notchHeight: notchHeight, gap: gap)
        let t = min(1, max(0, (presence - 0.45) / 0.45))
        let fade = t * t * (3 - 2 * t)
        content
            .frame(width: diameter, height: diameter)
            .scaleEffect(g.radius * 2 / diameter)
            .opacity(fade)
            .blur(radius: (1 - fade) * 3)
            .offset(x: g.center.x - diameter / 2, y: g.center.y - diameter / 2)
    }
}

/// Baloncuğun içi: seviye halkası ve ikon.
private struct BubbleContent: View {
    let hud: HUD
    let diameter: CGFloat

    var body: some View {
        let line = max(2, diameter * 0.09)
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: line)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(level, 0), 1)))
                .stroke(tint, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.15), value: level)
            Image(systemName: symbol)
                .font(.system(size: diameter * 0.34, weight: .semibold))
                .foregroundStyle(iconTint)
                .contentTransition(.symbolEffect(.replace))
        }
        .padding(line / 2 + 2)
    }

    private var level: Float {
        switch hud {
        case let .volume(level, isMuted, _): isMuted ? 0 : level
        case let .brightness(level): level
        case let .battery(status): Float(status.level) / 100
        case .event, .headphones, .notification: 0
        }
    }

    private var symbol: String {
        switch hud {
        case let .volume(level, isMuted, isHeadphones):
            HUDContent.volumeSymbol(level: level, isMuted: isMuted, isHeadphones: isHeadphones)
        case let .brightness(level):
            level < 0.5 ? "sun.min.fill" : "sun.max.fill"
        case let .battery(status):
            status.isPluggedIn ? "bolt.fill" : "battery.25percent"
        case .event, .headphones, .notification:
            "calendar"
        }
    }

    /// Pil durumu dışında halka beyaz; durum rengi her zaman ikonla birlikte gelir.
    private var tint: Color {
        if case let .battery(status) = hud { return status.isPluggedIn ? .green : .red }
        return .white
    }

    private var iconTint: Color {
        if case .battery = hud { return tint }
        return .white
    }
}
