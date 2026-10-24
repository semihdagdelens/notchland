import Accelerate
import AVFoundation
import CoreAudio

/// Çalan uygulamanın sesine Core Audio "process tap" ile bağlanır ve saniyede 30 kez bant başına enerji (dB) üretir.
/// Ses kaydedilmez, yalnızca beş sayı çıkar; dinleyici sadece kaydı olmayan şarkı kısımlarında açılır.
@available(macOS 14.2, *)
final class SystemAudioTap {
    static let frameRate = RhythmRecording.frameRate
    /// Bant sınırları (Hz): bas, alt orta, orta, üst orta, tiz.
    static let bandEdges: [Double] = [30, 150, 400, 1_200, 4_000, 14_000]

    private(set) var isRunning = false
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "UstBar.SystemAudioTap", qos: .userInitiated)

    /// `onFrame` ana iş parçacığında, bant başına dBFS ve karenin sıra numarasıyla çağrılır.
    /// Kareler sesin kendi zamanında tam 1/30 sn arayla üretilir; sıra numarası zaman ekseni olarak kullanılabilir.
    /// Kurulamazsa false döner.
    func start(bundleID: String?, onFrame: @escaping ([Float], Int) -> Void) -> Bool {
        guard !isRunning else { return true }
        let processes = Self.processObjects(matching: bundleID)
        // Çalan uygulamanın ses süreci bulunamazsa (ör. Firefox) bütün sistem sesine düş.
        let description = processes.isEmpty
            ? CATapDescription(stereoGlobalTapButExcludeProcesses: [])
            : CATapDescription(stereoMixdownOfProcesses: processes)
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = .unmuted

        guard AudioHardwareCreateProcessTap(description, &tapID) == noErr else { return fail() }

        var aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "UstBar Ritim",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: description.uuid.uuidString],
            ],
        ]
        if let outputUID = Self.defaultOutputUID() {
            aggregate[kAudioAggregateDeviceMainSubDeviceKey] = outputUID
            aggregate[kAudioAggregateDeviceSubDeviceListKey] = [[kAudioSubDeviceUIDKey: outputUID]]
        }
        guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID) == noErr,
              var streamDescription = Self.read(tapID, kAudioTapPropertyFormat, AudioStreamBasicDescription())
        else { return fail() }
        // Tap biçimi 48 kHz dese de ses toplu cihazın hızında (çoğu zaman 44,1 kHz) akar;
        // yanlış hızla kareler %8 yavaş üretilir ve konum kayar.
        if let rate = Self.read(aggregateID, kAudioDevicePropertyNominalSampleRate, Float64(0)), rate > 0 {
            streamDescription.mSampleRate = rate
        }
        guard let format = AVAudioFormat(streamDescription: &streamDescription) else { return fail() }

        let analyzer = BandAnalyzer(sampleRate: format.sampleRate) { bands, index in
            DispatchQueue.main.async { onFrame(bands, index) }
        }
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { _, input, _, _, _ in
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: input, deallocator: nil) else { return }
            analyzer.consume(buffer)
        }
        guard status == noErr, let procID, AudioDeviceStart(aggregateID, procID) == noErr else { return fail() }
        isRunning = true
        return true
    }

    func stop() {
        if let procID {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        procID = nil
        if aggregateID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregateID) }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
        isRunning = false
    }

    private func fail() -> Bool {
        stop()
        return false
    }

    // MARK: - Core Audio yardımcıları

    /// Çalan uygulamanın ses süreçleri. Safari sesi WebKit'in GPU sürecinden, Chrome'unki yardımcılardan çıkar.
    private static func processObjects(matching bundleID: String?) -> [AudioObjectID] {
        guard let bundleID else { return [] }
        let prefix = bundleID == "com.apple.Safari" ? "com.apple.WebKit" : bundleID
        return readArray(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList)
            .filter { readString($0, kAudioProcessPropertyBundleID)?.hasPrefix(prefix) == true }
    }

    private static func defaultOutputUID() -> String? {
        guard let device = read(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice,
                                AudioObjectID(kAudioObjectUnknown))
        else { return nil }
        return readString(device, kAudioDevicePropertyDeviceUID)
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ initial: T) -> T? {
        var address = address(selector)
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func readString(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0)
        }
        guard status == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    private static func readArray(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var address = address(selector)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }
}

/// Gelen sesi tek kanala indirir ve her 1/30 sn'de 2048 noktalı FFT ile bant enerjilerini hesaplar.
/// Yalnızca dinleyicinin kuyruğunda kullanılır.
@available(macOS 14.2, *)
private final class BandAnalyzer {
    private static let size = 2048

    private let fft: vDSP.FFT<DSPSplitComplex>
    private let window: [Float]
    private let hop: Int
    private let bins: [Range<Int>]
    private let onFrame: ([Float], Int) -> Void
    /// Tam ölçekli sinüsün 0 dB çıkması için güç ölçeği (vDSP'nin 2× ölçeği ve Hann kazancı dahil).
    private let powerScale: Float
    private var pending: [Float] = []
    private var produced = 0
    private var real = [Float](repeating: 0, count: size / 2)
    private var imag = [Float](repeating: 0, count: size / 2)
    private var power = [Float](repeating: 0, count: size / 2)

    init(sampleRate: Double, onFrame: @escaping ([Float], Int) -> Void) {
        let n = Self.size, half = n / 2
        fft = vDSP.FFT(log2n: vDSP_Length(log2(Double(n))), radix: .radix2, ofType: DSPSplitComplex.self)!
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: n, isHalfWindow: false)
        hop = Int(sampleRate / SystemAudioTap.frameRate)
        let edges = SystemAudioTap.bandEdges
        bins = zip(edges, edges.dropFirst()).map { low, high in
            let lo = max(1, Int(low * Double(n) / sampleRate))
            return lo..<max(lo + 1, min(half, Int(high * Double(n) / sampleRate)))
        }
        self.onFrame = onFrame
        powerScale = 1 / (Float(n) * Float(n) / 4)
    }

    func consume(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength), channelCount = Int(buffer.format.channelCount), stride = buffer.stride
        guard channelCount > 0 else { return }
        let scale = 1 / Float(channelCount)
        pending.reserveCapacity(pending.count + frames)
        for i in 0..<frames {
            var sum: Float = 0
            for c in 0..<channelCount {
                // Serpiştirilmiş biçimde tüm kanallar ilk göstericidedir.
                sum += buffer.format.isInterleaved ? channels[0][i * stride + c] : channels[c][i * stride]
            }
            pending.append(sum * scale)
        }
        while pending.count >= Self.size {
            analyzeFrame()
            pending.removeFirst(hop)
        }
    }

    private func analyzeFrame() {
        let half = Self.size / 2
        let windowed = vDSP.multiply(pending[0..<Self.size], window)
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                windowed.withUnsafeBufferPointer { wp in
                    wp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                    }
                }
                fft.forward(input: split, output: &split)
                vDSP.squareMagnitudes(split, result: &power)
            }
        }
        onFrame(bins.map { 10 * log10(vDSP.sum(power[$0]) * powerScale + 1e-12) }, produced)
        produced += 1
    }
}
