import SwiftUI

/// Notch'ta yaşayan piksel kedi Koci'nin paylaşılan hâli. Kapalı notch'a asılı Koci ile
/// açık paneldeki Koci aynı tepkiyi gösterir.
@Observable
final class Koci {
    /// Tıklanınca ya da şarj takılınca bu ana kadar sevinir.
    private(set) var excitedUntil = Date.distantPast
    /// Her tepkide başka bir söz seçilsin diye.
    private(set) var reactionCount = 0

    func react(for duration: TimeInterval = 2.5) {
        excitedUntil = .now + duration
        reactionCount += 1
    }
}

/// O anki duruma göre Koci'nin ruh hâli, karesi ve sözü.
enum KociMood {
    case excited, lowBattery, hot, music, sleepy, idle

    static func current(at date: Date, koci: Koci, media: MediaController, battery: BatteryMonitor) -> KociMood {
        if date < koci.excitedUntil { return .excited }
        if let status = battery.status, !status.isPluggedIn,
           status.level <= max(AppSettings.shared.lowBatteryThreshold, 10) { return .lowBattery }
        if ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue { return .hot }
        if media.track?.isPlaying == true { return .music }
        if (0..<6).contains(Calendar.current.component(.hour, from: date)) { return .sleepy }
        return .idle
    }

    /// Müzikte vuruşa, sevinçte zıplamaya yetişmek için saniyede 8, boşta 4 kare (göz kırpma ~0.3 sn sürer).
    static func frameInterval(koci: Koci, media: MediaController) -> TimeInterval {
        media.track?.isPlaying == true || Date.now < koci.excitedUntil ? 1 / 8 : 1 / 4
    }

    /// Kare ve dikey sıçrama (piksel); animasyon zamandan hesaplanır.
    func frame(pose: KociSprite.Pose, at date: Date, media: MediaController) -> (KociSprite.Frame, bob: CGFloat) {
        let t = date.timeIntervalSinceReferenceDate
        let tick = { (rate: Double) in Int(t * rate) % 2 }
        switch self {
        case .excited:
            return (.init(pose: pose, eyes: .star, tail: tick(6)), tick(6) == 0 ? -1 : 0)
        case .lowBattery:
            return (.init(pose: pose, eyes: .sad, tail: 0), 0)
        case .hot:
            return (.init(pose: pose, eyes: .open, tail: tick(2), extra: .sweat), 0)
        case .music:
            // Bas vurunca kafa sallar.
            let onBeat = media.track.map { media.visualizer.energy(for: $0, at: date) > 0.55 } ?? false
            return (.init(pose: pose, eyes: .happy, tail: tick(3), extra: .note), onBeat ? -1 : 0)
        case .sleepy:
            return (.init(pose: pose, eyes: .closed, tail: tick(1), extra: .sleep), 0)
        case .idle:
            // Arada bir göz kırpar.
            let blinking = t.truncatingRemainder(dividingBy: 4.3) < 0.3
            return (.init(pose: pose, eyes: blinking ? .closed : .open, tail: tick(0.8)), 0)
        }
    }

    func line(at date: Date, reactions: Int) -> String {
        switch self {
        case .excited:
            let lines = ["Miyav! 👋", "Ben Koci, notch benim evim!", "Pıt pıt pıt…", "Bir daha! Bir daha!", "⚡ Enerji doluyor!"]
            return lines[reactions % lines.count]
        case .lowBattery: return "Pilim bitiyor… şarja tak beni 🥺"
        case .hot: return "Burası çok ısındı. Sorun yok… 🔥"
        case .music: return "Bu şarkı güzelmiş ♪"
        case .sleepy: return "Zzz… Bu saatte uyumuyor musun?"
        case .idle:
            let lines = [
                "Bir şarkı açsana, sıkıldım.",
                "Bugün ne dinliyoruz?",
                "Çentiğin altı benim mekânım.",
                "Bana tıkla, sevilmeyi severim.",
            ]
            return lines[Int(date.timeIntervalSinceReferenceDate / 30) % lines.count]
        }
    }
}

/// Kapalı notch'un alt kenarına tutunan Koci; kolları notch'un arkasına girer.
struct KociHanging: View {
    static let pixel: CGFloat = 2
    /// Kolların notch'un arkasında kalan satır sayısı.
    static let tuckedRows: CGFloat = 3

    let koci: Koci
    let media: MediaController
    let battery: BatteryMonitor
    let isHovering: Bool

    var body: some View {
        KociSpriteView(pose: .hanging, pixel: Self.pixel) { [koci, media, battery, isHovering] date in
            let mood = KociMood.current(at: date, koci: koci, media: media, battery: battery)
            var (frame, bob) = mood.frame(pose: .hanging, at: date, media: media)
            // Fare notch'a gelince sevinir.
            if isHovering && mood == .idle { frame.eyes = .happy }
            return (frame, bob, KociMood.frameInterval(koci: koci, media: media))
        }
        .allowsHitTesting(false)
    }
}

/// Açık panelde, çalan bir şey yokken ana sayfada oturan Koci ve konuşma balonu.
struct KociCorner: View {
    let koci: Koci
    let media: MediaController
    let battery: BatteryMonitor

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            KociSpriteView(pose: .sitting, pixel: 4) { [koci, media, battery] date in
                let mood = KociMood.current(at: date, koci: koci, media: media, battery: battery)
                let (frame, bob) = mood.frame(pose: .sitting, at: date, media: media)
                return (frame, bob, KociMood.frameInterval(koci: koci, media: media))
            }
            .contentShape(Rectangle())
            .onTapGesture { koci.react() }
            .help("Koci")
            // Söz nadiren değişir; saniyede bir bakmak yeter.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let mood = KociMood.current(at: context.date, koci: koci, media: media, battery: battery)
                Text(mood.line(at: context.date, reactions: koci.reactionCount))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(SpeechBubble().fill(Color.white.opacity(0.12)))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 170, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Sol kenarında Koci'ye bakan küçük kuyruğu olan balon.
private struct SpeechBubble: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: rect, cornerRadius: 10)
        path.move(to: CGPoint(x: rect.minX, y: rect.midY - 5))
        path.addLine(to: CGPoint(x: rect.minX - 6, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY + 5))
        path.closeSubpath()
        return path
    }
}
