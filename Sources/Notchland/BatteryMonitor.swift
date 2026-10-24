import Foundation
import IOKit.ps

/// IOKit güç kaynağı bildirimleriyle pil durumunu izler.
@Observable
final class BatteryMonitor {
    struct Status: Equatable {
        var level: Int
        var isCharging: Bool
        var isPluggedIn: Bool
        var minutesRemaining: Int?
    }

    private(set) var status: Status?
    private(set) var isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

    /// Şarj kablosu takılıp çıkarılınca.
    @ObservationIgnored var onPowerSourceChange: ((Status) -> Void)?
    /// Pil düşük eşiğin altına inince (bir kez).
    @ObservationIgnored var onLowBattery: ((Status) -> Void)?

    static var lowBatteryThreshold: Int { AppSettings.shared.lowBatteryThreshold }

    @ObservationIgnored private var runLoopSource: CFRunLoopSource?
    @ObservationIgnored private var didWarnLowBattery = false

    func start() {
        status = Self.readStatus()
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue().refresh()
        }
        if let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = source
        }
        NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            self?.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    private func refresh() {
        guard let new = Self.readStatus() else { return }
        let old = status
        guard new != old else { return }
        status = new

        if let old, old.isPluggedIn != new.isPluggedIn {
            onPowerSourceChange?(new)
        }
        if new.isPluggedIn || new.level > Self.lowBatteryThreshold || Self.lowBatteryThreshold == 0 {
            didWarnLowBattery = false
        } else if !didWarnLowBattery {
            didWarnLowBattery = true
            onLowBattery?(new)
        }
    }

    private static func readStatus() -> Status? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                  info[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else { continue }
            let current = info[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = info[kIOPSMaxCapacityKey] as? Int ?? 100
            let minutes = info[kIOPSTimeToEmptyKey] as? Int
            return Status(
                level: max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : current,
                isCharging: info[kIOPSIsChargingKey] as? Bool ?? false,
                isPluggedIn: info[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                minutesRemaining: (minutes ?? -1) > 0 ? minutes : nil
            )
        }
        return nil
    }
}
