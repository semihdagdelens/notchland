import Darwin
import Foundation
import IOKit

/// CPU, bellek, GPU, ağ ve disk kullanımını Mach/IOKit API'leriyle örnekler.
@Observable
final class SystemStats {
    enum MemoryPressure {
        case normal, warning, critical
    }

    static let historyLength = 40

    private(set) var cpu: Double = 0
    private(set) var coreCount = ProcessInfo.processInfo.activeProcessorCount
    private(set) var memoryUsed: Double = 0
    private(set) var memoryTotal = Double(ProcessInfo.processInfo.physicalMemory)
    private(set) var memoryPressure: MemoryPressure = .normal
    private(set) var gpu: Double?
    private(set) var downloadRate: Double = 0
    private(set) var uploadRate: Double = 0
    private(set) var diskFree: Double = 0
    private(set) var diskTotal: Double = 0
    private(set) var thermalState = ProcessInfo.processInfo.thermalState

    private(set) var cpuHistory: [Double] = []
    private(set) var memoryHistory: [Double] = []
    private(set) var gpuHistory: [Double] = []
    private(set) var downloadHistory: [Double] = []

    var memoryFraction: Double { memoryTotal > 0 ? memoryUsed / memoryTotal : 0 }

    /// Sadece sekme görünürken örnekle; kapalıyken hiç iş yapma (pil).
    var isVisible = false {
        didSet {
            guard isVisible != oldValue else { return }
            timer?.invalidate()
            timer = nil
            guard isVisible else { return }
            sample()
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.sample() }
            timer.tolerance = 0.2
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var previousTicks: [(busy: UInt64, total: UInt64)] = []
    @ObservationIgnored private var previousInterfaceBytes: [String: (rx: UInt32, tx: UInt32)] = [:]
    @ObservationIgnored private var previousSampleDate: Date?
    @ObservationIgnored private var lastDiskSample: Date?

    /// Boş disk alanı sorgusu pahalı (temizlenebilir alanı hesaplar); seyrek yenile.
    private static let diskInterval: TimeInterval = 30

    private func sample() {
        let now = Date()
        let elapsed = previousSampleDate.map { now.timeIntervalSince($0) } ?? 0
        previousSampleDate = now

        cpu = sampleCPU()
        sampleMemory()
        gpu = Self.sampleGPU()
        // Uzun aradan sonra gelen ilk ağ örneği ortalamayı bozar; aralığı sıfırla.
        sampleNetwork(elapsed: elapsed > 5 ? 0 : elapsed)
        if lastDiskSample.map({ now.timeIntervalSince($0) > Self.diskInterval }) ?? true {
            lastDiskSample = now
            sampleDisk()
        }
        thermalState = ProcessInfo.processInfo.thermalState

        Self.append(cpu, to: &cpuHistory)
        Self.append(memoryFraction * 100, to: &memoryHistory)
        Self.append(gpu ?? 0, to: &gpuHistory)
        Self.append(downloadRate, to: &downloadHistory)
    }

    private static func append(_ value: Double, to history: inout [Double]) {
        history.append(value)
        if history.count > historyLength { history.removeFirst(history.count - historyLength) }
    }

    // MARK: - CPU

    private func sampleCPU() -> Double {
        var processorCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &processorCount, &info, &infoCount)
                == KERN_SUCCESS, let info
        else { return cpu }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }

        var ticks: [(busy: UInt64, total: UInt64)] = []
        for core in 0..<Int(processorCount) {
            let base = core * Int(CPU_STATE_MAX)
            let user = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]))
            let system = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]))
            let nice = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)]))
            let idle = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]))
            ticks.append((user + system + nice, user + system + nice + idle))
        }
        defer { previousTicks = ticks }
        coreCount = ticks.count
        guard previousTicks.count == ticks.count else { return 0 }

        var busy: UInt64 = 0, total: UInt64 = 0
        for (now, before) in zip(ticks, previousTicks) where now.total >= before.total {
            busy += now.busy &- before.busy
            total += now.total &- before.total
        }
        return total > 0 ? Double(busy) / Double(total) * 100 : 0
    }

    // MARK: - Bellek

    private func sampleMemory() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        let page = Double(vm_kernel_page_size)
        // Etkinlik Monitörü'ndeki "Kullanılan Bellek": uygulama + kalıcı + sıkıştırılmış.
        let app = Double(stats.internal_page_count) - Double(stats.purgeable_count)
        memoryUsed = (app + Double(stats.wire_count) + Double(stats.compressor_page_count)) * page

        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 {
            memoryPressure = level >= 4 ? .critical : level >= 2 ? .warning : .normal
        }
    }

    // MARK: - GPU

    private static func sampleGPU() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator)
                == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var best: Double?
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = properties?.takeRetainedValue() as? [String: Any],
                  let perf = dict["PerformanceStatistics"] as? [String: Any],
                  let usage = (perf["Device Utilization %"] ?? perf["GPU Activity(%)"]) as? NSNumber
            else { continue }
            best = max(best ?? 0, usage.doubleValue)
        }
        return best
    }

    // MARK: - Ağ

    private func sampleNetwork(elapsed: TimeInterval) {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return }
        defer { freeifaddrs(pointer) }

        var current: [String: (rx: UInt32, tx: UInt32)] = [:]
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = entry.pointee
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
                  let data = ifa.ifa_data?.assumingMemoryBound(to: if_data.self).pointee
            else { continue }
            let name = String(cString: ifa.ifa_name)
            // Wi-Fi/Ethernet (en*); VPN (utun) trafiği zaten bunların üzerinden geçtiği için sayılmaz.
            guard name.hasPrefix("en") else { continue }
            current[name] = (data.ifi_ibytes, data.ifi_obytes)
        }
        defer { previousInterfaceBytes = current }
        guard elapsed > 0 else { return }

        var rx: UInt64 = 0, tx: UInt64 = 0
        for (name, now) in current {
            guard let before = previousInterfaceBytes[name] else { continue }
            // Sayaçlar 32 bit; taşmada &- doğru farkı verir.
            rx += UInt64(now.rx &- before.rx)
            tx += UInt64(now.tx &- before.tx)
        }
        downloadRate = Double(rx) / elapsed
        uploadRate = Double(tx) / elapsed
    }

    // MARK: - Disk

    private func sampleDisk() {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys) else { return }
        diskFree = Double(values.volumeAvailableCapacityForImportantUsage ?? 0)
        diskTotal = Double(values.volumeTotalCapacity ?? 0)
    }
}
