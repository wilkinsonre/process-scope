import Foundation
import CoreAudio
import os

// MARK: - Audio Device

/// Represents a single audio device (input or output)
public struct AudioDevice: Codable, Sendable, Identifiable, Equatable {
    /// Unique identifier for this audio device
    public let id: String

    /// Display name of the device
    public let name: String

    /// Unique identifier string from CoreAudio
    public let uid: String

    /// Whether this device supports audio input
    public let isInput: Bool

    /// Whether this device supports audio output
    public let isOutput: Bool

    /// Current sample rate in Hz (e.g. 44100, 48000, 96000)
    public let sampleRate: Double

    /// Current buffer size in frames
    public let bufferSize: UInt32

    /// Bit depth (e.g. 16, 24, 32), 0 if unavailable
    public let bitDepth: UInt32

    public init(
        id: String,
        name: String,
        uid: String,
        isInput: Bool,
        isOutput: Bool,
        sampleRate: Double,
        bufferSize: UInt32,
        bitDepth: UInt32
    ) {
        self.id = id
        self.name = name
        self.uid = uid
        self.isInput = isInput
        self.isOutput = isOutput
        self.sampleRate = sampleRate
        self.bufferSize = bufferSize
        self.bitDepth = bitDepth
    }
}

// MARK: - Audio Snapshot

/// A point-in-time snapshot of audio system state
public struct AudioSnapshot: Codable, Sendable {
    /// Current default input device, nil if none
    public let defaultInput: AudioDevice?

    /// Current default output device, nil if none
    public let defaultOutput: AudioDevice?

    /// System volume (0.0 to 1.0)
    public let volume: Float

    /// Whether the system output is muted
    public let isMuted: Bool

    /// All available audio devices
    public let allDevices: [AudioDevice]

    /// Process names currently using the microphone (best effort)
    public let micInUseBy: [String]

    /// Whether a camera is currently in use
    public let cameraInUse: Bool

    /// Timestamp of collection
    public let timestamp: Date

    public init(
        defaultInput: AudioDevice? = nil,
        defaultOutput: AudioDevice? = nil,
        volume: Float = 0,
        isMuted: Bool = false,
        allDevices: [AudioDevice] = [],
        micInUseBy: [String] = [],
        cameraInUse: Bool = false,
        timestamp: Date = Date()
    ) {
        self.defaultInput = defaultInput
        self.defaultOutput = defaultOutput
        self.volume = volume
        self.isMuted = isMuted
        self.allDevices = allDevices
        self.micInUseBy = micInUseBy
        self.cameraInUse = cameraInUse
        self.timestamp = timestamp
    }

    /// Whether the microphone is currently in use
    public var micInUse: Bool {
        !micInUseBy.isEmpty
    }
}

// MARK: - Audio Collector Protocol

/// Protocol for audio collection, enabling mock injection for tests
public protocol AudioCollecting: SystemCollector, Sendable {
    func collect() async -> AudioSnapshot
}

// MARK: - Audio Collector

/// Collects audio device and privacy indicator information using CoreAudio APIs
public actor AudioCollector: AudioCollecting {
    public nonisolated let id = "audio"
    public nonisolated let displayName = "Audio"
    public nonisolated let requiresHelper = false
    public nonisolated var isAvailable: Bool { true }

    private let logger = Logger(subsystem: "com.processscope", category: "AudioCollector")
    private var _isActive = false

    public init() {}

    public func activate() {
        _isActive = true
        logger.info("AudioCollector activated")
    }

    public func deactivate() {
        _isActive = false
        logger.info("AudioCollector deactivated")
    }

    // MARK: - Collection

    /// Collect a snapshot of the audio system state
    public func collect() async -> AudioSnapshot {
        guard _isActive else {
            return AudioSnapshot()
        }

        let allDevices = Self.enumerateAllDevices()
        let defaultOutput = Self.getDefaultDevice(selector: kAudioHardwarePropertyDefaultOutputDevice)
        let defaultInput = Self.getDefaultDevice(selector: kAudioHardwarePropertyDefaultInputDevice)
        let volume = Self.getSystemVolume(deviceID: defaultOutput?.audioObjectID)
        let isMuted = Self.getSystemMuted(deviceID: defaultOutput?.audioObjectID)
        let micProcesses = Self.detectMicrophoneUsers()
        let cameraInUse = Self.detectCameraUse()

        // Build AudioDevice from default device info
        let outputDevice: AudioDevice?
        if let info = defaultOutput {
            outputDevice = Self.buildAudioDevice(from: info.audioObjectID)
        } else {
            outputDevice = nil
        }

        let inputDevice: AudioDevice?
        if let info = defaultInput {
            inputDevice = Self.buildAudioDevice(from: info.audioObjectID)
        } else {
            inputDevice = nil
        }

        return AudioSnapshot(
            defaultInput: inputDevice,
            defaultOutput: outputDevice,
            volume: volume,
            isMuted: isMuted,
            allDevices: allDevices,
            micInUseBy: micProcesses,
            cameraInUse: cameraInUse,
            timestamp: Date()
        )
    }

    // MARK: - Device Info Helper

    private struct DeviceRef {
        let audioObjectID: AudioObjectID
    }

    // MARK: - Default Device

    /// Get the default input or output device
    private static func getDefaultDevice(selector: AudioObjectPropertySelector) -> DeviceRef? {
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceID
        )
        guard status == noErr, deviceID != 0 else { return nil }
        return DeviceRef(audioObjectID: deviceID)
    }

    // MARK: - Build AudioDevice

    /// Build a full AudioDevice struct from an AudioObjectID
    private static func buildAudioDevice(from deviceID: AudioObjectID) -> AudioDevice? {
        guard let name = deviceName(deviceID) else { return nil }
        let uid = deviceUID(deviceID) ?? "\(deviceID)"
        let hasInput = deviceHasStreams(deviceID, scope: kAudioDevicePropertyScopeInput)
        let hasOutput = deviceHasStreams(deviceID, scope: kAudioDevicePropertyScopeOutput)
        let rate = sampleRate(deviceID)
        let bufSize = bufferSize(deviceID)
        let bits = bitDepth(deviceID)

        return AudioDevice(
            id: uid,
            name: name,
            uid: uid,
            isInput: hasInput,
            isOutput: hasOutput,
            sampleRate: rate,
            bufferSize: bufSize,
            bitDepth: bits
        )
    }

    // MARK: - Device Enumeration

    /// Enumerate all audio devices on the system
    private static func enumerateAllDevices() -> [AudioDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &dataSize
        )
        guard status == noErr, dataSize > 0 else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &dataSize, &deviceIDs
        )
        guard status == noErr else { return [] }

        return deviceIDs.compactMap { buildAudioDevice(from: $0) }
    }

    // MARK: - Device Properties

    /// Read the name of an audio device
    private static func deviceName(_ deviceID: AudioObjectID) -> String? {
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &name)
        guard status == noErr else { return nil }
        return name as String
    }

    /// Read the UID of an audio device
    private static func deviceUID(_ deviceID: AudioObjectID) -> String? {
        var uid: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &uid)
        guard status == noErr else { return nil }
        return uid as String
    }

    /// Check if a device has streams in the given scope (input or output)
    private static func deviceHasStreams(_ deviceID: AudioObjectID, scope: AudioObjectPropertyScope) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        return status == noErr && dataSize > 0
    }

    /// Read the current sample rate of an audio device
    private static func sampleRate(_ deviceID: AudioObjectID) -> Double {
        var rate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &rate)
        return status == noErr ? rate : 0
    }

    /// Read the current buffer size of an audio device
    private static func bufferSize(_ deviceID: AudioObjectID) -> UInt32 {
        var frames: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSize,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &frames)
        return status == noErr ? frames : 0
    }

    /// Read the bit depth of the default stream on an audio device
    private static func bitDepth(_ deviceID: AudioObjectID) -> UInt32 {
        // Get the first output stream (fallback to input)
        let scope = deviceHasStreams(deviceID, scope: kAudioDevicePropertyScopeOutput)
            ? kAudioDevicePropertyScopeOutput
            : kAudioDevicePropertyScopeInput

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)

        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &format)
        guard status == noErr else { return 0 }

        return format.mBitsPerChannel
    }

    // MARK: - Volume & Mute

    /// Get the system volume from the default output device (0.0 to 1.0)
    private static func getSystemVolume(deviceID: AudioObjectID?) -> Float {
        guard let deviceID else { return 0 }

        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)

        // Try the main element first (master volume)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)
        if status == noErr {
            return volume
        }

        // Fallback: try channel 1 volume
        address.mElement = 1 // Channel 1
        status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)
        return status == noErr ? volume : 0
    }

    /// Check if the default output device is muted
    private static func getSystemMuted(deviceID: AudioObjectID?) -> Bool {
        guard let deviceID else { return false }

        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muted)
        return status == noErr && muted != 0
    }

    // MARK: - Privacy Indicators

    /// Detect processes currently using the microphone.
    ///
    /// Uses process enumeration to find clients of coreaudiod that have
    /// audio input sessions active. This is a best-effort detection.
    private static func detectMicrophoneUsers() -> [String] {
        var users: [String] = []

        // Check for the microphone privacy indicator by examining
        // the audio device input running state
        let defaultInput = getDefaultDevice(selector: kAudioHardwarePropertyDefaultInputDevice)
        guard let inputID = defaultInput?.audioObjectID else { return [] }

        var isRunning: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(inputID, &address, 0, nil, &size, &isRunning)
        guard status == noErr, isRunning != 0 else { return [] }

        // The mic is active. Try to identify which process by looking at
        // processes with known audio-capturing names.
        // Full identification requires TCC database access (FDA).
        let audioProcessNames = [
            "zoom.us", "Zoom", "FaceTime", "Skype", "Discord",
            "Microsoft Teams", "Google Chrome", "Safari", "Firefox",
            "Slack", "OBS", "QuickTime Player", "GarageBand",
            "Logic Pro", "Audacity"
        ]

        let allProcs = SysctlWrapper.allProcesses()
        for proc in allProcs {
            let pid = proc.kp_proc.p_pid
            guard pid > 0 else { continue }
            let name = LibProcWrapper.processName(for: pid) ?? ""
            if audioProcessNames.contains(where: { name.contains($0) }) {
                users.append(name)
            }
        }

        // If mic is running but we could not identify the process, report generic
        if users.isEmpty {
            users.append("Unknown process")
        }

        return users
    }

    /// Detect whether a camera is currently in use.
    ///
    /// macOS shows a green dot in the menu bar when the camera is active.
    /// We detect this by looking for the VDCAssistant or AppleCameraAssistant process.
    private static func detectCameraUse() -> Bool {
        let allProcs = SysctlWrapper.allProcesses()
        for proc in allProcs {
            let pid = proc.kp_proc.p_pid
            guard pid > 0 else { continue }
            let name = LibProcWrapper.processName(for: pid) ?? ""
            if name == "VDCAssistant" || name == "AppleCameraAssistant" {
                return true
            }
        }
        return false
    }
}

// MARK: - Mock Audio Collector

/// Mock audio collector for testing
public final class MockAudioCollector: AudioCollecting, @unchecked Sendable {
    public let id = "audio-mock"
    public let displayName = "Audio (Mock)"
    public let requiresHelper = false
    public var isAvailable: Bool = true

    public var mockSnapshot: AudioSnapshot = AudioSnapshot()
    public private(set) var activateCount = 0
    public private(set) var deactivateCount = 0

    public init() {}

    public func activate() async { activateCount += 1 }
    public func deactivate() async { deactivateCount += 1 }

    public func collect() async -> AudioSnapshot {
        mockSnapshot
    }
}
