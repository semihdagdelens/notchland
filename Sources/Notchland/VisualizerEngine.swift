import AppKit

/// Ses dalgasının kaynağını seçer, en ucuzdan pahalıya:
/// 1. Klasördeki kayıt (dinleme de internet de yok),
/// 2. Kaydın eksik kısmıysa sistem sesini dinleyip kaydetme,
/// 3. Hiçbiri yoksa (dinleme kapalı, izin yok) yapay dalga (`levels` nil döner).
final class VisualizerEngine {
    /// Dinleyici ilk açıldığında bu kadar kare boyunca hiç ses gelmezse izin yok sayılır.
    private static let permissionProbeFrames = Int(RhythmRecording.frameRate * 8)

    private var tap: AnyObject?
    private var recording: RhythmRecording?
    private var track: MediaController.Track?
    private var trackKey: String?
    private var timer: Timer?
    private var lastSave = Date.now

    /// Dinleyici kurulamadıysa ya da izin verilmediyse bu oturumda bir daha denenmez.
    private var listeningUnavailable = false
    private var heardSound = false
    private var silentFrames = 0
    /// İlk sesten önceki sessiz kareler; izin yokken sessizlik kaydedilmesin diye bekletilir.
    private var pendingSilence: [TimeInterval] = []
    /// Dinleyici karesinin sıra numarasını çalma konumuna bağlayan çapa. Kareler parça parça geldiği için
    /// saat yerine bu eksen kullanılır; aksi halde aynı konuma iki kare düşer, arada delik kalır.
    private var anchor: (index: Int, elapsed: TimeInterval)?

    private var listeningEnabled: Bool {
        guard #available(macOS 14.2, *) else { return false }
        return AppSettings.shared.listenSystemAudio && !listeningUnavailable
    }

    init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.recording?.save() }
    }

    func update(_ track: MediaController.Track?) {
        let key = track.map { "\($0.title)|\($0.artist)" }
        if key != trackKey {
            trackKey = key
            stopListening()
            recording?.save()
            recording = track.flatMap { RhythmRecording(title: $0.title, artist: $0.artist, duration: $0.duration) }
        }
        self.track = track

        if track?.isPlaying == true {
            if timer == nil {
                timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
            }
        } else {
            timer?.invalidate()
            timer = nil
            recording?.save()
        }
        evaluate()
    }

    /// Çubuk yükseklikleri; nil ise yapay dalga gösterilir.
    func levels(for track: MediaController.Track, at date: Date) -> [Double]? {
        recording?.levels(at: track.elapsed(at: date))
    }

    // MARK: - Dinleyici

    private func tick() {
        evaluate()
        if let recording, recording.isDirty, lastSave.timeIntervalSinceNow < -15 {
            recording.save()
            lastSave = .now
        }
    }

    /// Yalnızca çalarken ve önümüzdeki 2 saniyede kaydı olmayan kare varken dinler.
    private func evaluate() {
        guard let track, let recording, track.isPlaying, listeningEnabled,
              recording.hasGap(from: track.elapsed(at: .now), length: 2)
        else { return stopListening() }
        startListening(bundleID: track.bundleID)
    }

    private func startListening(bundleID: String?) {
        guard #available(macOS 14.2, *), tap == nil else { return }
        let tap = SystemAudioTap()
        heardSound = false
        silentFrames = 0
        pendingSilence = []
        anchor = nil
        guard tap.start(bundleID: bundleID, onFrame: { [weak self] in self?.receive($0, index: $1) }) else {
            NSLog("[Notchland] Sistem sesi dinleyicisi kurulamadı; yapay dalgaya dönülüyor.")
            return giveUpListening()
        }
        self.tap = tap
    }

    private func stopListening() {
        guard #available(macOS 14.2, *), let tap = tap as? SystemAudioTap else { return }
        tap.stop()
        self.tap = nil
    }

    private func receive(_ decibels: [Float], index: Int) {
        guard tap != nil, let track, track.isPlaying, let recording else {
            anchor = nil
            return
        }
        let now = track.elapsed(at: .now)
        var elapsed = anchor.map { $0.elapsed + Double(index - $0.index) / RhythmRecording.frameRate } ?? now
        // İlk karede ya da ileri/geri sarınca yeniden çapala.
        if abs(elapsed - now) > 0.3 {
            anchor = (index, now)
            elapsed = now
        } else if anchor == nil {
            anchor = (index, now)
        }
        if RhythmRecording.isSilent(decibels) && !heardSound {
            silentFrames += 1
            pendingSilence.append(elapsed)
            if silentFrames > Self.permissionProbeFrames {
                NSLog("[Notchland] Sistem sesinden hiç ses gelmiyor (izin verilmemiş olabilir); yapay dalgaya dönülüyor.")
                giveUpListening()
            }
            return
        }
        if !heardSound {
            heardSound = true
            pendingSilence.forEach { recording.record([Float](repeating: -100, count: decibels.count), at: $0) }
            pendingSilence = []
        }
        recording.record(decibels, at: elapsed)
    }

    private func giveUpListening() {
        stopListening()
        listeningUnavailable = true
    }
}
