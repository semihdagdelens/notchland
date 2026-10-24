import SwiftUI

/// Kapalı notch'un iki yana genişleyerek gösterdiği kısa süreli bildirim.
enum HUD: Equatable {
    case volume(level: Float, isMuted: Bool, isHeadphones: Bool)
    case brightness(level: Float)
    case battery(BatteryMonitor.Status)
    case event(CalendarService.Event)
    case headphones(HeadphoneMonitor.Device)
    case notification(NotificationMirror.Notice)

    /// Ses, parlaklık ve pil notch'u genişletmez; yandan ayrılan baloncukta gösterilir (HUDBubble).
    var usesBubble: Bool {
        switch self {
        case .event, .headphones, .notification: false
        default: true
        }
    }

    /// Notch'un her iki yanına eklenen genişlik.
    var earWidth: CGFloat {
        switch self {
        case .event, .notification: 150
        case .headphones: 130
        default: 0
        }
    }

    /// Notch'un altına eklenen yükseklik (bildirim metni için).
    var extraHeight: CGFloat {
        if case .notification = self { return 46 }
        return 0
    }

    var duration: TimeInterval {
        switch self {
        case .battery: 3
        case .headphones: 4
        case .notification: 5
        case .event: 6
        default: 1.6
        }
    }
}

struct HUDContent: View {
    let hud: HUD
    let notchWidth: CGFloat
    let notchHeight: CGFloat

    var body: some View {
        if !hud.usesBubble {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    leading
                        .frame(width: hud.earWidth)
                    Color.clear.frame(width: notchWidth)
                    trailing
                        .frame(width: hud.earWidth)
                }
                .frame(height: notchHeight)
                if case let .notification(notice) = hud {
                    NotificationBody(notice: notice)
                        .frame(height: hud.extraHeight)
                }
            }
            .foregroundStyle(.white)
        }
    }

    @ViewBuilder private var leading: some View {
        switch hud {
        case let .volume(level, isMuted, isHeadphones):
            Image(systemName: Self.volumeSymbol(level: level, isMuted: isMuted, isHeadphones: isHeadphones))
                .font(.system(size: 14, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
        case let .brightness(level):
            Image(systemName: level < 0.5 ? "sun.min.fill" : "sun.max.fill")
                .font(.system(size: 14, weight: .semibold))
        case let .battery(status):
            Image(systemName: status.isPluggedIn ? "bolt.fill" : "battery.25percent")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(status.isPluggedIn ? .green : .red)
        case let .event(event):
            HStack(spacing: 6) {
                Circle().fill(Color(nsColor: event.color)).frame(width: 7, height: 7)
                Text(event.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.leading, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        case let .headphones(device):
            HStack(spacing: 6) {
                Image(systemName: device.symbol)
                    .font(.system(size: 14, weight: .semibold))
                Text(device.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.leading, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        case let .notification(notice):
            HStack(spacing: 6) {
                NotificationIcon(notice: notice)
                    .frame(width: 18, height: 18)
                Text(notice.appName ?? "Bildirim")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.leading, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var trailing: some View {
        switch hud {
        case let .volume(level, isMuted, _):
            LevelBar(level: isMuted ? 0 : level)
        case let .brightness(level):
            LevelBar(level: level)
        case let .battery(status):
            Text("%\(status.level)")
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(status.isPluggedIn ? .green : .red)
        case let .event(event):
            let minutes = max(1, Int((event.start.timeIntervalSinceNow / 60).rounded(.up)))
            Text("\(minutes) dk sonra")
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.trailing, 14)
                .frame(maxWidth: .infinity, alignment: .trailing)
        case let .headphones(device):
            HeadphoneLevels(device: device)
                .padding(.trailing, 14)
                .frame(maxWidth: .infinity, alignment: .trailing)
        case .notification:
            Text("şimdi")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.trailing, 16)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    static func volumeSymbol(level: Float, isMuted: Bool, isHeadphones: Bool) -> String {
        if isHeadphones { return isMuted ? "headphones.slash" : "headphones" }
        if isMuted || level == 0 { return "speaker.slash.fill" }
        if level < 0.33 { return "speaker.wave.1.fill" }
        if level < 0.66 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}

/// Kulaklık ve (varsa) kutu pil seviyeleri; bilinmiyorsa "Bağlandı".
private struct HeadphoneLevels: View {
    let device: HeadphoneMonitor.Device

    var body: some View {
        HStack(spacing: 10) {
            if let buds = device.budsLevel {
                level(buds, symbol: device.left != nil || device.right != nil ? device.symbol : "battery.100percent")
            }
            if let caseLevel = device.caseLevel {
                level(caseLevel, symbol: device.caseSymbol)
            }
            if !device.hasBattery {
                Text("Bağlandı")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func level(_ percent: Int, symbol: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("%\(percent)")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(percent <= 20 ? Color.red : .white)
        }
    }
}

/// Bildirimin geldiği uygulamanın ikonu; bulunamazsa zil.
private struct NotificationIcon: View {
    let notice: NotificationMirror.Notice

    var body: some View {
        if let icon = SourceAppIcon.icon(for: notice.bundleID) {
            Image(nsImage: icon).resizable()
        } else {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 12, weight: .semibold))
                .symbolRenderingMode(.multicolor)
        }
    }
}

/// Bildirimin başlığı ve metni; notch'un altına uzanan kısım.
private struct NotificationBody: View {
    let notice: NotificationMirror.Notice

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(notice.title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            if !notice.body.isEmpty {
                Text(notice.body)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 18)
        .padding(.top, 2)
    }
}

private struct LevelBar: View {
    let level: Float

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.25))
                Capsule().fill(Color.white)
                    .frame(width: proxy.size.width * CGFloat(min(max(level, 0), 1)))
            }
        }
        .frame(width: 44, height: 5)
        .animation(.easeOut(duration: 0.12), value: level)
    }
}

/// Açık notch'ta sağ üst köşedeki pil göstergesi.
struct BatteryBadge: View {
    let battery: BatteryMonitor

    var body: some View {
        if let status = battery.status {
            HStack(spacing: 5) {
                Text("%\(status.level)")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                Image(systemName: Self.symbol(for: status))
                    .font(.system(size: 14))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Self.color(for: status, lowPower: battery.isLowPowerMode), .white.opacity(0.5))
            }
            .help(Self.tooltip(for: status))
        }
    }

    private static func symbol(for status: BatteryMonitor.Status) -> String {
        if status.isCharging || status.isPluggedIn { return "battery.100percent.bolt" }
        switch status.level {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    private static func color(for status: BatteryMonitor.Status, lowPower: Bool) -> Color {
        if status.isPluggedIn { return .green }
        if lowPower { return .yellow }
        return status.level <= BatteryMonitor.lowBatteryThreshold ? .red : .white
    }

    private static func tooltip(for status: BatteryMonitor.Status) -> String {
        if status.isCharging { return "Şarj oluyor" }
        if status.isPluggedIn { return "Güç adaptörüne bağlı" }
        guard let minutes = status.minutesRemaining else { return "Pil" }
        return "Kalan süre: \(minutes / 60) sa \(minutes % 60) dk"
    }
}
