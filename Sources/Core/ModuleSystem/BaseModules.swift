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
    public var pollingSubscriptions: Set<PollingTier> { [.standard, .extended] }

    public let networkCollector: NetworkCollector
    public var collectors: [any SystemCollector] { [networkCollector] }

    public init() { networkCollector = NetworkCollector() }

    public func activate() async { await networkCollector.activate() }
    public func deactivate() async { await networkCollector.deactivate() }
}

// MARK: - Storage Module

public final class StorageModule: PSModule, @unchecked Sendable {
    public let id = "storage"
    public let displayName = "Storage"
    public let symbolName = "internaldrive"
    public let category = ModuleCategory.hardware
    public nonisolated var isAvailable: Bool { true }
    public var pollingSubscriptions: Set<PollingTier> { [.extended, .slow] }

    public let diskCollector: DiskCollector
    public var collectors: [any SystemCollector] { [diskCollector] }

    public init() { diskCollector = DiskCollector() }

    public func activate() async { await diskCollector.activate() }
    public func deactivate() async { await diskCollector.deactivate() }
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
    public var collectors: [any SystemCollector] { [thermalCollector] }

    public init() { thermalCollector = ThermalCollector() }

    public func activate() async { await thermalCollector.activate() }
    public func deactivate() async { await thermalCollector.deactivate() }
}

// MARK: - Bluetooth Module

public final class BluetoothModule: PSModule, @unchecked Sendable {
    public let id = "bluetooth"
    public let displayName = "Bluetooth"
    public let symbolName = "bluetooth"
    public let category = ModuleCategory.peripherals
    public nonisolated var isAvailable: Bool { true }
    public var pollingSubscriptions: Set<PollingTier> { [.standard] }

    public var collectors: [any SystemCollector] { [] }

    public init() {}

    public func activate() async {}
    public func deactivate() async {}
}

// MARK: - Audio Module

public final class AudioModule: PSModule, @unchecked Sendable {
    public let id = "audio"
    public let displayName = "Audio"
    public let symbolName = "speaker.wave.2"
    public let category = ModuleCategory.peripherals
    public nonisolated var isAvailable: Bool { true }
    public var pollingSubscriptions: Set<PollingTier> { [.standard] }

    public var collectors: [any SystemCollector] { [] }

    public init() {}

    public func activate() async {}
    public func deactivate() async {}
}

// MARK: - Display Module

public final class DisplayModule: PSModule, @unchecked Sendable {
    public let id = "display"
    public let displayName = "Display"
    public let symbolName = "display"
    public let category = ModuleCategory.peripherals
    public nonisolated var isAvailable: Bool { true }
    public var pollingSubscriptions: Set<PollingTier> { [.slow] }

    public var collectors: [any SystemCollector] { [] }

    public init() {}

    public func activate() async {}
    public func deactivate() async {}
}

// MARK: - Security Module

public final class SecurityModule: PSModule, @unchecked Sendable {
    public let id = "security"
    public let displayName = "Security"
    public let symbolName = "lock.shield"
    public let category = ModuleCategory.system
    public nonisolated var isAvailable: Bool { true }
    public var pollingSubscriptions: Set<PollingTier> { [.slow] }

    public var collectors: [any SystemCollector] { [] }

    public init() {}

    public func activate() async {}
    public func deactivate() async {}
}

// MARK: - Developer Module

public final class DeveloperModule: PSModule, @unchecked Sendable {
    public let id = "developer"
    public let displayName = "Developer"
    public let symbolName = "hammer"
    public let category = ModuleCategory.developer
    public nonisolated var isAvailable: Bool { true }
    public var pollingSubscriptions: Set<PollingTier> { [.extended] }

    public var collectors: [any SystemCollector] { [] }

    public init() {}

    public func activate() async {}
    public func deactivate() async {}
}
