import AppKit
import SwiftUI

/// Hesap makinesi sekmesi: solda geçmiş ve ifade/sonuç, sağda tuş takımı.
/// Panel odaktayken klavyeyle de yazılabilir (rakamlar, + - * / %, ( ), Enter, Sil, Esc).
struct CalculatorView: View {
    @State private var calculator = Calculator()
    @State private var copied = false
    @FocusState private var isFocused: Bool

    private static let keys: [[CalculatorKey]] = [
        [.digit("7"), .digit("8"), .digit("9"), .op("÷"), .clear],
        [.digit("4"), .digit("5"), .digit("6"), .op("×"), .backspace],
        [.digit("1"), .digit("2"), .digit("3"), .op("−"), .percent],
        [.negate, .digit("0"), .comma, .op("+"), .equals],
    ]

    var body: some View {
        HStack(spacing: 12) {
            display
            keypad
                .frame(width: 250)
        }
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onKeyPress(phases: .down) { press in
            guard let key = CalculatorKey(press) else { return .ignored }
            calculator.press(key)
            return .handled
        }
    }

    private var display: some View {
        VStack(alignment: .trailing, spacing: 4) {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .trailing, spacing: 2) {
                        ForEach(calculator.history) { entry in
                            Button { calculator.recall(entry) } label: {
                                Text("\(entry.expression) = \(entry.result)")
                                    .font(.system(size: 10).monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.head)
                            }
                            .buttonStyle(.plain)
                            .help("Sonucu ifadeye al")
                            .id(entry.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .onChange(of: calculator.history.last?.id) { _, id in
                    if let id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
                }
            }
            .frame(maxHeight: .infinity)

            Text(calculator.expression.isEmpty ? " " : calculator.expression)
                .font(.system(size: 13, design: .rounded).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)

            Button(action: copyResult) {
                HStack(spacing: 6) {
                    if copied {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.green)
                            .transition(.scale.combined(with: .opacity))
                    }
                    Text(calculator.preview ?? "0")
                        .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .contentTransition(.numericText())
                }
            }
            .buttonStyle(.plain)
            .help("Sonucu kopyala")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
        .animation(.snappy(duration: 0.2), value: calculator.preview)
    }

    private var keypad: some View {
        Grid(horizontalSpacing: 5, verticalSpacing: 5) {
            ForEach(Self.keys.indices, id: \.self) { row in
                GridRow {
                    ForEach(Self.keys[row], id: \.self) { key in
                        KeyButton(key: key) {
                            isFocused = true
                            calculator.press(key)
                        }
                    }
                }
            }
        }
    }

    private func copyResult() {
        guard let result = calculator.preview else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result, forType: .string)
        withAnimation(.snappy) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.snappy) { copied = false }
        }
    }
}

private struct KeyButton: View {
    let key: CalculatorKey
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Group {
                if let symbol = key.symbol {
                    Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                } else {
                    Text(key.label).font(.system(size: 15, weight: .medium, design: .rounded))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(key == .equals ? .black : .white)
            .background(RoundedRectangle(cornerRadius: 8).fill(fill))
            .contentShape(Rectangle())
        }
        .buttonStyle(KeyPressStyle())
        .onHover { isHovering = $0 }
    }

    private var fill: Color {
        switch key {
        case .equals: return .white.opacity(isHovering ? 1 : 0.88)
        case .op: return .orange.opacity(isHovering ? 0.75 : 0.6)
        case .digit, .comma: return .white.opacity(isHovering ? 0.16 : 0.1)
        default: return .white.opacity(isHovering ? 0.12 : 0.06)
        }
    }
}

private struct KeyPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.snappy(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Model

enum CalculatorKey: Hashable {
    case digit(Character)
    case op(Character)
    case comma, percent, negate, clear, backspace, equals
    case paren(Character)

    var label: String {
        switch self {
        case .digit(let c), .op(let c), .paren(let c): String(c)
        case .comma: ","
        case .percent: "%"
        case .negate: "±"
        case .clear: "C"
        case .backspace: "⌫"
        case .equals: "="
        }
    }

    var symbol: String? {
        switch self {
        case .backspace: "delete.left"
        case .negate: "plus.forwardslash.minus"
        case .percent: "percent"
        default: nil
        }
    }

    init?(_ press: KeyPress) {
        switch press.key {
        case .return: self = .equals; return
        case .delete, .deleteForward: self = .backspace; return
        case .escape: self = .clear; return
        default: break
        }
        guard press.modifiers.subtracting([.shift, .numericPad]).isEmpty,
              let c = press.characters.first else { return nil }
        switch c {
        case "0"..."9": self = .digit(c)
        case ",", ".": self = .comma
        case "+": self = .op("+")
        case "-": self = .op("−")
        case "*", "x", "X": self = .op("×")
        case "/", ":": self = .op("÷")
        case "%": self = .percent
        case "(", ")": self = .paren(c)
        case "=": self = .equals
        case "c", "C": self = .clear
        default: return nil
        }
    }
}

@Observable
final class Calculator {
    struct Entry: Identifiable {
        let id = UUID()
        let expression: String
        let result: String
    }

    private(set) var expression = ""
    private(set) var history: [Entry] = []
    /// "=" sonrası: yeni rakam ifadeyi sıfırlar, işleç sonuçtan devam eder.
    private var justEvaluated = false

    private static let operators: Set<Character> = ["+", "−", "×", "÷"]

    /// Yazarken anlık sonuç; sondaki işleç ve açık parantezler yok sayılır.
    var preview: String? {
        var text = expression
        while let last = text.last, Self.operators.contains(last) || last == "(" { text.removeLast() }
        guard !text.isEmpty, let value = Self.evaluate(text) else { return expression.isEmpty ? nil : "—" }
        return Self.format(value, grouped: true)
    }

    func press(_ key: CalculatorKey) {
        switch key {
        case .digit(let c):
            if justEvaluated { expression = "" }
            if expression.last == ")" || expression.last == "%" { expression.append("×") }
            // Baştaki gereksiz sıfırı değiştir ("0" → "7", ama "0,0" kalsın).
            if currentNumber == "0" { expression.removeLast() }
            expression.append(c)
        case .comma:
            if justEvaluated { expression = "" }
            guard !currentNumber.contains(",") else { break }
            if currentNumber.isEmpty { expression.append("0") }
            expression.append(",")
        case .op(let c):
            if expression.isEmpty {
                if c == "−" { expression = "−" }
                break
            }
            if let last = expression.last, Self.operators.contains(last) {
                expression.removeLast()
                if expression.isEmpty || expression.last == "(" {
                    if c == "−" { expression.append(c) }
                    break
                }
            }
            if expression.last == "," { expression.removeLast() }
            expression.append(c)
        case .percent:
            guard let last = expression.last, last.isNumber || last == ")" else { break }
            expression.append("%")
        case .paren(let c):
            if justEvaluated && c == "(" { expression = "" }
            if c == "(" {
                if let last = expression.last, last.isNumber || last == ")" || last == "%" { expression.append("×") }
                expression.append("(")
            } else {
                let open = expression.filter { $0 == "(" }.count - expression.filter { $0 == ")" }.count
                guard open > 0, let last = expression.last, !Self.operators.contains(last), last != "(" else { break }
                expression.append(")")
            }
        case .negate:
            negateCurrentNumber()
        case .clear:
            expression = ""
        case .backspace:
            if justEvaluated { expression = "" } else if !expression.isEmpty { expression.removeLast() }
        case .equals:
            evaluateExpression()
            return
        }
        justEvaluated = false
    }

    func recall(_ entry: Entry) {
        expression = entry.result.replacingOccurrences(of: ".", with: "")
        justEvaluated = true
    }

    private func evaluateExpression() {
        var text = expression
        while let last = text.last, Self.operators.contains(last) || last == "(" { text.removeLast() }
        let open = text.filter { $0 == "(" }.count - text.filter { $0 == ")" }.count
        if open > 0 { text += String(repeating: ")", count: open) }
        // Sıfıra bölme gibi tanımsız sonuçlar ifadeye yazılmaz; önizleme "Tanımsız" gösterir.
        guard !text.isEmpty, let value = Self.evaluate(text), value.isFinite else { return }
        let raw = Self.format(value, grouped: false)
        if text != raw {
            history.append(Entry(expression: text, result: Self.format(value, grouped: true)))
            if history.count > 30 { history.removeFirst() }
        }
        expression = raw
        justEvaluated = true
    }

    /// İfadenin sonundaki sayı (rakamlar ve virgül).
    private var currentNumber: Substring {
        expression[numberStart...]
    }

    private var numberStart: String.Index {
        var index = expression.endIndex
        while index > expression.startIndex {
            let previous = expression.index(before: index)
            guard expression[previous].isNumber || expression[previous] == "," else { break }
            index = previous
        }
        return index
    }

    private func negateCurrentNumber() {
        let start = numberStart
        guard start < expression.endIndex else {
            if expression.isEmpty { expression = "−" } else if expression == "−" { expression = "" }
            return
        }
        // Tekli eksi: başta ya da işleç/parantezden hemen sonra gelen "−".
        if start > expression.startIndex {
            let minus = expression.index(before: start)
            if expression[minus] == "−" {
                let isUnary = minus == expression.startIndex
                    || Self.operators.contains(expression[expression.index(before: minus)])
                    || expression[expression.index(before: minus)] == "("
                if isUnary {
                    expression.remove(at: minus)
                    justEvaluated = false
                    return
                }
            }
        }
        expression.insert("−", at: start)
        justEvaluated = false
    }

    // MARK: Biçimlendirme

    private static let groupedFormatter = makeFormatter(grouped: true)
    private static let rawFormatter = makeFormatter(grouped: false)

    private static func makeFormatter(grouped: Bool) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = grouped
        formatter.maximumFractionDigits = 10
        formatter.minusSign = "−"
        return formatter
    }

    static func format(_ value: Double, grouped: Bool) -> String {
        guard value.isFinite else { return "Tanımsız" }
        if abs(value) >= 1e15 || (abs(value) < 1e-9 && value != 0) {
            return String(format: "%.6g", value).replacingOccurrences(of: ".", with: ",")
                .replacingOccurrences(of: "-", with: "−")
        }
        let formatter = grouped ? groupedFormatter : rawFormatter
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    // MARK: Değerlendirme

    /// Basit özyinelemeli ayrıştırıcı: + − × ÷, sonek %, tekli eksi ve parantez.
    static func evaluate(_ text: String) -> Double? {
        var parser = Parser(chars: Array(text))
        guard let value = parser.expression(), parser.index == parser.chars.count else { return nil }
        return value
    }

    private struct Parser {
        let chars: [Character]
        var index = 0

        private var current: Character? { index < chars.count ? chars[index] : nil }

        mutating func expression() -> Double? {
            guard var value = term() else { return nil }
            while let c = current, c == "+" || c == "−" {
                index += 1
                guard let rhs = term() else { return nil }
                value = c == "+" ? value + rhs : value - rhs
            }
            return value
        }

        private mutating func term() -> Double? {
            guard var value = factor() else { return nil }
            while let c = current, c == "×" || c == "÷" {
                index += 1
                guard let rhs = factor() else { return nil }
                value = c == "×" ? value * rhs : value / rhs
            }
            return value
        }

        private mutating func factor() -> Double? {
            if current == "−" {
                index += 1
                return factor().map { -$0 }
            }
            guard var value = primary() else { return nil }
            while current == "%" {
                index += 1
                value /= 100
            }
            return value
        }

        private mutating func primary() -> Double? {
            if current == "(" {
                index += 1
                let value = expression()
                guard current == ")" else { return nil }
                index += 1
                return value
            }
            let start = index
            while let c = current, c.isNumber || c == "," { index += 1 }
            guard index > start else { return nil }
            return Double(String(chars[start..<index]).replacingOccurrences(of: ",", with: "."))
        }
    }
}
