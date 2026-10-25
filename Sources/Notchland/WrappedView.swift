import SwiftUI

/// Notchland Wrapped: seçilen dönemde ne kadar ve neyi dinlediğin.
struct WrappedView: View {
    let history: ListeningHistory
    @AppStorage("wrappedPeriod") private var period: ListeningHistory.Period = .week

    private static let gradient = LinearGradient(
        colors: [Color(red: 1, green: 0.45, blue: 0.7), Color(red: 0.65, green: 0.5, blue: 1), Color(red: 0.4, green: 0.75, blue: 1)],
        startPoint: .leading, endPoint: .trailing
    )

    var body: some View {
        // Sayaç ilerledikçe özet yeniden hesaplansın.
        let _ = history.revision
        let summary = history.summary(for: period)
        HStack(alignment: .top, spacing: 18) {
            overview(summary)
                .frame(width: 168, alignment: .leading)
            if summary.topSongs.isEmpty {
                Label("Müzik çaldıkça özetin burada birikecek", systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                topSongs(summary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                topArtists(summary)
                    .frame(width: 120, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Bölümler

    private func overview(_ summary: ListeningHistory.Summary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            PeriodPicker(selection: $period)
                .padding(.bottom, 4)
            Text(Self.duration(summary.seconds))
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(Self.gradient)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(summary.songCount > 0 ? "müzik · \(summary.songCount) farklı şarkı" : "henüz dinleme yok")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            ForEach(Self.facts(summary, period: period), id: \.self) { fact in
                Text(fact)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
        }
    }

    private func topSongs(_ summary: ListeningHistory.Summary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            header("En çok dinlenenler")
            ForEach(Array(summary.topSongs.enumerated()), id: \.element.id) { index, stat in
                HStack(spacing: 8) {
                    Text("\(index + 1)")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(index == 0 ? AnyShapeStyle(Self.gradient) : AnyShapeStyle(Color.white.opacity(0.45)))
                        .frame(width: 12)
                    SongArtwork(image: history.artwork(for: stat.song))
                        .frame(width: 26, height: 26)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(stat.song.title)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        Text(stat.song.artist)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Text(stat.plays > 1 ? "\(stat.plays)×" : Self.duration(stat.seconds))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func topArtists(_ summary: ListeningHistory.Summary) -> some View {
        let top = summary.topArtists.first?.seconds ?? 1
        return VStack(alignment: .leading, spacing: 8) {
            header("Sanatçılar")
            ForEach(summary.topArtists) { artist in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(artist.name)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        Text(Self.duration(artist.seconds))
                            .font(.system(size: 9).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    GeometryReader { proxy in
                        Capsule()
                            .fill(Self.gradient)
                            .frame(width: max(4, proxy.size.width * artist.seconds / max(top, 1)))
                    }
                    .frame(height: 3)
                }
            }
        }
    }

    private func header(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(.white.opacity(0.4))
    }

    // MARK: - Metinler

    static func duration(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes) dk" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "\(hours) sa" : "\(hours) sa \(rest) dk"
    }

    /// Özetin altındaki en fazla iki küçük not.
    private static func facts(_ summary: ListeningHistory.Summary, period: ListeningHistory.Period) -> [String] {
        var facts: [String] = []
        if summary.streak >= 2 { facts.append("🔥 \(summary.streak) gündür her gün müzik") }
        if let hour = summary.peakHour, period != .today {
            let label = String(format: "%02d:00", hour)
            facts.append((0...5).contains(hour) ? "🦉 Gece kuşu: en çok \(label)" : "⏰ En çok \(label) civarı")
        }
        if let top = summary.topSongs.first, top.plays >= 3, facts.count < 2 {
            facts.append("🔁 Favorin \(top.plays) kez çaldı")
        }
        return Array(facts.prefix(2))
    }
}

private struct PeriodPicker: View {
    @Binding var selection: ListeningHistory.Period

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ListeningHistory.Period.allCases) { period in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { selection = period }
                } label: {
                    Text(period.title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(selection == period ? Color.black : Color.white.opacity(0.6))
                        .fixedSize()
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background {
                            if selection == period { Capsule().fill(Color.white) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(0.1)))
    }
}

private struct SongArtwork: View {
    let image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white.opacity(0.12))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// Ayarlarda geçmişi silme satırı.
struct ListeningHistoryRow: View {
    @State private var confirming = false

    var body: some View {
        LabeledContent("Dinleme geçmişi") {
            Button("Geçmişi sil…") { confirming = true }
        }
        .confirmationDialog("Tüm dinleme geçmişi silinsin mi?", isPresented: $confirming) {
            Button("Sil", role: .destructive) { ListeningHistory.requestReset() }
        } message: {
            Text("Wrapped özeti sıfırlanır; bu geri alınamaz.")
        }
    }
}
