import AVFoundation
import Speech
import SwiftUI

/// Mikrofonu dinleyip Türkçe konuşmayı canlı olarak yazıya döker (SFSpeechRecognizer).
/// Destekleniyorsa tanıma cihaz üzerinde yapılır; ses dışarı gönderilmez.
@Observable
final class DictationService {
    enum Phase: Equatable {
        case idle
        case preparing
        case listening
        case finishing
        case done(pasted: Bool)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    /// Kesinleşmiş cümleler.
    private(set) var committed = ""
    /// Hâlâ söylenmekte olan, tanıyıcının değiştirebileceği kısım.
    private(set) var partial = ""
    /// 0…1 mikrofon seviyesi (düğme animasyonu için).
    private(set) var level: Float = 0

    var isActive: Bool { phase != .idle }
    var text: String { Self.join(committed, partial) }

    /// Metin hazır olunca çağrılır; öndeki uygulamaya yapıştırıldıysa true dönmeli.
    @ObservationIgnored var onFinish: ((String) -> Bool)?
    /// Dikte paneli kapandığında çağrılır.
    @ObservationIgnored var onClose: (() -> Void)?

    @ObservationIgnored private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "tr-TR"))
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var taskStart = Date()
    /// Ses iş parçacığından da okunduğu için kilitle korunur.
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private let requestLock = NSLock()
    /// Başlar başlamaz hata veren tanıma oturumlarının sayısı (sonsuz döngüye girmemek için).
    @ObservationIgnored private var quickFailures = 0
    /// İzin istekleri sürerken iptal edilip yeniden başlatılırsa eski yanıtı yok saymak için.
    @ObservationIgnored private var session = 0
    @ObservationIgnored private var finishTimeout: DispatchWorkItem?
    @ObservationIgnored private var closeWork: DispatchWorkItem?

    func start() {
        closeWork?.cancel()
        teardown()
        committed = ""
        partial = ""
        quickFailures = 0
        phase = .preparing
        session += 1
        let current = session
        Self.requestPermissions { [weak self] error in
            guard let self, self.session == current, self.phase == .preparing else { return }
            if let error {
                self.fail(error)
            } else {
                self.beginListening()
            }
        }
    }

    /// Dinlemeyi bitirir; son sonuç gelince `onFinish` çağrılır.
    func stop() {
        guard phase == .listening else { return }
        phase = .finishing
        stopAudio()
        currentRequest?.endAudio()
        // Tanıyıcı son sonucu geciktirirse eldekiyle devam et.
        let timeout = DispatchWorkItem { [weak self] in self?.complete() }
        finishTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: timeout)
    }

    /// Metni kullanmadan kapatır.
    func cancel() {
        session += 1
        teardown()
        close()
    }

    // MARK: - Dinleme

    private func beginListening() {
        guard let recognizer, recognizer.isAvailable else {
            fail("Türkçe konuşma tanıma şu an kullanılamıyor. Sistem Ayarları › Klavye › Dikte açık mı?")
            return
        }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            fail("Mikrofon bulunamadı.")
            return
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.currentRequest?.append(buffer)
            let level = Self.level(of: buffer)
            DispatchQueue.main.async {
                // Hızlı yükselip yavaş sönsün.
                self.level = max(level, self.level * 0.8)
            }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            fail("Mikrofon açılamadı: \(error.localizedDescription)")
            return
        }
        self.engine = engine
        startRecognition()
        phase = .listening
    }

    /// Yeni bir tanıma oturumu açar. Sunucu tabanlı tanıma ~1 dakikada ve uzun sessizlikte
    /// kendiliğinden biter; o zaman metin kesinleştirilip yeni oturumla devam edilir.
    private func startRecognition() {
        guard let recognizer else { return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        currentRequest = request
        taskStart = Date()
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async { self?.handle(result: result, error: error, from: request) }
        }
    }

    private func handle(result: SFSpeechRecognitionResult?, error: Error?, from request: SFSpeechAudioBufferRecognitionRequest) {
        guard request === currentRequest else { return }
        if let result {
            partial = result.bestTranscription.formattedString
        }
        guard result?.isFinal == true || error != nil else { return }

        committed = text
        partial = ""
        switch phase {
        case .listening:
            if error != nil, result == nil, Date().timeIntervalSince(taskStart) < 1 {
                quickFailures += 1
            } else {
                quickFailures = 0
            }
            if quickFailures >= 3 {
                fail("Konuşma tanıma durdu: \(error?.localizedDescription ?? "bilinmeyen hata")")
                return
            }
            startRecognition()
        case .finishing:
            complete()
        default:
            break
        }
    }

    private func complete() {
        guard phase == .finishing else { return }
        let text = self.text.trimmingCharacters(in: .whitespacesAndNewlines)
        teardown()
        guard !text.isEmpty else {
            close()
            return
        }
        let pasted = onFinish?(text) ?? false
        phase = .done(pasted: pasted)
        scheduleClose(after: 1.2)
    }

    private func fail(_ message: String) {
        teardown()
        phase = .failed(message)
        scheduleClose(after: 4)
    }

    private func scheduleClose(after delay: TimeInterval) {
        closeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.close() }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func close() {
        closeWork?.cancel()
        closeWork = nil
        guard phase != .idle else { return }
        withAnimation(.spring(response: 0.36, dampingFraction: 0.95)) {
            phase = .idle
            level = 0
        }
        onClose?()
    }

    private func teardown() {
        finishTimeout?.cancel()
        finishTimeout = nil
        stopAudio()
        currentRequest = nil
        task?.cancel()
        task = nil
    }

    private func stopAudio() {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        level = 0
    }

    private var currentRequest: SFSpeechAudioBufferRecognitionRequest? {
        get {
            requestLock.lock()
            defer { requestLock.unlock() }
            return request
        }
        set {
            requestLock.lock()
            request = newValue
            requestLock.unlock()
        }
    }

    // MARK: - Yardımcılar

    private static func requestPermissions(_ completion: @escaping (String?) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else {
                DispatchQueue.main.async {
                    completion("Konuşma tanıma izni yok. Sistem Ayarları › Gizlilik ve Güvenlik › Konuşma Tanıma.")
                }
                return
            }
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    completion(granted ? nil : "Mikrofon izni yok. Sistem Ayarları › Gizlilik ve Güvenlik › Mikrofon.")
                }
            }
        }
    }

    /// Tamponun RMS seviyesini −50…−10 dB aralığından 0…1'e çevirir.
    private static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<count { sum += samples[i] * samples[i] }
        let decibels = 20 * log10(max(sqrt(sum / Float(count)), 1e-6))
        return min(max((decibels + 50) / 40, 0), 1)
    }

    private static func join(_ first: String, _ second: String) -> String {
        if first.isEmpty { return second }
        if second.isEmpty { return first }
        return first + " " + second
    }
}
