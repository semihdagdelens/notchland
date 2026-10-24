import AppKit
import CoreAudio
import AudioToolbox

/// Varsayılan çıkış aygıtının ses seviyesini CoreAudio ile okur/yazar ve değişiklikleri dinler.
final class VolumeController {
    struct State: Equatable {
        var level: Float
        var isMuted: Bool
        var deviceName: String
        var isHeadphones: Bool
    }

    /// Ses seviyesi, sessiz durumu veya aygıt değişince çağrılır (başka bir uygulama değiştirse bile).
    var onChange: ((State) -> Void)?

    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var deviceListeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var lastState: State?

    private static var defaultDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private static var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    private static var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    func start() {
        attachToDefaultDevice()
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &Self.defaultDeviceAddress, .main
        ) { [weak self] _, _ in
            self?.attachToDefaultDevice()
        }
    }

    var state: State {
        State(level: level, isMuted: isMuted, deviceName: deviceName, isHeadphones: isHeadphones)
    }

    var level: Float {
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        AudioObjectGetPropertyData(deviceID, &Self.volumeAddress, 0, nil, &size, &value)
        return value
    }

    func setLevel(_ newValue: Float) {
        var value = Float32(min(max(newValue, 0), 1))
        AudioObjectSetPropertyData(deviceID, &Self.volumeAddress, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
        if isMuted && value > 0 { setMuted(false) }
    }

    var isMuted: Bool {
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(deviceID, &Self.muteAddress, 0, nil, &size, &value)
        return value != 0
    }

    func setMuted(_ muted: Bool) {
        var value: UInt32 = muted ? 1 : 0
        AudioObjectSetPropertyData(deviceID, &Self.muteAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    private var deviceName: String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &name) == noErr, let name else {
            return ""
        }
        return name.takeRetainedValue() as String
    }

    private var isHeadphones: Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &transport)
        return transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    private func attachToDefaultDevice() {
        for (address, block) in deviceListeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(deviceID, &address, .main, block)
        }
        deviceListeners.removeAll()

        var newID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &Self.defaultDeviceAddress, 0, nil, &size, &newID)
        deviceID = newID

        for address in [Self.volumeAddress, Self.muteAddress] {
            var address = address
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.publish() }
            if AudioObjectAddPropertyListenerBlock(deviceID, &address, .main, block) == noErr {
                deviceListeners.append((address, block))
            }
        }
        // Aygıt değişimini HUD'da göstermeden sadece hatırla.
        lastState = state
    }

    private func publish() {
        let current = state
        guard current != lastState else { return }
        lastState = current
        onChange?(current)
    }
}

/// Dahili ekranın parlaklığı. Genel bir API olmadığı için özel DisplayServices çalışma anında yüklenir.
final class BrightnessController {
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private let getFn: GetFn?
    private let setFn: SetFn?

    init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
        getFn = dlsym(handle, "DisplayServicesGetBrightness").map { unsafeBitCast($0, to: GetFn.self) }
        setFn = dlsym(handle, "DisplayServicesSetBrightness").map { unsafeBitCast($0, to: SetFn.self) }
    }

    var isAvailable: Bool { getFn != nil && setFn != nil }

    private var display: CGDirectDisplayID {
        var displays = [CGDirectDisplayID](repeating: 0, count: 8)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(8, &displays, &count)
        return displays.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 } ?? CGMainDisplayID()
    }

    var level: Float {
        var value: Float = 0
        _ = getFn?(display, &value)
        return value
    }

    func setLevel(_ newValue: Float) {
        _ = setFn?(display, min(max(newValue, 0), 1))
    }
}
