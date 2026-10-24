import AppKit

/// Sistem genelindeki "Şu An Çalıyor" bilgisini okur (Spotify, Music, Safari/Chrome'daki YouTube vb.).
/// macOS 15.4+ MediaRemote'u üçüncü parti uygulamalara kapattığı için, Apple imzalı
/// /usr/bin/perl üzerinden MediaRemoteAdapter (BSD-3, ungive/mediaremote-adapter) kullanılır.
@Observable
final class MediaController {
    struct Track: Equatable {
        var title: String
        var artist: String
        var album: String
        var isPlaying: Bool
        var bundleID: String?
        var duration: TimeInterval
        var elapsed: TimeInterval
        var timestamp: Date
        var playbackRate: Double
        var artwork: NSImage?

        /// Son güncellemeden bu yana geçen süreyle tahmini oynatma konumu.
        func elapsed(at date: Date) -> TimeInterval {
            guard isPlaying else { return elapsed }
            let value = elapsed + date.timeIntervalSince(timestamp) * playbackRate
            return duration > 0 ? min(value, duration) : value
        }

        static func == (lhs: Track, rhs: Track) -> Bool {
            lhs.title == rhs.title && lhs.artist == rhs.artist && lhs.isPlaying == rhs.isPlaying
                && lhs.bundleID == rhs.bundleID && lhs.elapsed == rhs.elapsed && lhs.artwork === rhs.artwork
        }
    }

    /// MRCommand kimlikleri.
    private enum Command: Int {
        case togglePlayPause = 2
        case nextTrack = 4
        case previousTrack = 5
    }

    private(set) var track: Track? {
        didSet {
            if track?.title != oldValue?.title || track?.artist != oldValue?.artist {
                onTrackChange?(track)
            }
        }
    }

    /// Parça (başlık/sanatçı) değişince çağrılır.
    @ObservationIgnored var onTrackChange: ((Track?) -> Void)?

    /// Kapaktan çıkarılan baskın renk (notch arka planı için); kapak yoksa nil.
    private(set) var artworkColor: NSColor?

    private var process: Process?
    private var stdinPipe: Pipe?
    private var lineBuffer = Data()
    private var lastArtworkData: String?
    private var restartDelay: TimeInterval = 1

    private static var adapterPaths: (script: String, framework: String)? {
        guard let resources = Bundle.main.resourceURL?.appendingPathComponent("MediaRemote") else { return nil }
        let script = resources.appendingPathComponent("mediaremote-adapter.pl").path
        let framework = resources.appendingPathComponent("MediaRemoteAdapter.framework").path
        guard FileManager.default.fileExists(atPath: script), FileManager.default.fileExists(atPath: framework) else {
            return nil
        }
        return (script, framework)
    }

    func start() {
        guard process == nil, let paths = Self.adapterPaths else {
            if Self.adapterPaths == nil { NSLog("[UstBar] MediaRemoteAdapter bulunamadı; medya bilgisi kapalı.") }
            return
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        task.arguments = [paths.script, paths.framework, "stream", "--no-diff", "--debounce=100", "--micros"]
        var env = ProcessInfo.processInfo.environment
        env["PERLIO"] = ":unix"
        // Betik stdin'i bekçi olarak dinler: biz kapanınca (crash dahil) o da kapanır.
        env["SAPPHIRE_WATCH_PARENT_STDIN"] = "1"
        task.environment = env

        let stdin = Pipe()
        let stdout = Pipe()
        task.standardInput = stdin
        task.standardOutput = stdout
        task.standardError = FileHandle.nullDevice

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            DispatchQueue.main.async { self?.consume(data) }
        }
        task.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.streamDidExit() }
        }

        do {
            try task.run()
            process = task
            stdinPipe = stdin
        } catch {
            NSLog("[UstBar] Medya akışı başlatılamadı: \(error.localizedDescription)")
        }
    }

    func playPause() { send(.togglePlayPause) }
    func next() { send(.nextTrack) }
    func previous() { send(.previousTrack) }

    func seek(to seconds: TimeInterval) {
        run(["seek", String(Int(max(0, seconds) * 1_000_000))])
        // Akış güncellemesi gelene kadar arayüz eski konumda kalmasın.
        if var current = track {
            current.elapsed = seconds
            current.timestamp = .now
            track = current
        }
    }

    private func send(_ command: Command) {
        run(["send", String(command.rawValue)])
    }

    private func run(_ arguments: [String]) {
        guard let paths = Self.adapterPaths else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        task.arguments = [paths.script, paths.framework] + arguments
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
    }

    private func streamDidExit() {
        process = nil
        try? stdinPipe?.fileHandleForWriting.close()
        stdinPipe = nil
        lineBuffer.removeAll()
        // Akış ölürse giderek artan aralıklarla yeniden dene.
        DispatchQueue.main.asyncAfter(deadline: .now() + restartDelay) { [weak self] in self?.start() }
        restartDelay = min(restartDelay * 2, 30)
    }

    // MARK: - Ayrıştırma

    private func consume(_ data: Data) {
        lineBuffer.append(data)
        while let newline = lineBuffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = lineBuffer[lineBuffer.startIndex..<newline]
            lineBuffer.removeSubrange(lineBuffer.startIndex...newline)
            handle(line: Data(line))
        }
    }

    private func handle(line: Data) {
        guard let event = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              event["type"] as? String == "data",
              let payload = event["payload"] as? [String: Any]
        else { return }
        restartDelay = 1

        guard let title = payload["title"] as? String, !title.isEmpty else {
            track = nil
            lastArtworkData = nil
            artworkColor = nil
            return
        }

        var artwork = track?.artwork
        let artworkData = payload["artworkData"] as? String
        if artworkData != lastArtworkData {
            lastArtworkData = artworkData
            artwork = artworkData.flatMap { Data(base64Encoded: $0) }.flatMap(NSImage.init(data:))
            // Renk sadece kapak değişince, arka planda bir kez hesaplanır.
            if let artwork {
                ArtworkPalette.dominantColor(of: artwork) { [weak self] color in
                    guard let self, self.lastArtworkData == artworkData else { return }
                    self.artworkColor = color
                }
            } else {
                artworkColor = nil
            }
        }

        let micros: (String) -> Double = { (payload[$0] as? NSNumber)?.doubleValue ?? 0 }
        let timestampMicros = micros("timestampEpochMicros")
        let newTrack = Track(
            title: title,
            artist: payload["artist"] as? String ?? "",
            album: payload["album"] as? String ?? "",
            isPlaying: payload["playing"] as? Bool ?? false,
            bundleID: payload["bundleIdentifier"] as? String,
            duration: micros("durationMicros") / 1_000_000,
            elapsed: micros("elapsedTimeMicros") / 1_000_000,
            timestamp: timestampMicros > 0 ? Date(timeIntervalSince1970: timestampMicros / 1_000_000) : .now,
            playbackRate: (payload["playbackRate"] as? NSNumber)?.doubleValue ?? 1,
            artwork: artwork
        )
        if newTrack != track { track = newTrack }
    }
}
