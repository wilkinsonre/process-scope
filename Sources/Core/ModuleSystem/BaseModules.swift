import Foundation

// MARK: - CPU Module

public final class CPUModule: PSModule, @unchecked Sendable {
    public let id = "cpu"
    public let displayName = "CPU"
    public let symbolName = "cpu"
    public let category = ModuleCategory.system
    public nonisolated var isAvailable: Bool { true }
    public var pollingSubscriptions: Set<PollingTier> { [.critical, .standard] }

    public let cpuCollector: CPUCollector
    public var collectors: [any SystemCollector] { [cpuCollector] }

    public init() { cpuCollector = CPUCollector() }

    public func activate() async { await cpuCollector.activate() }
    public func deactivate() async { await cpuCollector.deactivate() }
}

// MARK: - Memory Module

public final class MemoryModule: PSModule, @unchecked Sendable {
    public let id = "memory"
    public let displayName = "Memory"
    public let symbolName = "memorychip"
    public let category = ModuleCategory.system
    public nonisolated var isAvailable: Bool { true }
    public var pollingSubscriptions: Set<PollingTier> { [.critical] }

    public let memoryCollector: MemoryCollector
    public var collectors: [any SystemCollector] { [memoryCollector] }

    public init() { memoryCollector = MemoryCollector() }

    public func activate() async { await memoryCollector.activate() }
    public func deactivate() async { await memoryCollector.deactivate() }
}

// MARK: - GPU Module

public final class GPUModule: PSModule, @unchecked Sendable {
    public let id = "gpu"
    public let displayName = "GPU & Neural Engine"
    public let symbolName = "gpu"
    public let category = ModuleCategory.hardware
    public nonisolated var isAvailable: Bool { true }
    public var pollingSubscriptions: Set<PollingTier> { [.critical] }

    public let gpuCollector: GPUCollector
    public var collectors: [any SystemCollector] { [gpuCollector] }

    public init() { gpuCollector = GPUCollector() }

    public func activate() async { await gpuCollector.activate() }
    public func deactivate() async { await gpuCollector.deactivate() }
}

// MARK: - Processes Module

public final class ProcessesModule: PSModule, @unchecked Sendable {
    public let id = "processes"
    public let displayName = "Processes"
    public let symbolName = "list.bullet.rectangle"
    public let category = ModuleCategory.system
    public nonisolated var isAvailable: Bool { true }
    public var pollingSubscriptions: Set<PollingTier> { [.standard, .slow] }

    public let processCollector: ProcessCollector
    public var collectors: [any SystemCollector] { [processCollector] }

    public init() { processCollector = ProcessCollector() }

    public func activate() async { await processCollector.activate() }
    public func deactivate() async { await processCollector.deactivate() }
}

// MARK: - Network Module

public final class NetworkModule: PSModule, @unchecked Sendable {
    public let id = "network"
    public let displayName = "Network"
    public let symbolName = "network"
    public let category = ModuleCategory.network
    public nonisolated var isAvailable: Bool { true }
    public var pollingSubscriptions: Set<PollingTier> { [.standard, .extended, .slow, .infrequent] }

    public let networkCollector: NetworkCollector
    public let sshCollector: SSHSessionCollector
    public let tailscaleCollector: TailscaleCollector
    public let wifiCollector: WiFiCollector
    public let speedTestRunner: SpeedTestRunner
    public let listeningPortsCollector: ListeningPortsCollector

    public var collectors: [any SystemCollector] {
        [networkCollector, sshCollector, tailscaleCollector, wifiCollector, listeningPortsCollector]
    }

    public init() {
        networkCollector = NetworkCollector()
        sshCollector = SSHSessionCollector()
        tailscaleCollector = TailscaleCollector()
        wifiCollector = WiFiCollector()
        speedTestRunner = SpeedTestRunner()
        listeningPortsCollector = ListeningPortsCollector()
    }

    public func activate() async {
        await networkCollector.activate()
        await sshCollector.activate()
        await tailscaleCollector.activate()
        await wifiCollector.activate()
        await listeningPortsCollector.activate()
    }

    public func deactivate() async {
        await networkCollector.deactivate()
        await sshCollector.deactivate()
        await tailscaleCollector.deactivate()
        await wifiCollector.deactivate()
        await listeningPortsCollector.deactivate()
        await speedTestRunner.cancel()
    }
}

// MARK: - Storage Module

public final class StorageModule: PSModule, @unchecked Sendable {
    public let id = "storage"
    public let displayName = "Storage"
    public let symbolName = "internaldrive"
    public let category = ModuleCategory.hardware
    public nonisolated var isAvailable: Bool { true }
    public var pollingSubscriptions: Set<PollingTier> { [.slow, .infrequent] }

    public let storageCollector: StorageCollector
    public let networkVolumeCollector: NetworkVolumeCollector
    public var collectors: [any SystemCollector] { [storageCollector, networkVolumeCollector] }

    public init() {
        storageCollector = StorageCollector()
        networkVolumeCollector = NetworkVolumeCollector()
    }

    public func activate() async {
        await storageCollector.activate()
        await networkVolumeCollector.activate()
    }

    public func deactivate() async {
        await storageCollector.deactivate()
        await networkVolumeCollector.deactivate()
    }
}

// MARK: - Power & Thermal Module

public final class PowerThermalModule: PSModule, @unchecked Sendable {
    public let id = "power"
    public let displayName = "Power & Thermal"
    public let symbolName = "bolt.fill"
    public let category = ModuleCategory.hardware
    public nonisolated var isAvailable: Bool { true }
    public var pollingSubscriptions: Set<PollingTier> { [.critical, .infrequent] }

    public let thermalCollector: ThermalCollector
    public let powerCollector: PowerCollector
    public var collectors: [any SystemCollector] { [thermalCollector, powerCollector] }

    public init() {
        thermalCollector = ThermalCollector()
        powerCollector = PowerCollector()
    }

    public func activate() async {
        await thermalCollector.activate()
        await powerCollector.activate()
    }

    public func deactivate() async {
        await thermalCollector.deactivate()
        await powerCollector.deactivate()
    }
}

// MARK: - Bluetooth Module

public final class BluetoothModule: PSModule, @unchecked Sendable {
    public let id = "bluetooth"
    public let displayName = "Bluetooth"
    public let symbolName = "bluetooth"
    public let category = ModuleCategory.peripherals
    public nonisolated var isAvailable: Bool { true }
    public var pollingSubscriptions: Set<PollingTier> { [.standard] }

    public let bluetoothCollector: BluetoothCollector
    public var collectors: [any SystemCollector] { [bluetoothCollector] }

    public init() { bluetoothCollector = BluetoothCollector() }

    public func activate() async { await bluetoothCollector.activate() }
    public func deactivate() async { await bluetoothCollector.deactivate() }
}

// MARK: - Audio Module

public final class AudioModule: PSModule, @unchecked Sendable {
    public let id = "audio"
    public let displayName = "Audio"
    public let symbolName = "speaker.wave.2"
    public let category = ModuleCategory.peripherals
    public nonisolated var isAvailable: Bool { true }
    public var pollingSubscriptions: Set<PollingTier> { [.standard] }

    public let audioCollector: AudioCollector
    public var collectors: [any SystemCollector] { [audioCollector] }

    public init() { audioCollector = AudioCollector() }

    public func activate() async { await audioCollector.activate() }
    public func deactivate() async { await audioCollector.deactivate() }
}

// MARK: - Display Module

public final class DisplayModule: PSModule, @unchecked Sendable {
    public let id = "display"
    public let displayName = "Display"
    public let symbolName = "display"
    public let category = ModuleCategory.peripherals
    public nonisolated var isAvailable: Bool { true }
    public var pollingSubscriptions: Set<PollingTier> { [.slow] }

    public let displayCollector: DisplayCollector
    public var collectors: [any SystemCollector] { [displayCollector] }

    public init() { displayCollector = DisplayCollector() }

    public func activate() async { await displayCollector.activate() }
    public func deactivate() async { await displayCollector.deactivate() }
}

// MARK: - Security Module

public final class SecurityModule: PSModule, @unchecked Sendable {
    public let id = "security"
    public let displayName = "Security"
    public let symbolName = "lock.shield"
    public let category = ModuleCategory.system
    public nonisolated var isAvailable: Bool { true }
    public var pollingSubscriptions: Set<PollingTier> { [.slow] }

    public let securityCollector: SecurityCollector
    public var collectors: [any SystemCollector] { [securityCollector] }

    public init() { securityCollector = SecurityCollector() }

    public func activate() async { await securityCollector.activate() }
    public func deactivate() async { await securityCollector.deactivate() }
}

// MARK: - Developer Module

public final class DeveloperModule: PSModule, @unchecked Sendable {
    public let id = "developer"
    public let displayName = "Developer"
    public let symbolName = "hammer"
    public let category = ModuleCategory.developer
    public nonisolated var isAvailable: Bool { true }
    public var pollingSubscriptions: Set<PollingTier> { [.extended] }

    public let developerCollector: DeveloperCollector
    public var collectors: [any SystemCollector] { [developerCollector] }

    public init() { developerCollector = DeveloperCollector() }

    public func activate() async { await developerCollector.activate() }
    public func deactivate() async { await developerCollector.deactivate() }
}
