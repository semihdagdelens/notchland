import SwiftUI

/// Koci'nin (Kocinyo'nun yıldız gözlü kedisi) piksel çizimi. Kareler katmanlardan (kafa, gözler, gövde,
/// kuyruk, süs) birleştirilir ve önbelleğe alınır; her karakter bir piksel rengidir, '.' saydamdır.
enum KociSprite {
    enum Pose { case sitting, hanging }
    enum Eyes { case open, happy, closed, star, sad }
    enum Extra { case none, note, sleep, sweat }

    struct Frame: Hashable {
        var pose: Pose
        var eyes: Eyes
        var tail: Int
        var extra: Extra = .none
    }

    typealias Grid = [[Character]]

    // MARK: - Renkler (Kocinyo maskot paleti, koyu zeminde seçilsin diye biraz açılmış)

    private static let palette: [Character: (CGFloat, CGFloat, CGFloat)] = [
        "K": (0.03, 0.04, 0.09),  // kontur
        "B": (0.30, 0.32, 0.47),  // kürk
        "b": (0.24, 0.26, 0.38),  // kürk gölgesi
        "E": (0.47, 0.46, 0.66),  // kulak içi
        "D": (0.10, 0.10, 0.34),  // göz derinliği
        "G": (0.73, 0.78, 0.86),  // göz parıltısı
        "S": (0.97, 0.97, 1.00),  // gözdeki yıldız
        "N": (0.75, 0.64, 0.47),  // altın burun
        "T": (0.17, 0.21, 0.42),  // kuyruk
        "W": (0.96, 0.96, 0.98),  // kuyruk ucu, notalar
        "Y": (1.00, 0.82, 0.30),  // heyecanlı gözler
        "L": (0.50, 0.75, 1.00),  // gözyaşı, ter
    ]

    // MARK: - Katmanlar

    private static let head = [
        ".K............K.",
        "KEK..........KEK",
        "KEEK........KEEK",
        "KBEEK......KEEBK",
        "KBBEBKKKKKKBEBBK",
        "KBBBBBBBBBBBBBBK",
        "KB....BBBB....BK",
        "KB....BBBB....BK",
        "KB....BBBB....BK",
        "KB....BBBB....BK",
        "KBBBBBBNNBBBBBBK",
        ".KBBBBKBBKBBBBK.",
        "..KKBBBKKBBBKK..",
    ]

    /// Her göz 4×4; kafadaki boşluklara yerleşir.
    private static func eyes(_ eyes: Eyes) -> [String] {
        switch eyes {
        case .open: ["DDDD", "DSDD", "DDDS", "GGDD"]
        case .happy: ["BBBB", "BKKB", "KBBK", "BBBB"]
        case .closed: ["BBBB", "BBBB", "KKKK", "BBBB"]
        case .star: ["DYYD", "YYYY", "YYYY", "DYYD"]
        case .sad: ["DDDD", "DSDD", "DDDD", "LGDD"]
        }
    }

    private static let sitBody = [
        "...KBBBBBBBBK...",
        "..KBBBBBBBBBBK..",
        "..KBBBBBBBBBBK..",
        "..KBBbBBBBbBBK..",
        "..KBKBBKKBBKBK..",
        "...KKKK..KKKK...",
    ]

    private static let sitTail = [
        ["..WW", "..WW", "..TT", ".TT.", ".TT.", "TT..", "T..."],
        ["....", "WW..", "WT..", ".TT.", "..TT", ".TT.", "TT.."],
    ]

    private static let hangBody = [
        "...KBBBBBBBBK...",
        "...KBbBBBBbBK...",
        "...KBbBBBBbBK...",
        "...KBBKKKKBBK...",
        "...KBK....KBK...",
        "....K......K....",
    ]

    private static let hangTail = [
        [".TT.", ".TT.", "..TT", "..TT", ".WW.", "WW.."],
        [".TT.", ".TT.", "TT..", "TT..", ".WW.", "..WW"],
    ]

    /// Kenara tutunan kol; üst kısmı notch'un arkasında kalır.
    private static let arm = [String](repeating: "KBK", count: 11)

    private static let note = ["..WW", "..W.", "..W.", "WWW.", "WW.."]
    private static let sleepZ = ["WWW", "..W", ".W.", "WWW"]
    private static let sweat = [".L.", "LLL", ".L."]

    // MARK: - Birleştirme

    /// Pozun ızgara boyutu (sütun, satır).
    static func size(of pose: Pose) -> (columns: Int, rows: Int) {
        pose == .sitting ? (22, 21) : (20, 25)
    }

    private static var images: [Frame: CGImage] = [:]

    /// Karenin piksel başına bir piksellik görseli; her kare bir kez çizilir.
    static func image(_ frame: Frame) -> CGImage? {
        if let cached = images[frame] { return cached }
        let grid = grid(frame)
        let (columns, rows) = size(of: frame.pose)
        guard let context = CGContext(
            data: nil, width: columns, height: rows, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        for (row, line) in grid.enumerated() {
            for (column, character) in line.enumerated() {
                guard let (r, g, b) = palette[character] else { continue }
                context.setFillColor(red: r, green: g, blue: b, alpha: 1)
                // CGContext'in y ekseni aşağıdan yukarı.
                context.fill(CGRect(x: column, y: rows - 1 - row, width: 1, height: 1))
            }
        }
        let image = context.makeImage()
        images[frame] = image
        return image
    }

    private static func grid(_ frame: Frame) -> Grid {
        let (columns, rows) = size(of: frame.pose)
        var grid = Grid(repeating: [Character](repeating: ".", count: columns), count: rows)
        let eyeRows = eyes(frame.eyes)
        switch frame.pose {
        case .sitting:
            // Kedi 2 satır aşağıda; üstteki pay notalar ve "z"ler için.
            put(&grid, head, x: 0, y: 2)
            put(&grid, eyeRows, x: 2, y: 8, opaque: true)
            put(&grid, eyeRows, x: 10, y: 8, opaque: true)
            put(&grid, sitBody, x: 0, y: 15)
            put(&grid, sitTail[frame.tail % 2], x: 14, y: 12)
            switch frame.extra {
            case .note: put(&grid, note, x: 18, y: frame.tail % 2 == 0 ? 0 : 1)
            case .sleep: put(&grid, sleepZ, x: 18, y: frame.tail % 2 == 0 ? 0 : 1)
            case .sweat: put(&grid, sweat, x: 15, y: 4)
            case .none: break
            }
        case .hanging:
            put(&grid, arm, x: 0, y: 0)
            put(&grid, arm, x: 17, y: 0)
            put(&grid, head, x: 2, y: 3)
            put(&grid, eyeRows, x: 4, y: 9, opaque: true)
            put(&grid, eyeRows, x: 12, y: 9, opaque: true)
            put(&grid, hangBody, x: 2, y: 16)
            put(&grid, hangTail[frame.tail % 2], x: 9, y: 19)
        }
        return grid
    }

    /// `opaque` değilse '.' alttakini korur.
    private static func put(_ grid: inout Grid, _ layer: [String], x: Int, y: Int, opaque: Bool = false) {
        for (row, line) in layer.enumerated() {
            for (column, pixel) in line.enumerated() where opaque || pixel != "." {
                let gy = y + row, gx = x + column
                guard grid.indices.contains(gy), grid[gy].indices.contains(gx) else { continue }
                grid[gy][gx] = pixel
            }
        }
    }
}

/// Koci'yi SwiftUI'yi her karede yeniden değerlendirmeden çizer. Kendi zamanlayıcısı kareyi hesaplar,
/// yalnızca kare değişince katmanın görselini değiştirir; görünüm ağacının geri kalanı uyanmaz.
struct KociSpriteView: NSViewRepresentable {
    let pose: KociSprite.Pose
    /// Bir pikselin nokta cinsinden boyu; Retina'da 0.5'in katları keskin kalır.
    let pixel: CGFloat
    /// O andaki kare, dikey sıçrama (piksel) ve bir sonraki kareye kadar beklenecek süre.
    let source: (Date) -> (frame: KociSprite.Frame, bob: CGFloat, interval: TimeInterval)

    func makeNSView(context: Context) -> KociLayerView {
        KociLayerView(pixel: pixel)
    }

    func updateNSView(_ view: KociLayerView, context: Context) {
        view.source = source
        view.refresh()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: KociLayerView, context: Context) -> CGSize? {
        let size = KociSprite.size(of: pose)
        return CGSize(width: CGFloat(size.columns) * pixel, height: CGFloat(size.rows) * pixel)
    }
}

final class KociLayerView: NSView {
    var source: ((Date) -> (frame: KociSprite.Frame, bob: CGFloat, interval: TimeInterval))?

    private let pixel: CGFloat
    private var shown: (frame: KociSprite.Frame, bob: CGFloat)?
    private var timer: Timer?
    private var interval: TimeInterval = 0

    init(pixel: CGFloat) {
        self.pixel = pixel
        super.init(frame: .zero)
        wantsLayer = true
        // Büyütürken yumuşatma olmasın; pikseller keskin kalsın.
        layer?.magnificationFilter = .nearest
        layer?.contentsGravity = .resize
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) kullanılmıyor") }

    /// Tıklamalar SwiftUI'deki hareketlere gitsin.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            timer?.invalidate()
            timer = nil
            interval = 0
        } else {
            refresh()
        }
    }

    func refresh() {
        guard window != nil, let source else { return }
        let (frame, bob, nextInterval) = source(.now)
        if shown?.frame != frame || shown?.bob != bob {
            shown = (frame, bob)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer?.contents = KociSprite.image(frame)
            // Katman y ekseni yukarı doğru; sıçrama (eksi) yukarı demek.
            layer?.transform = CATransform3DMakeTranslation(0, -bob * pixel, 0)
            CATransaction.commit()
        }
        guard nextInterval != interval else { return }
        interval = nextInterval
        timer?.invalidate()
        let timer = Timer(timeInterval: nextInterval, repeats: true) { [weak self] _ in self?.refresh() }
        timer.tolerance = nextInterval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
