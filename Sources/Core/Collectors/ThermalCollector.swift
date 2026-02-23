import Foundation
import os

/// Collects thermal state and power metrics
public actor ThermalCollector: SystemCollector {
    public nonisolated let id = "thermal"
    public nonisolated let displayName = "Thermal"
    public nonisolated let requiresHelper = false
    public nonisolated var isAvailable: Bool { true }

    private let logger = Logger(subsystem: "com.processscope", category: "ThermalCollector")
    private var _isActive = false
    private let iokit = IOKitWrapper.shared

    public init() {}

    public func activate() {
        _isActive = true
        logger.info("ThermalCollector activated")
    }

    public func deactivate() {
        _isActive = false
        logger.info("ThermalCollector deactivated")
    }

    // MARK: - Collection

    /// Snapshot of thermal state, battery info, and fan speed
    public struct ThermalSnapshot: Sendable {
        public let thermalState: Int // 0-3
        public let batteryInfo: IOKitWrapper.BatteryInfo?
        public let fanSpeedRPM: Int?
    }

    /// Collects current thermal state, battery info, and fan speed
    public func collect() -> ThermalSnapshot {
        ThermalSnapshot(
            thermalState: _isActive ? iokit.thermalState() : 0,
            batteryInfo: _isActive ? iokit.batteryInfo() : nil,
            fanSpeedRPM: _isActive ? iokit.fanSpeedRPM() : nil
        )
    }
}
