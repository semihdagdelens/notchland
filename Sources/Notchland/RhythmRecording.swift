import SwiftUI

/// Bir şarkının dinlenerek çıkarılmış ritmi: çalma konumuna göre saniyede 30 kare, kare başına bant başına bir bayt.
/// `~/Library/Application Support/Notchland/Ritimler/Sanatçı - Şarkı.ritim` dosyasında durur;
/// dolu kareler bir daha dinlenmez.
final class RhythmRecording {
    static let frameRate = 30.0
    static let bandCount = barOrder.count
    /// Bu süreden uzun parçalar (canlı yayın, miks) kaydedilmez.
    static let maxDuration: TimeInterval = 20 * 60

    /// URT1 kayıtları yanlış ölçekliydi (tavana vuruyordu); okunmaz, yeniden dinlenir.
    private static let magic = Array("URT2".utf8)
    /// Bas ortada, tizler kenarlarda.
    private static let barOrder = [3, 1, 0, 2, 4]

    let url: URL
    let duration: TimeInterval
    /// `[kare * bandCount + bant]`; 0 = dinlenmedi, 1 = sessiz, gerisi (dBFS + 110) * 2 (−109…+17 dB).
    private var frames: [UInt8]
    /// Bant başına değer histogramı; dalgayı şarkının kendi ses aralığına göre ölçeklemek için.
    private var histograms: [[Int]]
    private var ranges: [(low: Double, high: Double)] = []
    private var recordsSinceRangeUpdate = 0
    private(set) var isDirty = false

    private var frameCount: Int { frames.count / Self.bandCount }

    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notchland/Ritimler", isDirectory: true)
    }

    /// Kaydedilebilecek bir parça değilse nil.
    init?(title: String, artist: String, duration: TimeInterval) {
        guard duration > 0, duration <= Self.maxDuration, !title.isEmpty else { return nil }
        let name = (artist.isEmpty ? title : "\(artist) - \(title)")
            .replacingOccurrences(of: "/", with: "∕")
            .replacingOccurrences(of: ":", with: "꞉")
        url = Self.folder.appendingPathComponent(String(name.prefix(180))).appendingPathExtension("ritim")
        self.duration = duration
        let count = Int((duration * Self.frameRate).rounded(.up)) * Self.bandCount
        frames = Self.load(url, duration: duration, count: count) ?? [UInt8](repeating: 0, count: count)
        histograms = [[Int]](repeating: [Int](repeating: 0, count: 256), count: Self.bandCount)
        for (index, value) in frames.enumerated() where value > 1 {
            histograms[index % Self.bandCount][Int(value)] += 1
        }
        updateRanges()
    }

    // MARK: - Okuma

    /// Verilen konumdaki çubuk yükseklikleri (0...1, çubuk sırasıyla); bu kısım dinlenmediyse nil.
    /// Dinlerken son kare birkaç on ms geriden geldiği için en fazla 4 kare geriye bakılır.
    func levels(at elapsed: TimeInterval) -> [Double]? {
        let position = elapsed * Self.frameRate
        let frame = Int(position)
        guard let known = (max(0, frame - 4)...frame).reversed().first(where: isKnown) else { return nil }
        let next = known + 1
        let t = known == frame && isKnown(next) ? position - Double(frame) : 0
        return Self.barOrder.map { band in
            let value = level(frame: known, band: band) * (1 - t) + (t > 0 ? level(frame: next, band: band) * t : 0)
            return 0.12 + 0.86 * value
        }
    }

    /// `elapsed`'ten başlayıp `length` saniye içinde dinlenmemiş kare var mı?
    func hasGap(from elapsed: TimeInterval, length: TimeInterval) -> Bool {
        let start = max(0, Int(elapsed * Self.frameRate))
        let end = min(frameCount, start + Int(length * Self.frameRate))
        return start < end && (start..<end).contains { !isKnown($0) }
    }

    private func isKnown(_ frame: Int) -> Bool {
        frame >= 0 && frame < frameCount && frames[frame * Self.bandCount] != 0
    }

    private func level(frame: Int, band: Int) -> Double {
        let value = Double(frames[frame * Self.bandCount + band])
        guard value > 1, band < ranges.count else { return 0 }
        let (low, high) = ranges[band]
        return high > low ? min(1, max(0, (value - low) / (high - low))) : 0.5
    }

    // MARK: - Yazma

    /// Dinleyiciden gelen kareyi yazar. Tamamen sessiz kareler `silent` olarak işaretlenir.
    func record(_ decibels: [Float], at elapsed: TimeInterval) {
        let frame = Int(elapsed * Self.frameRate)
        guard frame >= 0, frame < frameCount, decibels.count == Self.bandCount else { return }
        let silent = Self.isSilent(decibels)
        for band in 0..<Self.bandCount {
            let index = frame * Self.bandCount + band
            if frames[index] > 1 { histograms[band][Int(frames[index])] -= 1 }
            let value: UInt8 = silent ? 1 : UInt8(min(255, max(2, (Double(decibels[band]) + 110) * 2)))
            frames[index] = value
            if value > 1 { histograms[band][Int(value)] += 1 }
        }
        isDirty = true
        recordsSinceRangeUpdate += 1
        if recordsSinceRangeUpdate >= 30 || ranges.isEmpty { updateRanges() }
    }

    static func isSilent(_ decibels: [Float]) -> Bool {
        decibels.allSatisfy { $0 < -90 }
    }

    func save() {
        guard isDirty else { return }
        var data = Data(Self.magic)
        withUnsafeBytes(of: duration.bitPattern.littleEndian) { data.append(contentsOf: $0) }
        data.append(contentsOf: frames)
        do {
            try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            isDirty = false
        } catch {
            NSLog("[Notchland] Ritim kaydedilemedi: \(error.localizedDescription)")
        }
    }

    /// Süre farklıysa (başka bir sürüm) eski kayıt kullanılmaz, üzerine yazılır.
    private static func load(_ url: URL, duration: TimeInterval, count: Int) -> [UInt8]? {
        guard let data = try? Data(contentsOf: url), data.count == magic.count + 8 + count,
              Array(data.prefix(magic.count)) == magic
        else { return nil }
        let bits = data.dropFirst(magic.count).prefix(8).enumerated()
            .reduce(UInt64(0)) { $0 | UInt64($1.element) << (8 * UInt64($1.offset)) }
        guard abs(Double(bitPattern: bits) - duration) < 3 else { return nil }
        return Array(data.dropFirst(magic.count + 8))
    }

    /// Her bandın 15. ve 98. yüzdeliği; dalga bu aralıkta ölçeklenir.
    private func updateRanges() {
        recordsSinceRangeUpdate = 0
        ranges = histograms.map { histogram in
            let total = histogram.reduce(0, +)
            guard total > 0 else { return (0, 0) }
            func percentile(_ p: Double) -> Double {
                let target = Int(Double(total) * p)
                var running = 0
                for (value, count) in histogram.enumerated() {
                    running += count
                    if running > target { return Double(value) }
                }
                return 255
            }
            return (percentile(0.15), percentile(0.98))
        }
    }

    // MARK: - Klasör

    /// Kayıtlı şarkı sayısı ve toplam boyut (bayt).
    static func folderSummary() -> (count: Int, bytes: Int) {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.fileSizeKey]
        ))?.filter { $0.pathExtension == "ritim" } ?? []
        let bytes = files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        return (files.count, bytes)
    }

    static func revealFolder() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }
}

/// Ayarlarda kayıt klasörünün özeti ve açma düğmesi.
struct RhythmFolderRow: View {
    @State private var summary = (count: 0, bytes: 0)

    var body: some View {
        LabeledContent("Kayıtlı ritimler") {
            HStack {
                Text("\(summary.count) şarkı · \(ByteCountFormatter.string(fromByteCount: Int64(summary.bytes), countStyle: .file))")
                    .foregroundStyle(.secondary)
                Button("Klasörü aç") { RhythmRecording.revealFolder() }
            }
        }
        .onAppear { summary = RhythmRecording.folderSummary() }
    }
}
