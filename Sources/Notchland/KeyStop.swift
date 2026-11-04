import SwiftUI

/// Klavyeyle gezinmede ulaşılan bir düğme ya da liste öğesi. Duraklar satırlara dizilir:
/// ↓ ↑ satır, ← → satır içinde durak değiştirir; satırın ucunda → sonraki sekmeye geçer.
struct KeyStop {
    let id: String
    let tab: NotchState.Tab
    let row: Int
    let order: Int
    /// Uzun (tembel) listeler tek durak sayılır; bu eksendeki oklar `keyCommand` ile listeye gider.
    var contentAxis: Axis?
    /// Satırın ucunda sekme değiştirmez: öğeler arasında gezerken sayfadan kazara çıkılmasın.
    var clampsAtEdge = false
    var action: () -> Void = {}
    var onCopy: (() -> Void)?
    var onDelete: (() -> Void)?

    static func id(_ tab: NotchState.Tab, _ name: String) -> String { "\(tab).\(name)" }
    /// Uzun listenin durağı.
    static func contentID(_ tab: NotchState.Tab) -> String { id(tab, "items") }
}

/// Görünen durakları görünümlerden `NotchState`'e taşır.
struct KeyStopsKey: PreferenceKey {
    struct Value: Equatable {
        var stops: [KeyStop] = []
        /// Eylemler karşılaştırılamaz; her güncelleme son eylemleri taşısın diye hep farklı sayılır.
        static func == (lhs: Value, rhs: Value) -> Bool { false }
    }

    static let defaultValue = Value()

    static func reduce(value: inout Value, nextValue: () -> Value) {
        value.stops += nextValue().stops
    }
}

private struct KeyStopModifier: ViewModifier {
    let state: NotchState
    let stop: KeyStop
    let outset: CGFloat

    func body(content: Content) -> some View {
        content
            .overlay {
                if state.isKeyFocused(stop.id) {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
                        .padding(-outset)
                        .allowsHitTesting(false)
                }
            }
            .id(stop.id)
            // `preference` alt görünümlerin duraklarını ezerdi; üzerine eklenir.
            .transformPreference(KeyStopsKey.self) { $0.stops.append(stop) }
    }
}

extension View {
    /// Görünümü klavyeyle ulaşılan bir durak yapar. Kaydırılan listelerde çerçeve kırpılmasın diye `outset: 0`.
    func keyStop(
        _ state: NotchState, _ tab: NotchState.Tab, _ name: String, row: Int = 0, order: Int, outset: CGFloat = 3,
        clampsAtEdge: Bool = false, onCopy: (() -> Void)? = nil, onDelete: (() -> Void)? = nil,
        action: @escaping () -> Void
    ) -> some View {
        modifier(KeyStopModifier(
            state: state,
            stop: KeyStop(
                id: KeyStop.id(tab, name), tab: tab, row: row, order: order, clampsAtEdge: clampsAtEdge,
                action: action, onCopy: onCopy, onDelete: onDelete
            ),
            outset: outset
        ))
    }

    /// Uzun listeyi, seçimi kendi yöneten tek durak olarak kaydeder (liste boşsa `isEnabled: false`).
    func keyContent(_ tab: NotchState.Tab, row: Int, axis: Axis, isEnabled: Bool = true) -> some View {
        let stop = KeyStop(id: KeyStop.contentID(tab), tab: tab, row: row, order: 0, contentAxis: axis)
        return transformPreference(KeyStopsKey.self) { if isEnabled { $0.stops.append(stop) } }
    }

    /// Kaydırılan listede klavyeyle seçilen durağı görünür tutar.
    func scrollsToKeyFocus(_ state: NotchState, _ proxy: ScrollViewProxy) -> some View {
        onChange(of: state.focusedKeyStop) { _, id in
            guard let id else { return }
            withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .center) }
        }
    }
}

extension NotchState {
    private var currentKeyStops: [KeyStop] { keyStops.filter { $0.tab == tab } }

    var focusedStop: KeyStop? { currentKeyStops.first { $0.id == focusedKeyStop } }

    func isKeyFocused(_ id: String) -> Bool { isKeyboardActive && focusedKeyStop == id }

    /// Satır değiştirir; ilk satırdan yukarı çıkınca odak yeniden sekmelere döner.
    func moveKeyFocus(rowBy offset: Int) {
        let stops = currentKeyStops
        let rows = Set(stops.map(\.row)).sorted()
        guard let current = focusedStop, let index = rows.firstIndex(of: current.row) else {
            if offset > 0 { focusedKeyStop = stops.filter { $0.row == rows.first }.min { $0.order < $1.order }?.id }
            return
        }
        let target = index + offset
        guard rows.indices.contains(target) else {
            if target < 0 { focusedKeyStop = nil }
            return
        }
        focusedKeyStop = stops.filter { $0.row == rows[target] }
            .min { abs($0.order - current.order) < abs($1.order - current.order) }?.id
    }

    /// Satır içinde komşu durağa geçer; satırın ucundaysa false döner.
    @discardableResult
    func moveKeyFocus(orderBy offset: Int) -> Bool {
        guard let current = focusedStop else { return false }
        let row = currentKeyStops.filter { $0.row == current.row }.sorted { $0.order < $1.order }
        guard let index = row.firstIndex(where: { $0.id == current.id }), row.indices.contains(index + offset) else { return false }
        focusedKeyStop = row[index + offset].id
        return true
    }
}
