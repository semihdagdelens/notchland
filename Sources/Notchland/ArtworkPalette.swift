import AppKit
import SwiftUI

/// Kapak görselinden notch arka planı için baskın, canlı bir renk çıkarır.
enum ArtworkPalette {
    /// Ana kuyruğu bloklamaz; sonuç ana kuyrukta döner.
    static func dominantColor(of image: NSImage, completion: @escaping (NSColor?) -> Void) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            completion(nil)
            return
        }
        DispatchQueue.global(qos: .utility).async {
            let color = dominantColor(of: cgImage)
            DispatchQueue.main.async { completion(color) }
        }
    }

    /// Görseli 24×24'e küçültür, pikselleri ton/doygunluk kovalarına ayırır ve
    /// en çok ağırlık toplayan kovanın ortalamasını alır. Siyaha, beyaza ve griye yakın
    /// pikseller (çoğu kapaktaki zemin ve yazılar) ağırlıkta geri planda kalır.
    static func dominantColor(of image: CGImage) -> NSColor? {
        let side = 24
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(
            data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))

        struct Bucket { var weight = 0.0; var r = 0.0; var g = 0.0; var b = 0.0 }
        var buckets: [Int: Bucket] = [:]
        var fallback = Bucket()

        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[i]) / 255, g = Double(pixels[i + 1]) / 255, b = Double(pixels[i + 2]) / 255
            fallback.weight += 1; fallback.r += r; fallback.g += g; fallback.b += b

            let color = NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
            var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0
            color.getHue(&h, saturation: &s, brightness: &v, alpha: nil)
            guard v > 0.12, s > 0.18 else { continue }
            // 12 ton × 3 doygunluk kovası.
            let key = Int(h * 12) % 12 * 3 + min(Int(s * 3), 2)
            // Doygun ve orta parlaklıktaki pikseller daha "kapağın rengi"dir.
            let weight = Double(s) * (1 - abs(Double(v) - 0.6))
            buckets[key, default: Bucket()].weight += weight
            buckets[key]!.r += r * weight
            buckets[key]!.g += g * weight
            buckets[key]!.b += b * weight
        }

        let chosen: Bucket
        if let best = buckets.values.max(by: { $0.weight < $1.weight }), best.weight > 1.5 {
            chosen = Bucket(weight: 1, r: best.r / best.weight, g: best.g / best.weight, b: best.b / best.weight)
        } else if fallback.weight > 0 {
            // Neredeyse renksiz kapak (siyah-beyaz vb.): ortalama ton.
            chosen = Bucket(weight: 1, r: fallback.r / fallback.weight, g: fallback.g / fallback.weight,
                            b: fallback.b / fallback.weight)
        } else {
            return nil
        }
        return normalized(NSColor(srgbRed: chosen.r, green: chosen.g, blue: chosen.b, alpha: 1))
    }

    /// Beyaz yazının her zaman okunacağı kadar koyu, ama rengin seçilebileceği kadar canlı.
    private static func normalized(_ color: NSColor) -> NSColor {
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &v, alpha: nil)
        let saturation = min(s * 1.1, 0.85)
        let brightness = min(max(v, 0.35), 0.55)
        return NSColor(hue: h, saturation: saturation, brightness: brightness, alpha: 1)
    }
}

/// Notch şeklinin üstüne, yukarıdan aşağı solan kapak rengi katmanı. Renk değişince yumuşakça geçer.
/// Açılışta şekil büyük ölçüde genişledikten sonra belirir; kapanışta şekil küçülmeden önce söner.
struct ArtworkTint<S: Shape>: View {
    let color: NSColor?
    let isVisible: Bool
    let shape: S

    var body: some View {
        colorLayer
            .opacity(isVisible ? 1 : 0)
            // Açılış yayı (~0.42 sn) yarılanınca renk gelmeye başlasın.
            .animation(isVisible ? .easeOut(duration: 0.25).delay(0.1) : .easeOut(duration: 0.1), value: isVisible)
            .allowsHitTesting(false)
    }

    private var colorLayer: some View {
        ZStack {
            if let color {
                let tint = Color(nsColor: color)
                shape
                    .fill(LinearGradient(
                        stops: [
                            .init(color: tint.opacity(0.65), location: 0),
                            .init(color: tint.opacity(0.3), location: 0.55),
                            .init(color: tint.opacity(0.08), location: 1),
                        ],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .id(color)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.6), value: color)
    }
}
