import Foundation
import os

// MARK: - Power Snapshot

/// Complete snapshot of power, thermal, and battery state
public struct PowerSnapshot: Codable, Sendable {
    /// Per-component power breakdown (nil if IOReport unavailable)
    public let componentPower: IOKitWrapper.ComponentPower?
    /// Total system power in watts (sum of all components, nil if unavailable)
    public let totalWatts: Double?
    /// CPU frequency information for throttle detection
    public let frequency: IOKitWrapper.CPUFrequency?
    /// CPU die temperature in Celsius
    public let cpuTemp: Double?
    /// GPU die temperature in Celsius
    public let gpuTemp: Double?
    /// Thermal state (0=nominal, 1=fair, 2=serious, 3=critical)
    public let thermalState: Int
    /// Battery information (nil on desktop Macs)
    public let battery: IOKitWrapper.BatteryInfo?
    /// Fan speed in RPM (nil if no fan or unavailable)
    public let fanSpeedRPM: Int?
    /// Timestamp of this snapshot
    public let timestamp: Date

    public init(
        componentPower: IOKitWrapper.ComponentPower? = nil,
        totalWatts: Double? = nil,
        frequency: IOKitWrapper.CPUFrequency? = nil,
        cpuTemp: Double? = nil,
        gpuTemp: Double? = nil,
        thermalState: Int = 0,
        battery: IOKitWrapper.BatteryInfo? = nil,
        fanSpeedRPM: Int? = nil,
        timestamp: Date = Date()
    ) {
        self.componentPower = componentPower
        self.totalWatts = totalWatts
        self.frequency = frequency
        self.cpuTemp = cpuTemp
        self.gpuTemp = gpuTemp
        self.thermalState = thermalState
        self.battery = battery
        self.fanSpeedRPM = fanSpeedRPM
        self.timestamp = timestamp
    }

    /// Whether any throttling is detected (thermal or frequency-based)
    public var isThrottled: Bool {
        if thermalState >= 2 { return true }
        if let freq = frequency, freq.isThrottled { return true }
        return false
    }
}

// MARK: - Power Collector

/// Collects per-component power breakdown, thermal state, CPU frequency,
/// temperature readings, and battery health.
///
/// Subscribes to the critical polling tier for thermal/power (500ms)
/// and the infrequent tier for battery health (60s).
public actor PowerCollector: SystemCollector {
    public nonisolated let id = "power"
    public nonisolated let displayName = "Power & Thermal"
    public nonisolated let requiresHelper = false
    public nonisolated var isAvailable: Bool { true }

    private let logger = Logger(subsystem: "com.processscope", category: "PowerCollector")
    private var _isActive = false
    private let iokit = IOKitWrapper.shared

    /// History buffer for power sparkline (up to 60 data points)
    private var powerHistory: [Double] = []
    private let maxHistoryPoints = 60

    /// Most recent snapshot for consumers
    private var latestSnapshot: PowerSnapshot?

    public init() {}

    // MARK: - Lifecycle

    public func activate() {
        _isActive = true
        powerHistory.removeAll()
        latestSnapshot = nil
        logger.info("PowerCollector activated")
    }

    public func deactivate() {
        _isActive = false
        powerHistory.removeAll()
        latestSnapshot = nil
        logger.info("PowerCollector deactivated")
    }

    // MARK: - Collection

    /// Collects a full power/thermal snapshot.
    /// Called on the critical polling tier (500ms) for power and thermal,
    /// battery data is included on every tick but only changes slowly.
    public func collect() -> PowerSnapshot? {
        guard _isActive else { return nil }

        let componentPower = iokit.perComponentPower()
        let totalWatts = componentPower?.totalWatts
        let frequency = iokit.cpuFrequency()
        let cpuTemp = iokit.cpuDieTemperature()
        let gpuTemp = iokit.gpuDieTemperature()
        let thermalState = iokit.thermalState()
        let battery = iokit.batteryInfo()
        let fan = iokit.fanSpeedRPM()

        // Update power history
        if let watts = totalWatts {
            appendHistory(watts)
        }

        let snapshot = PowerSnapshot(
            componentPower: componentPower,
            totalWatts: totalWatts,
            frequency: frequency,
            cpuTemp: cpuTemp,
            gpuTemp: gpuTemp,
            thermalState: thermalState,
            battery: battery,
            fanSpeedRPM: fan,
            timestamp: Date()
        )

        latestSnapshot = snapshot
        return snapshot
    }

    /// Returns the current power history for sparkline rendering
    public func getPowerHistory() -> [Double] {
        return powerHistory
    }

    /// Returns the most recent snapshot without triggering a new collection
    public func getLatestSnapshot() -> PowerSnapshot? {
        return latestSnapshot
    }

    // MARK: - History Management

    private func appendHistory(_ value: Double) {
        powerHistory.append(value)
        if powerHistory.count > maxHistoryPoints {
            powerHistory.removeFirst(powerHistory.count - maxHistoryPoints)
        }
    }
}

// MARK: - Mock Power Collector

/// Mock power collector for testing
public final class MockPowerCollector: SystemCollector, @unchecked Sendable {
    public let id = "power-mock"
    public let displayName = "Power & Thermal (Mock)"
    public let requiresHelper = false
    public var isAvailable: Bool = true

    public var mockSnapshot: PowerSnapshot?
    public private(set) var activateCount = 0
    public private(set) var deactivateCount = 0

    public init() {}

    public func activate() async { activateCount += 1 }
    public func deactivate() async { deactivateCount += 1 }
}
