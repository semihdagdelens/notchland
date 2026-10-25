import SwiftUI

/// Müzik çalarken notch'un çevresinde kapak renginde atan ışık: bas vurdukça büyür ve parlar.
/// Notch şeklinin arkasına çizilir; yalnızca siyah gövdenin dışına taşan kısmı görünür.
struct NotchGlow<S: Shape>: View {
    let shape: S
    let media: MediaController
    let isOpen: Bool
    let isVisible: Bool

    /// Kapak rengi yoksa (veya henüz hesaplanmadıysa) kullanılan mor.
    private static var fallbackColor: NSColor { NSColor(srgbRed: 0.55, green: 0.5, blue: 1, alpha: 1) }

    var body: some View {
        ZStack {
            if isVisible, AppSettings.shared.lightShow, let track = media.track, track.isPlaying {
                let color = Color(nsColor: LiveActivity.barColor(media.artworkColor ?? Self.fallbackColor))
                TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                    let energy = Self.energy(track: track, source: media.visualizer, at: context.date)
                    GeometryReader { proxy in
                        let size = proxy.size
                        // Açık panelin gölgesi ışığı bastırdığı için orada daha yaygın; panelin 32 pt'lik payını aşmaz.
                        let grow = isOpen ? 5 + energy * 10 : 2 + energy * 8
                        shape
                            .fill(color)
                            .scaleEffect(
                                x: (size.width + grow * 2) / max(size.width, 1),
                                y: (size.height + grow) / max(size.height, 1),
                                anchor: .top
                            )
                            .blur(radius: isOpen ? 11 : 7)
                            .opacity(isOpen ? 0.4 + energy * 0.6 : 0.3 + energy * 0.65)
                    }
                }
                .animation(.easeInOut(duration: 0.6), value: color)
                .transition(.opacity.animation(.easeInOut(duration: 0.4)))
            }
        }
        .allowsHitTesting(false)
    }

    /// 0…1 arası enerji: ağırlık bas bandında, biraz da genel seviyede.
    /// Ritim bilinmiyorsa (yapay dalga) dakikada ~117 vuruşluk yumuşak bir nabız.
    private static func energy(track: MediaController.Track, source: VisualizerEngine, at date: Date) -> Double {
        guard let levels = source.levels(for: track, at: date), !levels.isEmpty else {
            let beat = (sin(date.timeIntervalSinceReferenceDate * .pi * 2 * 1.95) + 1) / 2
            return 0.25 + 0.5 * pow(beat, 3)
        }
        // `RhythmRecording` çubukları basları ortaya dizer; seviyeler 0.12…0.98 aralığında.
        let normalize = { (value: Double) in min(max((value - 0.12) / 0.86, 0), 1) }
        let bass = normalize(levels[levels.count / 2])
        let average = normalize(levels.reduce(0, +) / Double(levels.count))
        return bass * 0.65 + average * 0.35
    }
}
