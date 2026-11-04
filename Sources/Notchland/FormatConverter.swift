import AppKit
import AVFoundation
import PDFKit
import UniformTypeIdentifiers

/// Kullanıcının kurduğu araçlar (`brew install ffmpeg yt-dlp`, cwebp de ffmpeg'in bağımlılığı olarak gelir). Pakete gömülmez:
/// Homebrew derlemesi GPL, Notchland MIT. Uygulamalar kabuğun PATH'ini görmediği için yaygın konumlara
/// bakılır; kurulunca yeniden başlatmak gerekmez.
enum ExternalTool: String {
    case ffmpeg, cwebp, gif2webp
    case ytDlp = "yt-dlp"

    var path: String? {
        ["/opt/homebrew/bin/", "/usr/local/bin/"].map { $0 + rawValue }.first(where: FileManager.default.isExecutableFile)
    }
}

/// Format çarkındaki hedefler. Dönüştürme macOS'in kendi araçlarıyla yapılır; sistemin yazamadığı
/// biçimler (`needsFFmpeg`) ffmpeg kuruluysa çarkta görünür.
enum FileFormat: String, CaseIterable, Identifiable {
    case png, jpeg, heic, tiff, gif, bmp, pdf, webp
    case mp4, mov, m4v, mkv, webm
    case m4a, wav, aiff, flac, caf, mp3
    case txt, rtf, docx, doc, odt, html

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
    var fileExtension: String { self == .jpeg ? "jpg" : rawValue }

    var symbol: String {
        switch self {
        case .png: "square.dashed"
        case .jpeg: "photo.fill"
        case .heic: "photo.on.rectangle"
        case .tiff: "photo.artframe"
        case .gif: "play.square.stack"
        case .bmp: "squareshape.split.3x3"
        case .pdf: "doc.richtext.fill"
        case .webp: "globe"
        case .mp4: "play.rectangle.fill"
        case .mov: "film"
        case .m4v: "tv"
        case .mkv: "shippingbox"
        case .webm: "play.tv"
        case .m4a: "music.note"
        case .wav: "waveform"
        case .aiff: "waveform.path"
        case .flac: "hifispeaker.fill"
        case .caf: "music.note.list"
        case .mp3: "music.quarternote.3"
        case .txt: "doc.plaintext"
        case .rtf: "doc.richtext"
        case .docx: "doc.text.fill"
        case .doc: "doc.text"
        case .odt: "doc.append"
        case .html: "chevron.left.forwardslash.chevron.right"
        }
    }

    /// Çarkın göbeğinde, seçili dilimin altında görünen kısa açıklama.
    var hint: String {
        switch self {
        case .png: "Kayıpsız, şeffaflık korunur"
        case .jpeg: "Küçük boyut, fotoğraflara uygun"
        case .heic: "Yüksek verim, Apple cihazları"
        case .tiff: "Kayıpsız, baskıya uygun"
        case .gif: "Hareketli görsel, az renk"
        case .bmp: "Sıkıştırmasız"
        case .pdf: "Her yerde aynı görünür"
        case .webp: "Web için küçük boyut"
        case .mp4: "En uyumlu video"
        case .mov: "Apple'ın video kabı"
        case .m4v: "iTunes uyumlu video"
        case .mkv: "Yeniden kodlamadan, kayıpsız"
        case .webm: "Web videosu, yavaş kodlanır"
        case .m4a: "AAC ses, küçük boyut"
        case .wav: "Sıkıştırmasız ses"
        case .aiff: "Sıkıştırmasız, Apple"
        case .flac: "Kayıpsız sıkıştırma"
        case .caf: "Core Audio dosyası"
        case .mp3: "Her yerde çalar"
        case .txt: "Biçimsiz düz metin"
        case .rtf: "Biçimli metin"
        case .docx: "Word belgesi"
        case .doc: "Eski Word belgesi"
        case .odt: "OpenDocument metni"
        case .html: "Web sayfası"
        }
    }

    /// macOS'in yazamadığı biçimler (WebP'yi cwebp yazar).
    fileprivate var needsFFmpeg: Bool {
        switch self {
        case .webp, .mkv, .webm, .mp3: true
        default: false
        }
    }

    /// Yazılamayan biçimler çarkta gösterilmez: ffmpeg yoksa onun biçimleri, ImageIO kodlayıcısı olmayan görseller.
    fileprivate var isAvailable: Bool {
        if self == .webp { return ExternalTool.cwebp.path != nil }
        if needsFFmpeg { return ExternalTool.ffmpeg.path != nil }
        guard let type = imageType else { return true }
        let writable = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        return writable.contains(type.identifier)
    }

    fileprivate var imageType: UTType? {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        case .heic: .heic
        case .tiff: .tiff
        case .gif: .gif
        case .bmp: .bmp
        default: nil
        }
    }

    fileprivate init?(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "jpg", "jpeg": self = .jpeg
        case "tif", "tiff": self = .tiff
        case "htm", "html": self = .html
        case "aif", "aiff": self = .aiff
        case let other: self.init(rawValue: other)
        }
    }
}

/// Aynı araçla dönüştürülebilen dosya aileleri; çarkta hangi dilimlerin çıkacağını belirler.
enum FormatFamily {
    case image, video, audio, document, pdf
    /// Dosya değil, video bağlantısı: yt-dlp ile indirilir.
    case download

    private static let videoHosts: Set<String> = [
        "youtube.com", "youtu.be", "vimeo.com", "tiktok.com", "instagram.com", "x.com", "twitter.com", "twitch.tv", "dailymotion.com",
    ]

    /// Her bağlantı değil, yalnızca bilinen video siteleri: sıradan bir link kopyalanınca çark indirmeye dönmesin.
    static func isVideoLink(_ url: URL) -> Bool {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""), var host = url.host?.lowercased() else { return false }
        for prefix in ["www.", "m.", "music."] where host.hasPrefix(prefix) { host.removeFirst(prefix.count) }
        return videoHosts.contains(host)
    }

    fileprivate static let documentExtensions: Set<String> = [
        "txt", "rtf", "rtfd", "html", "htm", "doc", "docx", "odt", "webarchive",
    ]

    /// macOS'in tanımadığı, yalnızca ffmpeg'in açabildiği kaplar.
    private static let ffmpegVideoExtensions: Set<String> = ["mkv", "webm", "avi", "flv", "wmv", "ogv", "ts", "m2ts", "vob"]
    private static let ffmpegAudioExtensions: Set<String> = ["ogg", "oga", "opus", "wma", "ape", "mka"]

    init?(url: URL) {
        if !url.isFileURL {
            guard Self.isVideoLink(url), ExternalTool.ytDlp.path != nil else { return nil }
            self = .download
            return
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return nil }
        let ext = url.pathExtension.lowercased()
        // RTFD paket olarak bir klasördür; diğer klasörler dönüştürülemez.
        if isDirectory.boolValue && ext != "rtfd" { return nil }
        let type = UTType(filenameExtension: ext)

        if ExternalTool.ffmpeg.path != nil, Self.ffmpegVideoExtensions.contains(ext) {
            self = .video
        } else if ExternalTool.ffmpeg.path != nil, Self.ffmpegAudioExtensions.contains(ext) {
            self = .audio
        } else if type?.conforms(to: .pdf) == true {
            self = .pdf
        } else if let type, type.conforms(to: .image) {
            // SVG gibi "görsel" sayılıp ImageIO'nun okuyamadığı türler çarkı boşuna açmasın.
            let readable = CGImageSourceCopyTypeIdentifiers() as? [String] ?? []
            guard readable.contains(type.identifier) else { return nil }
            self = .image
        } else if type?.conforms(to: .movie) == true || type?.conforms(to: .video) == true {
            self = .video
        } else if type?.conforms(to: .audio) == true {
            self = .audio
        } else if Self.documentExtensions.contains(ext) || type?.conforms(to: .plainText) == true {
            self = .document
        } else {
            return nil
        }
    }

    private var allTargets: [FileFormat] {
        switch self {
        case .image: [.png, .jpeg, .webp, .heic, .pdf, .tiff, .gif, .bmp]
        case .video: [.mp4, .mov, .webm, .mkv, .gif, .mp3, .m4a, .m4v]
        case .audio: [.mp3, .m4a, .wav, .flac, .aiff, .caf]
        case .document: [.pdf, .docx, .txt, .rtf, .html, .odt, .doc]
        case .pdf: [.png, .jpeg, .heic, .txt]
        case .download: [.mp4, .mp3]
        }
    }

    /// Dosyaların hepsi zaten aynı biçimdeyse o biçim dilim olarak sunulmaz.
    func targets(for sources: [URL]) -> [FileFormat] {
        let current = Set(sources.map { FileFormat(fileExtension: $0.pathExtension) })
        // Videodan GIF de ffmpeg ister (görselden GIF'i ImageIO yazar).
        let videoGIFMissing = self == .video && ExternalTool.ffmpeg.path == nil
        return allTargets.filter {
            $0.isAvailable && !(current.count == 1 && current.contains($0)) && !($0 == .gif && videoGIFMissing)
        }
    }
}

struct ConversionError: LocalizedError {
    let errorDescription: String?

    init(_ message: String) {
        errorDescription = message
    }
}

enum FormatConverter {
    /// Kaynağa dokunmaz; sonucu yanına yeni bir adla yazar ve (PDF'ten görselde ilk sayfanın) adresini döndürür.
    static func convert(_ source: URL, to format: FileFormat, onProgress: ((String, Int) -> Void)? = nil) async throws -> URL {
        guard let family = FormatFamily(url: source) else {
            throw ConversionError("Bu dosya türü desteklenmiyor")
        }
        if family == .download { return try await download(source, as: format, onProgress: onProgress) }
        let directory = outputDirectory(for: source)
        let name = source.deletingPathExtension().lastPathComponent
        if family == .pdf, format != .txt {
            return try renderPDF(source, to: format, directory: directory, name: name)
        }

        let destination = uniqueURL(in: directory, name: name, fileExtension: format.fileExtension)
        do {
            switch family {
            case .image:
                if format == .webp {
                    try await convertToWebP(source, destination: destination)
                } else {
                    try convertImage(source, to: format, destination: destination)
                }
            case .video, .audio:
                try await convertMedia(source, to: format, family: family, destination: destination)
            case .document: try await convertDocument(source, to: format, destination: destination)
            case .pdf: try extractPDFText(source, destination: destination)
            case .download: break
            }
        } catch {
            // Yarım kalan çıktı kaynağın yanında kalmasın.
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        return destination
    }

    // MARK: - Hedef konum

    /// Pano kaydı ve bırakılan geçici içerikler kullanıcının görmediği klasörlerde durur; sonuç Masaüstüne gider.
    private static func outputDirectory(for source: URL) -> URL {
        let manager = FileManager.default
        let directory = source.deletingLastPathComponent().standardizedFileURL
        let hidden = [
            manager.temporaryDirectory,
            manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Notchland"),
        ].map { $0.standardizedFileURL.path }
        let isHidden = hidden.contains { directory.path.hasPrefix($0) }
        if !isHidden, manager.isWritableFile(atPath: directory.path) { return directory }
        return manager.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    /// Var olan bir dosyanın üzerine asla yazma.
    private static func uniqueURL(in directory: URL, name: String, fileExtension: String) -> URL {
        var url = directory.appendingPathComponent(name).appendingPathExtension(fileExtension)
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(name) \(counter)").appendingPathExtension(fileExtension)
            counter += 1
        }
        return url
    }

    // MARK: - Görsel

    private static func convertImage(_ source: URL, to format: FileFormat, destination: URL) throws {
        if format == .pdf { return try writeImagePDF(source, destination: destination) }
        guard let input = CGImageSourceCreateWithURL(source as CFURL, nil), CGImageSourceGetCount(input) > 0,
              let type = format.imageType else {
            throw ConversionError("Görsel okunamadı")
        }
        // Hareketli GIF'in kareleri yalnızca çok kareli biçimlerde korunur.
        let frames = format == .gif || format == .tiff ? CGImageSourceGetCount(input) : 1
        guard let output = CGImageDestinationCreateWithURL(destination as CFURL, type.identifier as CFString, frames, nil) else {
            throw ConversionError("\(format.title) yazılamıyor")
        }
        for index in 0..<frames {
            var options: [CFString: Any] = [:]
            if format == .jpeg || format == .heic { options[kCGImageDestinationLossyCompressionQuality] = 0.9 }
            // JPEG ve BMP'de şeffaflık yok; pencere gölgeli ekran görüntüleri siyah zeminli çıkmasın.
            if format == .jpeg || format == .bmp, let image = CGImageSourceCreateImageAtIndex(input, index, nil),
               let opaque = flattened(image) {
                let original = CGImageSourceCopyPropertiesAtIndex(input, index, nil) as? [CFString: Any] ?? [:]
                CGImageDestinationAddImage(output, opaque, original.merging(options) { $1 } as CFDictionary)
            } else {
                CGImageDestinationAddImageFromSource(output, input, index, options as CFDictionary)
            }
        }
        guard CGImageDestinationFinalize(output) else { throw ConversionError("\(format.title) yazılamadı") }
    }

    private static func flattened(_ image: CGImage) -> CGImage? {
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard let context = whiteContext(width: image.width, height: image.height) else { return nil }
        context.draw(image, in: rect)
        return context.makeImage()
    }

    private static func whiteContext(width: Int, height: Int) -> CGContext? {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.setFillColor(.white)
        context?.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context
    }

    private static func writeImagePDF(_ source: URL, destination: URL) throws {
        guard let image = NSImage(contentsOf: source), let page = PDFPage(image: image) else {
            throw ConversionError("Görsel okunamadı")
        }
        let document = PDFDocument()
        document.insert(page, at: 0)
        guard document.write(to: destination) else { throw ConversionError("PDF yazılamadı") }
    }

    // MARK: - PDF

    /// Her sayfa ayrı dosya olur: tek sayfada `ad.png`, çok sayfada `ad-1.png`, `ad-2.png`…
    private static func renderPDF(_ source: URL, to format: FileFormat, directory: URL, name: String) throws -> URL {
        let document = try openPDF(source)
        guard let type = format.imageType else { throw ConversionError("\(format.title) yazılamıyor") }
        var first: URL?
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let box = page.bounds(for: .mediaBox)
            let isSideways = page.rotation % 180 != 0
            let scale: CGFloat = 2
            let width = Int((isSideways ? box.height : box.width) * scale)
            let height = Int((isSideways ? box.width : box.height) * scale)
            guard let context = whiteContext(width: width, height: height) else { continue }
            context.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: context)

            let pageName = document.pageCount == 1 ? name : "\(name)-\(index + 1)"
            let url = uniqueURL(in: directory, name: pageName, fileExtension: format.fileExtension)
            guard let image = context.makeImage(),
                  let output = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
                throw ConversionError("\(format.title) yazılamıyor")
            }
            CGImageDestinationAddImage(output, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
            guard CGImageDestinationFinalize(output) else { throw ConversionError("\(format.title) yazılamadı") }
            first = first ?? url
        }
        guard let first else { throw ConversionError("PDF'te sayfa yok") }
        return first
    }

    private static func extractPDFText(_ source: URL, destination: URL) throws {
        let text = try openPDF(source).string ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ConversionError("PDF'te metin yok (taranmış olabilir)")
        }
        try text.write(to: destination, atomically: true, encoding: .utf8)
    }

    private static func openPDF(_ source: URL) throws -> PDFDocument {
        guard let document = PDFDocument(url: source) else { throw ConversionError("PDF okunamadı") }
        guard !document.isLocked else { throw ConversionError("PDF parolalı") }
        return document
    }

    // MARK: - İndirme

    private static var downloadsDirectory: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }

    /// İlerleme satırlarını dosya yolundan ayıran ön ek.
    private static let progressPrefix = "NOTCHLAND"

    /// H.264 öncelikli seçilir ki dosya QuickTime'da da açılsın (çoğunlukla en fazla 1080p).
    /// Yarım parçalar geçici klasörde durur; İndirilenler'e yalnızca bitmiş dosya düşer.
    private static func download(_ link: URL, as format: FileFormat, onProgress: ((String, Int) -> Void)?) async throws -> URL {
        guard let tool = ExternalTool.ytDlp.path else { throw ConversionError("yt-dlp kurulu değil (brew install yt-dlp)") }
        let partial = FileManager.default.temporaryDirectory.appendingPathComponent("NotchlandDownloads", isDirectory: true)
        var arguments = [
            "--ignore-config", "--no-playlist", "--no-warnings", "--no-mtime",
            // Canlı yayın hiç bitmez; arka planda sonsuza dek inmesin.
            "--match-filter", "!is_live",
            "-P", "home:" + downloadsDirectory.path, "-P", "temp:" + partial.path, "-o", "%(title).150B.%(ext)s",
            "--print", "after_move:filepath",
            "--progress", "--newline", "--progress-template", "download:\(progressPrefix) %(info.vcodec)s %(progress._percent_str)s",
        ]
        if let ffmpeg = ExternalTool.ffmpeg.path { arguments += ["--ffmpeg-location", ffmpeg] }
        if format == .mp3 {
            arguments += ["-x", "--audio-format", "mp3", "--audio-quality", "2"]
        } else {
            arguments += ["-S", "vcodec:h264,res,acodec:aac", "--merge-output-format", "mp4"]
        }
        let path = try await lastOutputLine(tool, arguments + ["--", link.absoluteString]) { line in
            // "NOTCHLAND avc1.640028  42.3%": MP4 önce görüntü, sonra ses olarak iki parça iner.
            let parts = line.split(separator: " ")
            guard parts.count >= 3, let percent = Double(parts[2].dropLast()) else { return }
            onProgress?(format == .mp4 && parts[1] == "none" ? "Ses" : format.title, Int(percent))
        }
        guard FileManager.default.fileExists(atPath: path) else { throw ConversionError("Bu bağlantı indirilemedi") }
        return URL(fileURLWithPath: path)
    }

    /// Çıktıyı satır satır okur: ilerleme satırları `onProgress`'e gider, kalanların sonuncusu döner.
    /// yt-dlp, YouTube çözümü için PATH'teki JS motorunu arar; uygulamanın PATH'i ise dardır.
    private static func lastOutputLine(_ tool: String, _ arguments: [String], onProgress: @escaping (String) -> Void) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: tool)
            task.arguments = arguments
            task.environment = ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin", "HOME": NSHomeDirectory()]
            let output = Pipe()
            task.standardOutput = output
            task.standardError = FileHandle.nullDevice
            DispatchQueue.global(qos: .utility).async {
                do {
                    try task.run()
                } catch {
                    return continuation.resume(throwing: error)
                }
                var buffer = Data()
                var last = ""
                func consume(_ bytes: Data) {
                    let line = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                    if line.hasPrefix(progressPrefix) { onProgress(line) } else if !line.isEmpty { last = line }
                }
                while true {
                    let chunk = output.fileHandleForReading.availableData
                    if chunk.isEmpty { break }
                    buffer.append(chunk)
                    while let newline = buffer.firstIndex(where: { $0 == 10 || $0 == 13 }) {
                        consume(buffer[buffer.startIndex..<newline])
                        buffer = Data(buffer[buffer.index(after: newline)...])
                    }
                }
                consume(buffer)
                task.waitUntilExit()
                if task.terminationStatus == 0 {
                    continuation.resume(returning: last)
                } else {
                    continuation.resume(throwing: ConversionError("Bu bağlantı indirilemedi"))
                }
            }
        }
    }

    // MARK: - Video ve ses

    /// Önce sistemin araçları denenir (MOV→MP4 anında ve kayıpsız olur); onların yazamadığı biçimler
    /// ve açamadığı kaynaklar ffmpeg'e gider.
    private static func convertMedia(_ source: URL, to format: FileFormat, family: FormatFamily, destination: URL) async throws {
        if !format.needsFFmpeg && format != .gif {
            do {
                if family == .video {
                    try await convertVideo(source, to: format, destination: destination)
                } else {
                    try await convertAudio(source, to: format, destination: destination)
                }
                return
            } catch {
                guard ExternalTool.ffmpeg.path != nil else { throw error }
                try? FileManager.default.removeItem(at: destination)
            }
        }
        try await runFFmpeg(source, arguments: ffmpegArguments(for: format), destination: destination)
    }

    private static func ffmpegArguments(for format: FileFormat) -> [String] {
        let h264 = ["-c:v", "libx264", "-crf", "20", "-preset", "medium", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", "-sn"]
        switch format {
        case .mp4, .m4v: return h264 + ["-movflags", "+faststart"]
        case .mov: return h264
        case .mkv: return ["-c:v", "copy", "-c:a", "copy", "-sn"]
        case .webm: return ["-c:v", "libvpx-vp9", "-crf", "32", "-b:v", "0", "-row-mt", "1", "-c:a", "libopus", "-b:a", "128k", "-sn"]
        // Ortak palet tüm kareler için üretilmezse GIF'te renk bantları çıkar.
        case .gif: return ["-vf", "fps=12,scale='min(480,iw)':-2:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse", "-loop", "0"]
        case .mp3: return ["-vn", "-c:a", "libmp3lame", "-q:a", "2"]
        case .m4a: return ["-vn", "-c:a", "aac", "-b:a", "256k"]
        case .wav: return ["-vn", "-c:a", "pcm_s16le"]
        case .aiff: return ["-vn", "-c:a", "pcm_s16be"]
        case .flac: return ["-vn", "-c:a", "flac"]
        case .caf: return ["-vn", "-c:a", "pcm_s16le"]
        default: return []
        }
    }

    /// HEIC gibi kaynakları cwebp okuyamaz ve EXIF yönünü uygulamaz; bu yüzden görsel önce ImageIO ile
    /// düz bir PNG'ye açılır. Hareketli GIF kareleri korunsun diye gif2webp'e doğrudan verilir.
    private static func convertToWebP(_ source: URL, destination: URL) async throws {
        if source.pathExtension.lowercased() == "gif", let gif2webp = ExternalTool.gif2webp.path {
            return try await run(gif2webp, ["-quiet", "-q", "85", "-mt", source.path, "-o", destination.path])
        }
        guard let cwebp = ExternalTool.cwebp.path else { throw ConversionError("cwebp kurulu değil (brew install webp)") }
        guard let input = CGImageSourceCreateWithURL(source as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(input, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 1 << 16,
              ] as CFDictionary)
        else { throw ConversionError("Görsel okunamadı") }

        let work = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: work) }
        guard let output = CGImageDestinationCreateWithURL(work as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw ConversionError("Görsel okunamadı")
        }
        CGImageDestinationAddImage(output, image, nil)
        guard CGImageDestinationFinalize(output) else { throw ConversionError("Görsel okunamadı") }
        try await run(cwebp, ["-quiet", "-q", "85", "-mt", work.path, "-o", destination.path])
    }

    private static func runFFmpeg(_ source: URL, arguments: [String], destination: URL) async throws {
        guard let ffmpeg = ExternalTool.ffmpeg.path else { throw ConversionError("ffmpeg kurulu değil (brew install ffmpeg)") }
        // -n: var olan dosyanın üzerine yazma; -nostdin: arka planda girdi beklemesin.
        try await run(ffmpeg, ["-hide_banner", "-nostdin", "-loglevel", "error", "-n", "-i", source.path] + arguments + [destination.path])
    }

    private static func convertVideo(_ source: URL, to format: FileFormat, destination: URL) async throws {
        let asset = AVURLAsset(url: source)
        let fileType: AVFileType
        // Önce yeniden kodlamadan dene: anında biter ve kalite kaybı olmaz.
        var presets = [AVAssetExportPresetPassthrough, AVAssetExportPresetHighestQuality]
        switch format {
        case .mp4: fileType = .mp4
        case .mov: fileType = .mov
        case .m4v: fileType = .m4v
        case .m4a:
            fileType = .m4a
            presets = [AVAssetExportPresetAppleM4A]
        default: throw ConversionError("\(format.title) yazılamıyor")
        }
        for preset in presets {
            guard let session = AVAssetExportSession(asset: asset, presetName: preset),
                  session.supportedFileTypes.contains(fileType) else { continue }
            session.outputURL = destination
            session.outputFileType = fileType
            await session.export()
            if session.status == .completed { return }
            try? FileManager.default.removeItem(at: destination)
        }
        throw ConversionError("Bu video \(format.title) yapılamadı")
    }

    // MARK: - Ses

    private static func convertAudio(_ source: URL, to format: FileFormat, destination: URL) async throws {
        let codec: [String]
        switch format {
        case .m4a: codec = ["-f", "m4af", "-d", "aac", "-b", "256000"]
        case .wav: codec = ["-f", "WAVE", "-d", "LEI16"]
        case .aiff: codec = ["-f", "AIFF", "-d", "BEI16"]
        case .flac: codec = ["-f", "flac", "-d", "flac"]
        case .caf: codec = ["-f", "caff", "-d", "LEI16"]
        default: throw ConversionError("\(format.title) yazılamıyor")
        }
        try await run("/usr/bin/afconvert", codec + [source.path, destination.path])
    }

    // MARK: - Belge

    private static func convertDocument(_ source: URL, to format: FileFormat, destination: URL) async throws {
        if format == .pdf {
            let work = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: work) }
            if let html = await officeHTML(source, in: work), let text = await readOfficeHTML(html) {
                return try await writeDocumentPDF(text, destination: destination)
            }
            // Diğer belgeler RTFD'ye çevrilir: HTML'deki uzak kaynaklar indirilmez.
            let rich = work.appendingPathComponent("belge.rtfd")
            try await runTextUtil(source, convert: "rtfd", destination: rich)
            let text = try await MainActor.run { try NSAttributedString(url: rich, options: [:], documentAttributes: nil) }
            try await writeDocumentPDF(text, destination: destination)
        } else {
            try await runTextUtil(source, convert: format.rawValue, destination: destination)
        }
    }

    private static func runTextUtil(_ source: URL, convert: String, destination: URL) async throws {
        var arguments = ["-noload", "-convert", convert, "-output", destination.path]
        // textutil biçimi uzantıdan anlar; .md ve benzeri düz metinleri açıkça belirt.
        let ext = source.pathExtension.lowercased()
        if !FormatFamily.documentExtensions.contains(ext) { arguments += ["-format", "txt"] }
        // charset yazmayan HTML'i textutil Latin-1 sanar ve Türkçe harfler bozulur. Bayrak belgedeki
        // bildirimi de ezdiği için yalnızca içerik gerçekten UTF-8 ise verilir.
        let isBinary = ["doc", "docx", "odt", "rtf", "rtfd", "webarchive"].contains(ext)
        if !isBinary, let data = try? Data(contentsOf: source), String(data: data, encoding: .utf8) != nil {
            arguments += ["-inputencoding", "UTF-8"]
        }
        try await run("/usr/bin/textutil", arguments + [source.path])
    }

    /// textutil Word belgelerindeki görselleri okumaz; Quick Look ise belgeyi görselleriyle birlikte HTML'e açar.
    /// Çıktı `Preview.html` ve yanında `AttachmentN` dosyalarıdır. Olmazsa `nil`: metin yine textutil'den gelir.
    private static func officeHTML(_ source: URL, in work: URL) async -> URL? {
        guard ["docx", "doc", "odt"].contains(source.pathExtension.lowercased()) else { return nil }
        guard (try? await run("/usr/bin/qlmanage", ["-p", "-o", work.path, source.path])) != nil else { return nil }
        let html = work.appendingPathComponent(source.lastPathComponent + ".qlpreview/Preview.html")
        return FileManager.default.fileExists(atPath: html.path) ? html : nil
    }

    @MainActor
    private static func readOfficeHTML(_ html: URL) -> NSAttributedString? {
        // Belgedeki uzak görseller indirilmesin; yanındaki ekler yereldir.
        if let page = try? String(contentsOf: html, encoding: .utf8) {
            let local = page.replacingOccurrences(of: "src\\s*=\\s*\"https?:[^\"]*\"", with: "src=\"\"", options: .regularExpression)
            try? local.write(to: html, atomically: true, encoding: .utf8)
        }
        return try? NSAttributedString(
            url: html,
            options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
            documentAttributes: nil
        )
    }

    /// Sayfadan büyük görsel sayfa kabına sığmaz ve metni oracıkta keser; orantılı küçültülür.
    @MainActor
    private static func fitAttachments(in text: NSMutableAttributedString, to frame: CGSize) {
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, _, _ in
            guard let attachment = value as? NSTextAttachment else { return }
            let image = attachment.image ?? attachment.fileWrapper?.regularFileContents.flatMap(NSImage.init(data:))
            let natural = attachment.bounds.width > 0 ? attachment.bounds.size
                : attachment.attachmentCell?.cellSize() ?? image?.size ?? .zero
            guard natural.width > 0, natural.height > 0 else { return }
            // Satır aralığına da yer kalsın diye yükseklikte biraz pay.
            let scale = min(1, frame.width / natural.width, (frame.height - 8) / natural.height)
            let size = CGSize(width: natural.width * scale, height: natural.height * scale)
            if let image {
                image.size = size
                attachment.attachmentCell = NSTextAttachmentCell(imageCell: image)
            }
            attachment.bounds = CGRect(origin: .zero, size: size)
        }
    }

    /// Metni A4 sayfalara kendisi böler: her sayfa bir metin kabı, çizim doğrudan PDF bağlamına.
    @MainActor
    private static func writeDocumentPDF(_ text: NSAttributedString, destination: URL) throws {
        let page = CGSize(width: 595, height: 842)
        let margin: CGFloat = 50
        let fitted = NSMutableAttributedString(attributedString: text)
        fitAttachments(in: fitted, to: CGSize(width: page.width - margin * 2, height: page.height - margin * 2))
        let storage = NSTextStorage(attributedString: fitted)
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)

        var mediaBox = CGRect(origin: .zero, size: page)
        guard let pdf = CGContext(destination as CFURL, mediaBox: &mediaBox, nil) else {
            throw ConversionError("PDF yazılamadı")
        }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: pdf, flipped: true)

        var range: NSRange
        repeat {
            let container = NSTextContainer(size: CGSize(width: page.width - margin * 2, height: page.height - margin * 2))
            layout.addTextContainer(container)
            range = layout.glyphRange(for: container)
            pdf.beginPDFPage(nil)
            pdf.translateBy(x: margin, y: page.height - margin)
            pdf.scaleBy(x: 1, y: -1)
            layout.drawBackground(forGlyphRange: range, at: .zero)
            layout.drawGlyphs(forGlyphRange: range, at: .zero)
            pdf.endPDFPage()
            // Sayfaya sığmayan tek parça (dev görsel) sonsuz döngüye sokmasın.
        } while range.length > 0 && NSMaxRange(range) < layout.numberOfGlyphs
        pdf.closePDF()
    }

    // MARK: - Süreç

    private static func run(_ tool: String, _ arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: tool)
            task.arguments = arguments
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            task.terminationHandler = { finished in
                if finished.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ConversionError("Bu dosya dönüştürülemedi"))
                }
            }
            do {
                try task.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
