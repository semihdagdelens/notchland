import SwiftUI

/// Ajanlar sekmesi: her oturum kendi 3B robotuyla, önce dikkat isteyenler. Tıklamak oturumun uygulamasına götürür.
struct AgentsView: View {
    let state: NotchState
    let agents: AgentMonitor

    var body: some View {
        if agents.sessions.isEmpty && agents.cursor == nil {
            Text("Çalışan ajan oturumu yok")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(Array(agents.sessions.enumerated()), id: \.element.id) { index, session in
                                SessionCard(session: session) { agents.focus(session) }
                                    .keyStop(state, .agents, "session\(session.id)", order: index, outset: 0) {
                                        agents.focus(session)
                                    }
                            }
                            if let cursor = agents.cursor {
                                RobotCard(
                                    title: "Cursor", subtitle: "Durum okunamıyor", help: "Uygulama açık · oturum durumu okunamıyor",
                                    mood: .unknown, tint: NSColor(red: 0.55, green: 0.5, blue: 0.95, alpha: 1)
                                ) { cursor.activate() }
                                    .keyStop(state, .agents, "cursor", order: agents.sessions.count, outset: 0) {
                                        cursor.activate()
                                    }
                            }
                        }
                        /// Az oturum varken kartlar ortada durur, çoksa yana kayar.
                        .frame(minWidth: geometry.size.width, maxHeight: .infinity)
                    }
                    .scrollIndicators(.never)
                    .scrollsToKeyFocus(state, proxy)
                }
            }
        }
    }
}

private struct SessionCard: View {
    let session: AgentMonitor.Session
    let action: () -> Void

    /// Robotlar birbirinden ayırt edilsin diye gövde rengi pid'den seçilir; yenilemede değişmez.
    private static let tints: [NSColor] = [
        NSColor(red: 0.2, green: 0.75, blue: 0.85, alpha: 1),
        NSColor(red: 0.95, green: 0.45, blue: 0.55, alpha: 1),
        NSColor(red: 0.35, green: 0.55, blue: 1, alpha: 1),
        NSColor(red: 0.95, green: 0.8, blue: 0.3, alpha: 1),
        NSColor(red: 0.6, green: 0.85, blue: 0.4, alpha: 1),
        NSColor(red: 0.85, green: 0.55, blue: 0.95, alpha: 1),
    ]

    private var mood: RobotMood {
        switch session.status {
        case .waiting: .waiting
        case .working: .working
        case .idle: .idle
        }
    }

    private var statusText: String {
        switch session.status {
        case .waiting: "Seni bekliyor"
        case .working: "Çalışıyor"
        case .idle: "Uyuyor"
        }
    }

    private var help: String {
        var parts = ["Claude Code", session.host?.localizedName].compactMap { $0 }
        if case let .waiting(detail?) = session.status { parts.append(detail) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            RobotCard(
                title: session.name,
                subtitle: session.status == .idle
                    ? statusText
                    : "\(statusText) · \(Self.elapsed(from: session.statusSince, to: context.date))",
                help: help,
                mood: mood,
                tint: Self.tints[Int(session.id.magnitude) % Self.tints.count],
                action: action
            )
        }
    }

    private static func elapsed(from start: Date, to now: Date) -> String {
        let minutes = Int(now.timeIntervalSince(start) / 60)
        if minutes < 1 { return "şimdi" }
        return minutes < 60 ? "\(minutes) dk" : "\(minutes / 60) sa \(minutes % 60) dk"
    }
}

private struct RobotCard: View {
    let title: String
    let subtitle: String
    let help: String
    let mood: RobotMood
    let tint: NSColor
    let action: () -> Void
    @State private var spinCount = 0

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                AgentRobotView(mood: mood, tint: tint, spinCount: spinCount)
                    .frame(maxWidth: .infinity, minHeight: 30, maxHeight: .infinity)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(mood == .waiting ? Color(nsColor: mood.glow) : .secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .frame(width: 124)
            .frame(maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(colors: [.white.opacity(0.09), .white.opacity(0.03)], startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color(nsColor: mood.glow).opacity(mood == .waiting ? 0.55 : 0.12), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { if $0 { spinCount += 1 } }
    }
}
