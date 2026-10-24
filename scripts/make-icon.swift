// Notchland uygulama ikonunu çizer: gün batımında tepeler ve üstte, içinde canlı etkinlik olan çentik.
// Kullanım: swift scripts/make-icon.swift <çıktı.png>   (1024×1024)
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.dropFirst().first ?? "icon.png"

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func gradient(_ stops: [(UInt32, CGFloat)], alpha: CGFloat = 1) -> CGGradient {
    CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: stops.map { color($0.0, alpha) } as CFArray,
        locations: stops.map(\.1)
    )!
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(
    data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!
// Yukarıdan aşağı koordinatlarla çiz.
ctx.translateBy(x: 0, y: size)
ctx.scaleBy(x: 1, y: -1)

// macOS ikon ızgarası: 824'lük gövde, 100 pay.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

// Gölge
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 12), blur: 28, color: color(0x000000, 0.35))
ctx.addPath(bodyPath)
ctx.setFillColor(color(0x1B1747))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(bodyPath)
ctx.clip()

// Gökyüzü
ctx.drawLinearGradient(
    gradient([(0x1E1B4F, 0), (0x3D2A80, 0.35), (0x9A4FB0, 0.6), (0xFF9468, 0.82), (0xFFC27A, 1)]),
    start: CGPoint(x: 0, y: 100), end: CGPoint(x: 0, y: 760), options: [.drawsAfterEndLocation]
)

// Yıldızlar
var seed: UInt64 = 7
func random() -> CGFloat {
    seed = seed &* 6364136223846793005 &+ 1442695040888963407
    return CGFloat(seed >> 33) / CGFloat(1 << 31)
}
for _ in 0..<38 {
    let point = CGPoint(x: 120 + random() * 784, y: 240 + random() * 230)
    let radius = 1.5 + random() * 3
    ctx.setFillColor(color(0xFFFFFF, 0.25 + random() * 0.5))
    ctx.fillEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
}

// Güneş ve parıltısı
let sun = CGPoint(x: 512, y: 700)
ctx.drawRadialGradient(
    CGGradient(colorsSpace: space, colors: [color(0xFFD9A0, 0.75), color(0xFF9468, 0)] as CFArray, locations: [0, 1])!,
    startCenter: sun, startRadius: 120, endCenter: sun, endRadius: 360, options: []
)
ctx.drawRadialGradient(
    gradient([(0xFFF1C9, 0), (0xFFC46B, 0.7), (0xFF8A5B, 1)]),
    startCenter: sun, startRadius: 0, endCenter: sun, endRadius: 150, options: []
)

// Tepeler: arkadan öne koyulaşan katmanlar. Noktalar: başlangıç, sonra (kontrol, uç) çiftleri.
func hill(_ points: [CGPoint], _ fill: CGGradient, top: CGFloat) {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 0, y: size))
    path.addLine(to: points[0])
    for index in stride(from: 1, to: points.count - 1, by: 2) {
        path.addQuadCurve(to: points[index + 1], control: points[index])
    }
    path.addLine(to: CGPoint(x: size, y: size))
    path.closeSubpath()
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(fill, start: CGPoint(x: 0, y: top), end: CGPoint(x: 0, y: size), options: [])
    ctx.restoreGState()
}

hill(
    [CGPoint(x: 0, y: 690), CGPoint(x: 250, y: 600), CGPoint(x: 470, y: 700),
     CGPoint(x: 700, y: 790), CGPoint(x: 1024, y: 640)],
    gradient([(0x7A3F9E, 0), (0x4A2A7A, 1)]), top: 600
)
hill(
    [CGPoint(x: 0, y: 790), CGPoint(x: 330, y: 700), CGPoint(x: 600, y: 790),
     CGPoint(x: 820, y: 860), CGPoint(x: 1024, y: 740)],
    gradient([(0x3F2470, 0), (0x24164A, 1)]), top: 700
)
hill(
    [CGPoint(x: 0, y: 880), CGPoint(x: 260, y: 820), CGPoint(x: 560, y: 880),
     CGPoint(x: 820, y: 930), CGPoint(x: 1024, y: 840)],
    gradient([(0x1E1240, 0), (0x120A2A, 1)]), top: 820
)

// Çentiğin altından yayılan ışık
let glowCenter = CGPoint(x: 512, y: 215)
ctx.drawRadialGradient(
    CGGradient(colorsSpace: space, colors: [color(0xB79CFF, 0.45), color(0xB79CFF, 0)] as CFArray, locations: [0, 1])!,
    startCenter: glowCenter, startRadius: 0, endCenter: glowCenter, endRadius: 300, options: []
)

// Çentik: üst kenara yapışık, alt köşeleri yuvarlak, üst köşeleri dışa kıvrık.
let notchWidth: CGFloat = 420, notchHeight: CGFloat = 118
let flare: CGFloat = 30, bottomRadius: CGFloat = 52
let left = 512 - notchWidth / 2, right = 512 + notchWidth / 2
let top: CGFloat = 100, bottom = top + notchHeight
let notch = CGMutablePath()
notch.move(to: CGPoint(x: left - flare, y: top))
notch.addLine(to: CGPoint(x: right + flare, y: top))
notch.addQuadCurve(to: CGPoint(x: right, y: top + flare), control: CGPoint(x: right, y: top))
notch.addLine(to: CGPoint(x: right, y: bottom - bottomRadius))
notch.addArc(tangent1End: CGPoint(x: right, y: bottom), tangent2End: CGPoint(x: right - bottomRadius, y: bottom), radius: bottomRadius)
notch.addLine(to: CGPoint(x: left + bottomRadius, y: bottom))
notch.addArc(tangent1End: CGPoint(x: left, y: bottom), tangent2End: CGPoint(x: left, y: bottom - bottomRadius), radius: bottomRadius)
notch.addLine(to: CGPoint(x: left, y: top + flare))
notch.addQuadCurve(to: CGPoint(x: left - flare, y: top), control: CGPoint(x: left, y: top))
notch.closeSubpath()

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 30, color: color(0x000000, 0.55))
ctx.addPath(notch)
ctx.setFillColor(color(0x050409))
ctx.fillPath()
ctx.restoreGState()

// Canlı etkinlik: solda kapak, sağda ses dalgası.
let rowY = top + notchHeight / 2 + 4
let cover = CGRect(x: left + 46, y: rowY - 30, width: 60, height: 60)
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: cover, cornerWidth: 14, cornerHeight: 14, transform: nil))
ctx.clip()
ctx.drawLinearGradient(
    gradient([(0xFFC27A, 0), (0xFF6F7D, 0.55), (0x9A4FB0, 1)]),
    start: CGPoint(x: cover.minX, y: cover.minY), end: CGPoint(x: cover.maxX, y: cover.maxY), options: []
)
ctx.restoreGState()

let bars: [CGFloat] = [0.45, 0.85, 0.6, 1.0, 0.5]
let barWidth: CGFloat = 13, barGap: CGFloat = 9
var barX = right - 46 - CGFloat(bars.count) * barWidth - CGFloat(bars.count - 1) * barGap
for level in bars {
    let height = 62 * level
    let rect = CGRect(x: barX, y: rowY - height / 2, width: barWidth, height: height)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
    ctx.setFillColor(color(0xFFD9A0))
    ctx.fillPath()
    barX += barWidth + barGap
}

// Gövdenin iç kenarında ince parlaklık.
ctx.addPath(bodyPath)
ctx.setStrokeColor(color(0xFFFFFF, 0.12))
ctx.setLineWidth(3)
ctx.strokePath()
ctx.restoreGState()

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
