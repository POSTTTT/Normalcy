import AppKit
import AudioToolbox
import CoreAudio

// What "vol" does: to the whole Mac, or with an app name, to that app only.
enum VolumeChange: Equatable {
    case set(Int) // 0-100
    case step(Int) // steps up (negative: down)
    case mute // toggles
    case output(String) // a device name, or the start of one
}

// What the bar shows while "vol" is typed: the Mac's output, or one app.
struct VolumeInfo: Equatable {
    var title: String
    var level: Float? // 0-1; nil when the device has no volume control
    var muted: Bool
}

// The Mac's output devices, through Core Audio.
enum Volume {
    struct Device: Equatable { var id: AudioDeviceID; var uid: String; var name: String }

    static let step: Float = 0.05

    static func address(_ sel: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func get<T>(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, _ value: T) -> T? {
        var a = address(sel, scope), v = value, size = UInt32(MemoryLayout<T>.size)
        // Plain values only (numbers, IDs): the bytes are filled in as-is.
        let ok = withUnsafeMutableBytes(of: &v) { AudioObjectGetPropertyData(obj, &a, 0, nil, &size, $0.baseAddress!) }
        return ok == noErr ? v : nil
    }

    @discardableResult
    static func set<T>(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, _ value: T) -> Bool {
        var a = address(sel, scope), v = value
        return withUnsafeBytes(of: &v) { AudioObjectSetPropertyData(obj, &a, 0, nil, UInt32(MemoryLayout<T>.size), $0.baseAddress!) } == noErr
    }

    static func string(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector) -> String? {
        var a = address(sel), v: Unmanaged<CFString>?, size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(obj, &a, 0, nil, &size, &v) == noErr else { return nil }
        return v?.takeRetainedValue() as String?
    }

    static func ids(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [AudioObjectID] {
        var a = address(sel, scope), size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(obj, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
        var out = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        return AudioObjectGetPropertyData(obj, &a, 0, nil, &size, &out) == noErr ? out : []
    }

    static func outputs() -> [Device] {
        ids(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices).compactMap { id in
            guard !ids(id, kAudioDevicePropertyStreams, kAudioObjectPropertyScopeOutput).isEmpty,
                  let uid = string(id, kAudioDevicePropertyDeviceUID), let name = string(id, kAudioObjectPropertyName) else { return nil }
            return Device(id: id, uid: uid, name: name)
        }
    }

    static var defaultOutput: Device? {
        let id = get(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal, AudioDeviceID(0))
        return outputs().first { $0.id == id }
    }

    // An exact name wins over one that only starts with what's typed, like "b".
    static func output(named q: String) -> Device? {
        let all = outputs(), q = q.lowercased()
        return all.first { $0.name.lowercased() == q } ?? all.first { $0.name.lowercased().hasPrefix(q) }
    }

    static func setDefault(_ d: Device) -> Bool {
        set(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal, d.id)
    }

    // The volume the menu bar slider shows, 0-1; nil when the device has no volume control (e.g. HDMI).
    static func level(_ d: Device) -> Float? {
        get(d.id, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioObjectPropertyScopeOutput, Float32(0))
    }

    static func setLevel(_ v: Float, _ d: Device) -> Bool {
        set(d.id, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioObjectPropertyScopeOutput, Float32(min(max(v, 0), 1)))
    }

    static func muted(_ d: Device) -> Bool {
        get(d.id, kAudioDevicePropertyMute, kAudioObjectPropertyScopeOutput, UInt32(0)) == 1
    }

    static func setMuted(_ on: Bool, _ d: Device) -> Bool {
        set(d.id, kAudioDevicePropertyMute, kAudioObjectPropertyScopeOutput, UInt32(on ? 1 : 0))
    }

    // The device's kind, by how it's connected.
    static func symbol(_ d: Device) -> String {
        switch get(d.id, kAudioDevicePropertyTransportType, kAudioObjectPropertyScopeGlobal, UInt32(0)) {
        case kAudioDeviceTransportTypeBuiltIn: "laptopcomputer"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: "display"
        case kAudioDeviceTransportTypeAirPlay: "airplayaudio"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE, kAudioDeviceTransportTypeUSB: "headphones"
        default: "hifispeaker"
        }
    }

    static func percent(_ v: Float) -> String { "\(Int((v * 100).rounded()))%" }
}

// One app's sound, taken off its usual path by a process tap and played on to a device with
// its own volume. Lasts until Normalcy quits; then the app plays as it did before.
// shortcut: only the app's processes playing sound when the route is made are tapped (a browser tab
// started later isn't); run the command again to pick it up.
@available(macOS 14.2, *)
final class AppRoute {
    let tap: AudioObjectID, agg: AudioObjectID, proc: AudioDeviceIOProcID
    let deviceUID: String? // nil: plays on the default output, moving with "vol out"
    // Read on the audio thread; a stale value for one buffer does no harm.
    var gain: Float = 1
    var muted = false

    static var routes: [pid_t: AppRoute] = [:]

    init(tap: AudioObjectID, agg: AudioObjectID, proc: AudioDeviceIOProcID, deviceUID: String?) {
        (self.tap, self.agg, self.proc, self.deviceUID) = (tap, agg, proc, deviceUID)
    }

    func stop() {
        AudioDeviceStop(agg, proc)
        AudioDeviceDestroyIOProcID(agg, proc)
        AudioHardwareDestroyAggregateDevice(agg)
        AudioHardwareDestroyProcessTap(tap)
    }

    // The app's route to that device (nil: the default output), made or remade as needed,
    // keeping its volume and mute. nil when the app isn't playing sound or the tap is refused.
    static func route(_ app: NSRunningApplication, device uid: String?, rebuild: Bool = false) -> AppRoute? {
        let pid = app.processIdentifier
        if let r = routes[pid], r.deviceUID == uid, !rebuild { return r }
        let old = routes.removeValue(forKey: pid)
        old?.stop()
        guard let r = make(app, uid) else { return nil }
        r.gain = old?.gain ?? 1
        r.muted = old?.muted ?? false
        routes[pid] = r
        return r
    }

    static func existing(_ app: NSRunningApplication) -> AppRoute? {
        routes[app.processIdentifier].map { route(app, device: $0.deviceUID) } ?? route(app, device: nil)
    }

    // After "vol out": apps on the default output follow it to the new one.
    static func followDefault() {
        for (pid, r) in routes where r.deviceUID == nil {
            guard let app = NSRunningApplication(processIdentifier: pid) else { r.stop(); routes[pid] = nil; continue }
            _ = route(app, device: nil, rebuild: true)
        }
    }

    // Browsers play from helper processes: Chrome's share its bundle ID, Safari's WebContent
    // is only tied to it as the responsible process.
    static func processObjects(_ app: NSRunningApplication) -> [AudioObjectID] {
        typealias Responsible = @convention(c) (pid_t) -> pid_t
        let responsible = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") // RTLD_DEFAULT
            .map { unsafeBitCast($0, to: Responsible.self) }
        let pid = app.processIdentifier, bundle = app.bundleIdentifier.map { $0 + "." }
        return Volume.ids(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList).filter { obj in
            // Never ourselves: run from a terminal, we count as the terminal's, and "vol ghostty"
            // would tap the sound we play for other apps back into itself.
            guard let p = Volume.get(obj, kAudioProcessPropertyPID, kAudioObjectPropertyScopeGlobal, pid_t(0)), p != getpid() else { return false }
            if p == pid || responsible?(p) == pid { return true }
            guard let bundle, let b = Volume.string(obj, kAudioProcessPropertyBundleID) else { return false }
            return b.hasPrefix(bundle)
        }
    }

    static func make(_ app: NSRunningApplication, _ uid: String?) -> AppRoute? {
        let objs = processObjects(app)
        guard !objs.isEmpty, let out = uid ?? Volume.defaultOutput?.uid else { return nil }
        let desc = CATapDescription(stereoMixdownOfProcesses: objs)
        desc.uuid = UUID()
        desc.muteBehavior = .mutedWhenTapped // the app's own sound stops; only ours plays
        desc.isPrivate = true
        var tap = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateProcessTap(desc, &tap) == noErr else { return nil }
        let agg: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Normalcy \(app.localizedName ?? "")",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: out,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: out]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: desc.uuid.uuidString]],
        ]
        var aggID = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateAggregateDevice(agg as CFDictionary, &aggID) == noErr else {
            AudioHardwareDestroyProcessTap(tap)
            return nil
        }
        var box: AppRoute?
        var proc: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&proc, aggID, nil) { _, input, _, output, _ in
            guard let r = box else { return }
            copy(input, output, gain: r.muted ? 0 : r.gain)
        }
        guard status == noErr, let proc else {
            AudioHardwareDestroyAggregateDevice(aggID)
            AudioHardwareDestroyProcessTap(tap)
            return nil
        }
        let r = AppRoute(tap: tap, agg: aggID, proc: proc, deviceUID: uid)
        box = r
        guard AudioDeviceStart(aggID, proc) == noErr else { r.stop(); return nil }
        return r
    }

    // The tap's stereo samples, Float32 interleaved, onto every output channel (left, right, left, …),
    // however the device splits its channels into buffers. Its last input buffer is the tap's:
    // a device with a microphone lists that first.
    static func copy(_ input: UnsafePointer<AudioBufferList>, _ output: UnsafeMutablePointer<AudioBufferList>, gain: Float) {
        let ins = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outs = UnsafeMutableAudioBufferListPointer(output)
        guard let src = ins.last, let sp = src.mData?.assumingMemoryBound(to: Float32.self), src.mNumberChannels > 0 else {
            for b in outs { if let d = b.mData { memset(d, 0, Int(b.mDataByteSize)) } }
            return
        }
        let sc = Int(src.mNumberChannels), srcFrames = Int(src.mDataByteSize) / 4 / sc
        var channel = 0
        for b in outs {
            guard let dp = b.mData?.assumingMemoryBound(to: Float32.self), b.mNumberChannels > 0 else { continue }
            let nc = Int(b.mNumberChannels), frames = Int(b.mDataByteSize) / 4 / nc
            for f in 0..<frames {
                for k in 0..<nc {
                    dp[f * nc + k] = f < srcFrames ? sp[f * sc + (channel + k) % sc] * gain : 0
                }
            }
            channel += nc
        }
    }
}

extension App {
    // An exact name wins, so "Safari" never lands on "Safari Technology Preview".
    static func runningApp(_ q: String) -> NSRunningApplication? {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        let name = { (a: NSRunningApplication) in (a.localizedName ?? "").lowercased() }
        return apps.first { name($0) == q.lowercased() } ?? apps.first { name($0).hasPrefix(q.lowercased()) }
    }

    // An app not yet adjusted plays at 100%.
    static func volumeInfo(_ q: String?) -> VolumeInfo? {
        if let q {
            guard let app = runningApp(q) else { return nil }
            var info = VolumeInfo(title: app.localizedName ?? q, level: 1, muted: false)
            if #available(macOS 14.2, *), let r = AppRoute.routes[app.processIdentifier] { (info.level, info.muted) = (r.gain, r.muted) }
            return info
        }
        return Volume.defaultOutput.map { VolumeInfo(title: $0.name, level: Volume.level($0), muted: Volume.muted($0)) }
    }

    static func outputItems() -> [AppItem] {
        Volume.outputs().map { AppItem(name: $0.name, symbol: Volume.symbol($0), level: Volume.level($0)) }
    }

    // The output device's name: an app's own, if it was sent to one, else the default.
    static func currentOutput(_ q: String?) -> String? {
        let all = Volume.outputs()
        if #available(macOS 14.2, *), let q, let app = runningApp(q),
           let uid = AppRoute.routes[app.processIdentifier]?.deviceUID {
            return all.first { $0.uid == uid }?.name
        }
        return Volume.defaultOutput?.name
    }

    // The new level or output, only once the bar is gone: while it's up, its meter and list show it.
    // Problems ("isn't playing sound") always show.
    func volumeNote(_ text: String) {
        if !panel.isVisible { showToast(text) }
    }

    func runVolume(app q: String?, _ change: VolumeChange) {
        defer { // the levels shown in a bar kept open by Shift+Return
            palette.outputs = Self.outputItems()
            palette.objectWillChange.send()
        }
        if let q { return runAppVolume(q, change) }
        if case .output(let name) = change {
            guard let d = Volume.output(named: name), Volume.setDefault(d) else { return NSSound.beep() }
            if #available(macOS 14.2, *) { AppRoute.followDefault() }
            return volumeNote("Output: \(d.name)")
        }
        guard let d = Volume.defaultOutput else { return NSSound.beep() }
        if change == .mute {
            let on = !Volume.muted(d)
            return Volume.setMuted(on, d) ? volumeNote(on ? "Muted" : "Unmuted") : showToast("\(d.name) can't be muted")
        }
        let now = Volume.level(d) ?? 0
        let v: Float = switch change {
        case .set(let n): Float(n) / 100
        case .step(let n): now + Volume.step * Float(n)
        default: now
        }
        guard Volume.setLevel(v, d) else { return showToast("\(d.name) has no volume control") }
        if Volume.muted(d), v > 0 { _ = Volume.setMuted(false, d) } // like the volume keys
        volumeNote("Volume \(Volume.percent(Volume.level(d) ?? v))")
    }

    func runAppVolume(_ q: String, _ change: VolumeChange) {
        guard let app = Self.runningApp(q) else { return NSSound.beep() }
        let name = app.localizedName ?? q
        guard #available(macOS 14.2, *) else { return showToast("Volume per app needs macOS 14.2") }
        if case .output(let dev) = change {
            guard let d = Volume.output(named: dev) else { return NSSound.beep() }
            // The default output itself: follow it from now on.
            let uid = d.uid == Volume.defaultOutput?.uid ? nil : d.uid
            guard AppRoute.route(app, device: uid) != nil else { return showToast("\(name) isn't playing sound") }
            return volumeNote("\(name): \(d.name)")
        }
        guard let r = AppRoute.existing(app) else { return showToast("\(name) isn't playing sound") }
        switch change {
        case .set(let n): r.gain = Float(n) / 100; r.muted = false
        case .step(let n): r.gain = min(max(r.gain + Volume.step * Float(n), 0), 1); r.muted = false
        case .mute: r.muted.toggle()
        case .output: break
        }
        volumeNote(r.muted ? "\(name) muted" : "\(name) \(Volume.percent(r.gain))")
    }
}

// Whatever is playing: the Now Playing app (Music, Spotify, a video in a browser…).
enum Media: Equatable {
    case playPause, next, previous
    case skip(Int) // seconds forward (negative: back)

    static func send(_ m: Media) {
        switch m {
        case .playPause: key(16) // NX_KEYTYPE_PLAY
        case .next: key(17) // NX_KEYTYPE_NEXT
        case .previous: key(18) // NX_KEYTYPE_PREVIOUS
        case .skip(let s): if !skip(s) { NSSound.beep() }
        }
    }

    // A press of that media key on the keyboard.
    static func key(_ code: Int) {
        for down in [true, false] {
            let state = down ? 0xa : 0xb
            NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state) << 8),
                               timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                               data1: code << 16 | state << 8, data2: -1)?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    // There's no media key for a 10-second skip: MediaRemote's skip forward / backward commands
    // (17 / 18), which players honor as their own skip, like a video page's seek buttons.
    // shortcut: private framework; if a macOS update drops it, it beeps.
    static func skip(_ seconds: Int) -> Bool {
        typealias Send = @convention(c) (UInt32, CFDictionary?) -> Bool
        guard let h = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY),
              let send = dlsym(h, "MRMediaRemoteSendCommand").map({ unsafeBitCast($0, to: Send.self) }),
              let key = dlsym(h, "kMRMediaRemoteOptionSkipInterval")?.assumingMemoryBound(to: CFString.self).pointee
        else { return false }
        return send(seconds > 0 ? 17 : 18, [key: abs(seconds)] as CFDictionary)
    }
}
