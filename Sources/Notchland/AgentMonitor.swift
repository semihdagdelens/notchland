import AppKit
import Darwin

/// Bilgisayardaki AI ajanlarını izler. Claude Code her oturum için `~/.claude/sessions/<pid>.json`
/// yazar; belgelenmemiş bu biçim değişirse liste boş kalır, uygulama etkilenmez.
/// Cursor durum bırakmadığı için yalnızca açık olup olmadığı bilinir.
@Observable
final class AgentMonitor {
    enum Status: Equatable {
        case waiting(String?)
        case working
        case idle

        /// Dikkat isteyen oturumlar listenin başına gelir.
        fileprivate var rank: Int {
            switch self {
            case .waiting: 0
            case .working: 1
            case .idle: 2
            }
        }
    }

    struct Session: Identifiable, Equatable {
        /// Süreç kimliği; `/clear` gibi oturum değişikliklerinde de aynı kalır.
        let id: Int32
        let name: String
        let cwd: String?
        let isEditorExtension: Bool
        let status: Status
        let statusSince: Date
        /// Oturumu barındıran uygulama (Terminal, VS Code…).
        let host: NSRunningApplication?
    }

    private(set) var sessions: [Session] = []
    private(set) var cursor: NSRunningApplication?

    /// Uzun bir iş bitti veya bir oturum kullanıcıyı bekliyor.
    @ObservationIgnored var onNotice: ((NotificationMirror.Notice) -> Void)?

    /// Yalnızca sekme açıkken dosyalar okunur; kapalıyken hiç iş yapma (pil).
    var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            timer?.invalidate()
            timer = nil
            sessions = []
            cursor = nil
            hosts = [:]
            hasSampled = false
            guard isEnabled else { return }
            sample()
            let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.sample() }
            timer.tolerance = 0.5
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var hosts: [Int32: NSRunningApplication] = [:]
    /// İlk okumada değişiklik sayılmaz; yoksa açılışta eski durumlar bildirim olarak düşerdi.
    @ObservationIgnored private var hasSampled = false

    private static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/sessions", isDirectory: true)
    private static let cursorBundleID = "com.todesktop.230313mzl4w4u92"
    /// Kısa yanıtlar bildirim yağmuruna dönmesin diye yalnızca bundan uzun işlerin bitişi bildirilir.
    private static let minimumNotifiedWork: TimeInterval = 20

    /// Barındıran uygulamayı öne getirir. Eklentide klasörü açmak, doğru pencereye götürür.
    func focus(_ session: Session) {
        guard let host = session.host else { return }
        if session.isEditorExtension, let cwd = session.cwd, let appURL = host.bundleURL {
            NSWorkspace.shared.open(
                [URL(fileURLWithPath: cwd)], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration()
            )
        } else {
            host.activate()
        }
    }

    private func sample() {
        let previous = sessions
        let current = readSessions()
        if hasSampled { notifyChanges(from: previous, to: current) }
        hasSampled = true
        if current != sessions { sessions = current }

        let cursor = NSRunningApplication.runningApplications(withBundleIdentifier: Self.cursorBundleID).first
        if cursor != self.cursor { self.cursor = cursor }
    }

    private func notifyChanges(from previous: [Session], to current: [Session]) {
        for session in current {
            guard let old = previous.first(where: { $0.id == session.id }), old.status != session.status else { continue }
            switch (old.status, session.status) {
            case (_, .waiting):
                onNotice?(.init(appName: "Claude Code", title: session.name, body: "Seni bekliyor", bundleID: nil))
            case (.working, .idle) where session.statusSince.timeIntervalSince(old.statusSince) >= Self.minimumNotifiedWork:
                onNotice?(.init(appName: "Claude Code", title: session.name, body: "İşini bitirdi", bundleID: nil))
            default:
                break
            }
        }
    }

    /// Yalnızca `.json` durum dosyaları okunur: yanındaki `.key` dosyalarına ve konuşma kayıtlarına dokunulmaz.
    private func readSessions() -> [Session] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: Self.directory, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        let sessions = urls.filter { $0.pathExtension == "json" }.compactMap { url -> Session? in
            guard let data = try? Data(contentsOf: url),
                  let file = try? decoder.decode(SessionFile.self, from: data),
                  Self.isAlive(file) else { return nil }
            let startedAt = file.startedAt ?? 0
            return Session(
                id: file.pid,
                name: file.name ?? file.cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Claude Code",
                cwd: file.cwd,
                isEditorExtension: file.entrypoint == "claude-vscode",
                status: file.resolvedStatus,
                statusSince: Date(timeIntervalSince1970: (file.statusUpdatedAt ?? startedAt) / 1000),
                host: host(of: file.pid)
            )
        }
        hosts = hosts.filter { pid, _ in sessions.contains { $0.id == pid } }
        return sessions.sorted {
            if $0.status.rank != $1.status.rank { return $0.status.rank < $1.status.rank }
            return $0.statusSince > $1.statusSince
        }
    }

    /// Dosya, süreç ansızın kapanınca geride kalabilir ve aynı pid başka bir sürece verilmiş olabilir:
    /// oturumdan sonra başlamış bir süreç o oturumun sahibi değildir.
    private static func isAlive(_ file: SessionFile) -> Bool {
        guard let info = processInfo(file.pid) else { return false }
        guard let startedAt = file.startedAt else { return true }
        return Double(info.pbi_start_tvsec) <= startedAt / 1000 + 5
    }

    private static func processInfo(_ pid: Int32) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.stride)
        return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size ? info : nil
    }

    /// Üst süreçlere çıkarak Dock'ta görünen ilk uygulamayı bulur (yardımcı süreçler atlanır).
    private func host(of pid: Int32) -> NSRunningApplication? {
        if let cached = hosts[pid], !cached.isTerminated { return cached }
        var current = pid
        while current > 1, let info = Self.processInfo(current) {
            if let app = NSRunningApplication(processIdentifier: current), app.activationPolicy == .regular {
                hosts[pid] = app
                return app
            }
            current = Int32(info.pbi_ppid)
        }
        return nil
    }
}

/// Oturum dosyasının gereken alanları; ötekiler bilerek okunmaz.
private struct SessionFile: Decodable {
    let pid: Int32
    let cwd: String?
    let startedAt: Double?
    let entrypoint: String?
    let name: String?
    let status: String?
    let waitingFor: String?
    let statusUpdatedAt: Double?

    var resolvedStatus: AgentMonitor.Status {
        switch status {
        case "busy": .working
        case "waiting": .waiting(waitingFor)
        default: .idle
        }
    }
}
