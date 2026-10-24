import SwiftUI

/// Çalarken parçanın ritmiyle oynayan çubuklar; ritim henüz bilinmiyorsa yumuşakça dalgalanır,
/// duraklatılınca alçalır.
struct VisualizerBars: View {
    static let barCount = RhythmRecording.bandCount

    let track: MediaController.Track
    let source: VisualizerEngine
    var color: Color = .white
    var spacing: CGFloat = 2

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1 / 30, paused: !track.isPlaying)) { context in
                bars(levels(at: context.date), in: proxy.size)
            }
        }
    }

    private func bars(_ levels: [Double], in size: CGSize) -> some View {
        let count = CGFloat(levels.count)
        let width = max(1.5, (size.width - spacing * (count - 1)) / count)
        return HStack(alignment: .center, spacing: spacing) {
            ForEach(levels.indices, id: \.self) { index in
                Capsule()
                    .fill(color)
                    .frame(width: width, height: max(width, size.height * CGFloat(min(max(levels[index], 0), 1))))
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func levels(at date: Date) -> [Double] {
        guard track.isPlaying else { return Self.restingLevels }
        return source.levels(for: track, at: date) ?? Self.levels(at: date)
    }

    private static let restingLevels = [Double](repeating: 0.15, count: barCount)

    private static func levels(at date: Date) -> [Double] {
        let t = date.timeIntervalSinceReferenceDate
        return (0..<barCount).map { index in
            let i = Double(index)
            let wave = sin(t * (5.2 + i * 1.3) + i * 1.7) * 0.5 + sin(t * (3.1 + i * 0.7) + i) * 0.5
            return 0.35 + 0.3 * wave
        }
    }
}
