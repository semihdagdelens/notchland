import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Çark, çentiğin paneline sığmadığı için imlecin çevresinde açılan kendi panelinde durur.
private final class FormatWheelPanel: NSPanel {
    init(side: CGFloat) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: side, height: side),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar + 2
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
    }

    /// Esc ve yön tuşları için odak alır; uygulamayı etkinleştirmediğinden kapanınca odak öndeki uygulamaya döner.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@Observable
private final class FormatWheelModel {
    var sources: [URL] = []
    var targets: [FileFormat] = []
    var family: FormatFamily = .image
    var highlighted: Int?
    var isOpen = false
}

/// Dosya formatı değiştirici: kısayolu basılı tut, imleci bir dilime doğru kaydır, bırak.
/// Kısa basılırsa çark açık kalır; tıklamayla, yön tuşları ve Return ile seçilir, Esc kapatır.
final class FormatWheelController {
    /// Finder'da seçim yoksa kullanılacak dosyalar (panodaki son dosya veya görsel).
    var fallbackSources: () -> [URL] = { [] }
    /// Çark açılmadan hemen önce (notch kapansın).
    var onWillOpen: (() -> Void)?
    var onNotice: ((_ title: String, _ body: String) -> Void)?

    private(set) var isVisible = false

    private static let side: CGFloat = 460
    /// Bundan uzun basılırsa bırakmak seçim sayılır; kısa basış çarkı açık bırakır.
    private static let holdThreshold: TimeInterval = 0.3
    /// Göbek bölgesi: imleç buraya dönünce seçim kalkar, bırakmak vazgeçmek olur.
    private static let deadZone: CGFloat = 36

    private let model = FormatWheelModel()
    private var panel: FormatWheelPanel?
    private var monitors: [Any] = []
    private var pressedAt: Date?
    private var isResolving = false

    // MARK: - Açılış

    func hotKeyPressed() {
        if isVisible { return close() }
        guard !isResolving else { return }
        isResolving = true
        pressedAt = Date()
        let isFinderFront = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder"
        // osascript ilk kullanımda izin penceresini bekler; ana kuyruğu bloklamasın.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let selection = isFinderFront ? Self.finderSelection() : []
            DispatchQueue.main.async {
                guard let self else { return }
                self.isResolving = false
                self.open(selection.isEmpty ? self.fallbackSources() : selection)
            }
        }
    }

    func hotKeyReleased() {
        guard isVisible, let pressedAt, Date().timeIntervalSince(pressedAt) >= Self.holdThreshold else { return }
        confirm()
    }

    /// Çarkı verilen dosyalar için açar. Karışık seçimde ilk dosyanın ailesi kullanılır.
    func open(_ urls: [URL]) {
        guard !isVisible else { return }
        guard let first = urls.first else {
            onNotice?("Dönüştürülecek dosya yok", "Finder'da bir dosya seç, çentiğe sürükle ya da video bağlantısı kopyala")
            return
        }
        guard let family = FormatFamily(url: first) else {
            onNotice?("\(first.lastPathComponent) dönüştürülemiyor", "Bu dosya türü desteklenmiyor")
            return
        }
        let sources = urls.filter { FormatFamily(url: $0) == family }
        let targets = family.targets(for: sources)
        guard !targets.isEmpty else { return }

        onWillOpen?()
        model.sources = sources
        model.targets = targets
        model.family = family
        model.highlighted = nil

        let panel = panel ?? makePanel()
        panel.setFrameOrigin(Self.origin(forMouse: NSEvent.mouseLocation))
        panel.makeKeyAndOrderFront(nil)
        isVisible = true
        startMonitoring()
        withAnimation(.spring(response: 0.26, dampingFraction: 0.74)) { model.isOpen = true }
    }

    private func makePanel() -> FormatWheelPanel {
        let panel = FormatWheelPanel(side: Self.side)
        panel.contentView = NSHostingView(rootView: FormatWheelView(model: model))
        self.panel = panel
        return panel
    }

    /// Çark imlecin çevresinde açılır ki küçük bir hareket dilim seçsin; ekrandan taşmasın diye kenarlara yaslanır.
    private static func origin(forMouse mouse: NSPoint) -> NSPoint {
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let frame = screen?.visibleFrame ?? NSRect(origin: .zero, size: CGSize(width: side, height: side))
        return NSPoint(
            x: min(max(mouse.x - side / 2, frame.minX), frame.maxX - side),
            y: min(max(mouse.y - side / 2, frame.minY), frame.maxY - side)
        )
    }

    /// Finder'daki seçimin yolları; izin yoksa veya seçim yoksa boş.
    private static func finderSelection() -> [URL] {
        let script = """
        tell application "Finder" to set picked to selection as alias list
        set paths to ""
        repeat with item_ in picked
            set paths to paths & POSIX path of item_ & linefeed
        end repeat
        return paths
        """
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        let output = Pipe()
        task.standardOutput = output
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return [] }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).map { URL(fileURLWithPath: String($0)) }
    }

    // MARK: - Seçim

    private func startMonitoring() {
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: moves, handler: { [weak self] _ in self?.trackMouse() }) {
            monitors.append(global)
        }
        // Panelin dışına tıklamak vazgeçmektir.
        if let outside = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in self?.close() }) {
            monitors.append(outside)
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .leftMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            switch event.type {
            case .leftMouseDown:
                self.trackMouse()
                self.confirm()
                return nil
            case .keyDown:
                return self.handleKey(event) ? nil : event
            default:
                self.trackMouse()
                return event
            }
        }
        if let local { monitors.append(local) }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let count = model.targets.count
        switch Int(event.keyCode) {
        case kVK_Escape:
            close()
        case kVK_Return, kVK_ANSI_KeypadEnter:
            confirm()
        case kVK_RightArrow, kVK_DownArrow:
            highlight(((model.highlighted ?? -1) + 1) % count)
        case kVK_LeftArrow, kVK_UpArrow:
            highlight(((model.highlighted ?? 0) - 1 + count) % count)
        default:
            return false
        }
        return true
    }

    /// İmlecin çark merkezine göre yönü dilimi belirler; panelin dışına çıkmak seçimi bozmaz.
    private func trackMouse() {
        guard let panel, isVisible else { return }
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - panel.frame.midX
        let dy = mouse.y - panel.frame.midY
        guard hypot(dx, dy) > Self.deadZone else { return highlight(nil) }
        let step = 2 * Double.pi / Double(model.targets.count)
        // İlk dilim tepede ortalanır; açı saat yönünde artar.
        let angle = atan2(Double(dx), Double(dy))
        let index = Int((angle / step).rounded())
        highlight((index + model.targets.count) % model.targets.count)
    }

    private func highlight(_ index: Int?) {
        guard index != model.highlighted else { return }
        withAnimation(.spring(response: 0.16, dampingFraction: 0.72)) { model.highlighted = index }
        if index != nil, AppSettings.shared.hapticFeedback {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    private func confirm() {
        guard let index = model.highlighted else { return close() }
        let format = model.targets[index]
        let sources = model.sources
        let family = model.family
        close()
        convert(sources, to: format, family: family)
    }

    private func close() {
        guard isVisible else { return }
        isVisible = false
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        withAnimation(.easeOut(duration: 0.1)) { model.isOpen = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.11) { [weak self] in
            guard let self, !self.isVisible else { return }
            self.panel?.orderOut(nil)
        }
    }

    // MARK: - Dönüştürme

    private func convert(_ sources: [URL], to format: FileFormat, family: FormatFamily) {
        // Video ve ses uzun sürebilir; çark onları beklemez, sonuç çentikte bildirilir.
        if family == .download {
            onNotice?("\(format.title) iniyor…", Self.describe(sources))
        } else if family == .video || family == .audio {
            onNotice?("\(format.title) hazırlanıyor…", Self.describe(sources))
        }
        Task { @MainActor in
            var outputs: [URL] = []
            var failure: Error?
            for source in sources {
                do {
                    outputs.append(try await FormatConverter.convert(source, to: format, onProgress: progress(for: sources)))
                } catch {
                    failure = error
                }
            }
            if let failure {
                let done = outputs.isEmpty ? "" : "\(outputs.count) tanesi oldu · "
                onNotice?("\(Self.describe(sources)) dönüştürülemedi", done + failure.localizedDescription)
            } else if let first = outputs.first {
                let folder = FileManager.default.displayName(atPath: first.deletingLastPathComponent().path)
                onNotice?(outputs.count == 1 ? "\(first.lastPathComponent) hazır" : "\(outputs.count) \(format.title) dosyası hazır", folder)
            }
        }
    }

    /// Her %10'da bir bildirir: bildirim kaybolmadan yenilenir, ama çentik sürekli titremez.
    private func progress(for sources: [URL]) -> (String, Int) -> Void {
        var lastStep = -1
        var lastLabel = ""
        return { [weak self] label, percent in
            let step = percent / 10
            guard step != lastStep || label != lastLabel else { return }
            lastStep = step
            lastLabel = label
            DispatchQueue.main.async {
                self?.onNotice?("\(label) iniyor · %\(step * 10)", Self.describe(sources))
            }
        }
    }

    private static func describe(_ sources: [URL]) -> String {
        sources.count == 1 ? sources[0].wheelName : "\(sources.count) dosya"
    }
}

private extension URL {
    /// Bağlantının son parçası ("watch") bir şey anlatmaz; site adı gösterilir.
    var wheelName: String { isFileURL ? lastPathComponent : (host ?? absoluteString) }
}

// MARK: - Görünüm

private struct FormatWheelView: View {
    let model: FormatWheelModel

    private static let innerRadius: CGFloat = 84
    private static let outerRadius: CGFloat = 196

    private var tint: Color {
        switch model.family {
        case .image: Color(red: 0.62, green: 0.42, blue: 1)
        case .video: Color(red: 1, green: 0.42, blue: 0.38)
        case .audio: Color(red: 0.25, green: 0.85, blue: 0.62)
        case .document: Color(red: 0.32, green: 0.6, blue: 1)
        case .pdf: Color(red: 1, green: 0.62, blue: 0.22)
        case .download: Color(red: 1, green: 0.27, blue: 0.3)
        }
    }

    var body: some View {
        ZStack {
            // Arkadaki ekranı karartarak dikkati çarka toplar.
            RadialGradient(
                colors: [.black.opacity(0.6), .black.opacity(0.45), .clear],
                center: .center, startRadius: 120, endRadius: 230
            )
            ForEach(Array(model.targets.enumerated()), id: \.element) { index, format in
                slice(format, index: index)
            }
            hub
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scaleEffect(model.isOpen ? 1 : 0.72)
        .opacity(model.isOpen ? 1 : 0)
        .environment(\.colorScheme, .dark)
    }

    private func slice(_ format: FileFormat, index: Int) -> some View {
        let count = model.targets.count
        let step = 360 / Double(count)
        let center = Double(index) * step
        let isSelected = model.highlighted == index
        let radians = center * .pi / 180
        let shape = WheelSlice(
            centerAngle: center, width: step - (count > 1 ? 2.5 : 0),
            innerRadius: Self.innerRadius, outerRadius: Self.outerRadius
        )
        let labelRadius = (Self.innerRadius + Self.outerRadius) / 2
        // Seçili dilim merkezden dışarı doğru bir adım atar.
        let push: CGFloat = isSelected ? 8 : 0

        return ZStack {
            shape.fill(isSelected ? AnyShapeStyle(tint.opacity(0.92)) : AnyShapeStyle(Color.black.opacity(0.78)))
            shape.stroke(Color.white.opacity(isSelected ? 0.75 : 0.12), lineWidth: isSelected ? 1.5 : 1)
            VStack(spacing: 5) {
                Image(systemName: format.symbol)
                    .font(.system(size: isSelected ? 24 : 20, weight: .semibold))
                    .frame(height: 28)
                Text(format.title)
                    .font(.system(size: isSelected ? 14 : 12, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white.opacity(isSelected ? 1 : 0.72))
            .offset(x: labelRadius * sin(radians), y: -labelRadius * cos(radians))
        }
        .offset(x: push * sin(radians), y: -push * cos(radians))
        .zIndex(isSelected ? 1 : 0)
    }

    /// Göbek: kaynak dosya ve seçili hedef.
    private var hub: some View {
        VStack(spacing: 3) {
            if let first = model.sources.first {
                Group {
                    if first.isFileURL {
                        Image(nsImage: FileIcon.icon(forFile: first.path)).resizable().scaledToFit()
                    } else {
                        Image(systemName: "arrow.down.circle.fill").resizable().scaledToFit().foregroundStyle(tint)
                    }
                }
                .frame(width: 30, height: 30)
                Text(model.sources.count == 1 ? first.wheelName : "\(model.sources.count) dosya")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let index = model.highlighted, model.targets.indices.contains(index) {
                let format = model.targets[index]
                Text("→ \(format.title)")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(tint)
                Text(format.hint)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            } else {
                Text("Bir dilim seç")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Text("Ortada bırakırsan vazgeçer")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 14)
        .frame(width: (Self.innerRadius - 6) * 2, height: (Self.innerRadius - 6) * 2)
        .background(Circle().fill(Color.black.opacity(0.88)))
        .overlay(Circle().strokeBorder(tint.opacity(model.highlighted == nil ? 0.25 : 0.8), lineWidth: 1.5))
    }
}

/// Merkezi çerçevenin ortasında olan halka dilimi; açı tepeden saat yönünde derece cinsinden.
private struct WheelSlice: Shape {
    let centerAngle: Double
    let width: Double
    let innerRadius: CGFloat
    let outerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        // SwiftUI'de 0° sağı gösterir; tepeye almak için 90° geri.
        let start = Angle.degrees(centerAngle - width / 2 - 90)
        let end = Angle.degrees(centerAngle + width / 2 - 90)
        var path = Path()
        path.addArc(center: center, radius: outerRadius, startAngle: start, endAngle: end, clockwise: false)
        path.addArc(center: center, radius: innerRadius, startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }
}
