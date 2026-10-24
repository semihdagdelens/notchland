import AppKit
import IOBluetooth

/// Bluetooth kulaklık bağlantılarını izler ve pil seviyelerini (AirPods için sol/sağ/kutu) okur.
/// Seviyeler IOBluetoothDevice'in belgelenmemiş `batteryPercent…` özelliklerinden gelir;
/// macOS'in Denetim Merkezi'nde gösterdiği değerlerle aynıdır.
@Observable
final class HeadphoneMonitor {
    struct Device: Equatable {
        let address: String
        let name: String
        let symbol: String
        let caseSymbol: String
        var left: Int?
        var right: Int?
        var caseLevel: Int?
        var single: Int?

        var hasBattery: Bool { left != nil || right != nil || caseLevel != nil || single != nil }
        /// Kulaklığın kendi seviyesi; iki kulak ayrıysa düşük olanı.
        var budsLevel: Int? { [left, right].compactMap { $0 }.min() ?? single }
    }

    /// En son bağlanan ve hâlâ bağlı olan ses cihazı.
    private(set) var current: Device?

    /// Yeni bir kulaklık bağlanıp pil bilgisi geldiğinde (veya gelmeyeceği anlaşıldığında).
    @ObservationIgnored var onConnect: ((Device) -> Void)?

    @ObservationIgnored private let bridge = Bridge()
    @ObservationIgnored private var connectNotification: IOBluetoothUserNotification?
    @ObservationIgnored private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    @ObservationIgnored private var devices: [String: Device] = [:]
    @ObservationIgnored private var refreshTimer: Timer?
    @ObservationIgnored private var startDate = Date()

    private static let audioMajorClass: BluetoothDeviceClassMajor = 0x04

    func start() {
        startDate = .now
        bridge.onConnect = { [weak self] device in self?.connected(device) }
        bridge.onDisconnect = { [weak self] device in self?.disconnected(device) }
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: bridge, selector: #selector(Bridge.connected(_:device:))
        )
        // Uygulama açıldığında zaten bağlı olanlar (gösterge çıkmadan).
        for device in IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? [] where device.isConnected() {
            connected(device)
        }

        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.refreshAll() }
        timer.tolerance = 15
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func connected(_ device: IOBluetoothDevice) {
        guard device.deviceClassMajor == Self.audioMajorClass, let address = device.addressString else { return }
        if disconnectNotifications[address] == nil {
            disconnectNotifications[address] = device.register(
                forDisconnectNotification: bridge, selector: #selector(Bridge.disconnected(_:device:))
            )
        }
        // Açılıştaki ilk bildirimler (zaten bağlı cihazlar) gösterge çıkarmasın.
        let announce = Date.now.timeIntervalSince(startDate) > 3
        devices[address] = Self.read(device)
        current = devices[address]
        // Pil bilgisi bağlandıktan bir süre sonra gelir; birkaç kez dene.
        poll(device, address: address, attempt: 0, announce: announce)
    }

    private func poll(_ device: IOBluetoothDevice, address: String, attempt: Int, announce: Bool) {
        guard device.isConnected() else { return }
        let reading = Self.read(device)
        devices[address] = reading
        if current?.address == address { setCurrent(reading) }
        if reading.hasBattery || attempt >= 8 {
            if announce { onConnect?(reading) }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
            self?.poll(device, address: address, attempt: attempt + 1, announce: announce)
        }
    }

    private func disconnected(_ device: IOBluetoothDevice) {
        guard let address = device.addressString else { return }
        disconnectNotifications.removeValue(forKey: address)?.unregister()
        devices.removeValue(forKey: address)
        if current?.address == address {
            current = devices.values.first
        }
    }

    private func refreshAll() {
        for device in IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? [] {
            guard let address = device.addressString, devices[address] != nil, device.isConnected() else { continue }
            devices[address] = Self.read(device)
        }
        if let address = current?.address { setCurrent(devices[address]) }
    }

    /// Gözlem her atamada görünümü yeniler; pil seviyesi değişmediyse atama yapma.
    private func setCurrent(_ device: Device?) {
        if device != current { current = device }
    }

    // MARK: - Okuma

    private static func read(_ device: IOBluetoothDevice) -> Device {
        let name = device.name ?? "Kulaklık"
        let symbols = symbols(for: name, minorClass: device.deviceClassMinor)
        return Device(
            address: device.addressString ?? "",
            name: name,
            symbol: symbols.device,
            caseSymbol: symbols.case,
            left: percent(device, "batteryPercentLeft"),
            right: percent(device, "batteryPercentRight"),
            caseLevel: percent(device, "batteryPercentCase"),
            single: percent(device, "batteryPercentSingle")
        )
    }

    /// 0 "bilinmiyor" demektir.
    private static func percent(_ device: IOBluetoothDevice, _ key: String) -> Int? {
        guard device.responds(to: NSSelectorFromString(key)),
              let value = (device.value(forKey: key) as? NSNumber)?.intValue,
              (1...100).contains(value)
        else { return nil }
        return value
    }

    private static func symbols(for name: String, minorClass: BluetoothDeviceClassMinor) -> (device: String, case: String) {
        let lower = name.lowercased()
        if lower.contains("airpods max") { return ("airpodsmax", "airpodsmax") }
        if lower.contains("airpods pro") {
            return ("airpodspro", available("airpodspro.chargingcase.wireless.fill") ?? "airpods.chargingcase.fill")
        }
        if lower.contains("airpods") { return ("airpods", "airpods.chargingcase.fill") }
        if lower.contains("beats") { return (available("beats.headphones") ?? "headphones", "airpods.chargingcase.fill") }
        // Sınıf 6: kulak üstü kulaklık; diğerleri (kulak içi, kulaklık-mikrofon) için kulak içi simgesi.
        let device = minorClass == 6 ? "headphones" : (available("earbuds") ?? "headphones")
        return (device, available("earbuds.case.fill") ?? "airpods.chargingcase.fill")
    }

    private static func available(_ symbol: String) -> String? {
        NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil ? symbol : nil
    }

    /// IOBluetooth bildirimleri Objective-C seçici ister.
    private final class Bridge: NSObject {
        var onConnect: ((IOBluetoothDevice) -> Void)?
        var onDisconnect: ((IOBluetoothDevice) -> Void)?

        @objc func connected(_: IOBluetoothUserNotification, device: IOBluetoothDevice) {
            onConnect?(device)
        }

        @objc func disconnected(_: IOBluetoothUserNotification, device: IOBluetoothDevice) {
            onDisconnect?(device)
        }
    }
}
