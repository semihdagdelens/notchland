import SwiftUI

/// Sistem sekmesi: her ölçüm için bir kutu (değer + son 40 örneğin küçük grafiği).
struct StatsView: View {
    let stats: SystemStats

    var body: some View {
        HStack(spacing: 8) {
            StatTile(
                title: "CPU",
                value: Self.percent(stats.cpu),
                detail: thermalText ?? "\(stats.coreCount) çekirdek",
                alert: stats.cpu > 85 ? "Yüksek yük" : thermalText,
                history: stats.cpuHistory,
                maxValue: 100
            )
            StatTile(
                title: "Bellek",
                value: Self.percent(stats.memoryFraction * 100),
                detail: "\(Self.gigabytes(stats.memoryUsed)) / \(Self.gigabytes(stats.memoryTotal))",
                alert: memoryAlert,
                history: stats.memoryHistory,
                maxValue: 100
            )
            if let gpu = stats.gpu {
                StatTile(
                    title: "GPU",
                    value: Self.percent(gpu),
                    detail: "Grafik işlemci",
                    alert: gpu > 85 ? "Yüksek yük" : nil,
                    history: stats.gpuHistory,
                    maxValue: 100
                )
            }
            StatTile(
                title: "Ağ",
                value: "↓ " + Self.rate(stats.downloadRate),
                detail: "↑ " + Self.rate(stats.uploadRate),
                alert: nil,
                history: stats.downloadHistory,
                maxValue: nil
            )
            DiskTile(free: stats.diskFree, total: stats.diskTotal)
        }
        .onAppear { stats.isVisible = true }
        .onDisappear { stats.isVisible = false }
    }

    private var thermalText: String? {
        switch stats.thermalState {
        case .serious: "Isınıyor"
        case .critical: "Aşırı sıcak"
        default: nil
        }
    }

    private var memoryAlert: String? {
        switch stats.memoryPressure {
        case .normal: nil
        case .warning: "Bellek baskısı"
        case .critical: "Bellek kritik"
        }
    }

    static func percent(_ value: Double) -> String {
        "%\(Int(value.rounded()))"
    }

    static func gigabytes(_ bytes: Double) -> String {
        String(format: "%.1f GB", bytes / 1_073_741_824)
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .file) + "/sn"
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    let detail: String
    /// Doluysa uyarı ikonu ve metniyle gösterilir (renk tek başına anlam taşımaz).
    let alert: String?
    let history: [Double]
    /// nil: grafiğin üst sınırı verinin en büyüğüne göre ayarlanır.
    let maxValue: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                if alert != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                }
            }
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Sparkline(values: history, maxValue: maxValue)
                .frame(height: 30)
            Text(alert ?? detail)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
        .help("\(title): \(value) · \(detail)")
    }
}

/// Tek serili küçük çizgi grafik: 2px çizgi ve altında hafif dolgu.
private struct Sparkline: View {
    let values: [Double]
    let maxValue: Double?

    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }
            let top = max(maxValue ?? (values.max() ?? 0), 1)
            let step = size.width / CGFloat(SystemStats.historyLength - 1)
            // En yeni örnek sağda; geçmiş dolana kadar grafik sağdan büyür.
            let startX = size.width - step * CGFloat(values.count - 1)
            let points = values.enumerated().map { index, value in
                CGPoint(
                    x: startX + CGFloat(index) * step,
                    y: size.height - 1 - CGFloat(min(value, top) / top) * (size.height - 2)
                )
            }
            var line = Path()
            line.addLines(points)
            var area = line
            area.addLine(to: CGPoint(x: points.last!.x, y: size.height))
            area.addLine(to: CGPoint(x: points.first!.x, y: size.height))
            area.closeSubpath()
            context.fill(area, with: .color(.white.opacity(0.12)))
            context.stroke(line, with: .color(.white.opacity(0.85)),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }
}

private struct DiskTile: View {
    let free: Double
    let total: Double

    private var usedFraction: Double { total > 0 ? 1 - free / total : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text("Disk")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                if usedFraction > 0.9 {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                }
            }
            Text(String(format: "%.0f GB", free / 1_000_000_000))
                .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
                .lineLimit(1)
            Spacer(minLength: 0)
            // Doluluk çubuğu: kullanılan kısım, boş kısımdan 2px aralıkla ayrılır.
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.85))
                        .frame(width: max(0, (proxy.size.width - 2) * usedFraction))
                    RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.15))
                }
            }
            .frame(height: 6)
            Text(usedFraction > 0.9 ? "Disk dolmak üzere" : String(format: "boş / %.0f GB", total / 1_000_000_000))
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
        .help(String(format: "Disk: %.0f GB boş, toplam %.0f GB", free / 1_000_000_000, total / 1_000_000_000))
    }
}
