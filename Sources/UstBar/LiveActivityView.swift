import SwiftUI

/// Bir şey çalarken kapalı notch'un iki yanı: solda küçük kapak, sağda müziğe göre titreşen dalga.
enum LiveActivity {
    /// Notch'un her iki yanına eklenen genişlik.
    static func earWidth(notchHeight: CGFloat) -> CGFloat {
        max(notchHeight, 24) + 8
    }

    /// Kapalı notch'ta gösterilir; başka bir yan gösterge (etkinlik, bildirim) varsa ona yer bırakır.
    static func isShown(state: NotchState, media: MediaController, isDictating: Bool) -> Bool {
        guard AppSettings.shared.liveActivity, !state.isExpanded, !isDictating,
              media.track?.isPlaying == true else { return false }
        if let hud = state.hud, !hud.usesBubble { return false }
        return true
    }

    /// Kapak renginin dalgada okunacak kadar açık hali.
    static func barColor(_ color: NSColor) -> NSColor {
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0
        (color.usingColorSpace(.sRGB) ?? color).getHue(&h, saturation: &s, brightness: &v, alpha: nil)
        return NSColor(hue: h, saturation: min(s, 0.55), brightness: 1, alpha: 1)
    }
}

struct LiveActivityView: View {
    let track: MediaController.Track
    let tint: NSColor?
    let notchWidth: CGFloat
    let notchHeight: CGFloat

    var body: some View {
        let ear = LiveActivity.earWidth(notchHeight: notchHeight)
        let artSide = max(notchHeight - 12, 16)
        HStack(spacing: 0) {
            artwork
                .frame(width: artSide, height: artSide)
                .clipShape(RoundedRectangle(cornerRadius: artSide * 0.28))
                .frame(width: ear)
                .id(track.title + track.artist)
                .transition(.blurFade(scale: 0.8))
            Color.clear.frame(width: notchWidth)
            VisualizerBars(
                isPlaying: track.isPlaying,
                color: Color(nsColor: tint.map(LiveActivity.barColor) ?? .white),
                spacing: 2
            )
            .frame(width: artSide, height: artSide * 0.75)
            .frame(width: ear)
        }
        .frame(height: notchHeight)
        .animation(.easeInOut(duration: 0.3), value: track.title)
    }

    @ViewBuilder private var artwork: some View {
        if let image = track.artwork {
            Image(nsImage: image).resizable().scaledToFill()
        } else {
            Image(systemName: "music.note")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white.opacity(0.15))
        }
    }
}
