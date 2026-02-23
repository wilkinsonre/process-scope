import Foundation
import os

/// Collects GPU metrics via IOKit
public actor GPUCollector: SystemCollector {
    public nonisolated let id = "gpu"
    public nonisolated let displayName = "GPU"
    public nonisolated let requiresHelper = false
    public nonisolated var isAvailable: Bool { true }

    private let logger = Logger(subsystem: "com.processscope", category: "GPUCollector")
    private var _isActive = false
    private let iokit = IOKitWrapper.shared

    public init() {}

    public func activate() {
        _isActive = true
        logger.info("GPUCollector activated")
    }

    public func deactivate() {
        _isActive = false
        logger.info("GPUCollector deactivated")
    }

    // MARK: - Collection

    /// Snapshot of GPU and Neural Engine utilization and power
    public struct GPUSnapshot: Sendable {
        public let utilization: Double?
        public let powerWatts: Double?
        public let anePowerWatts: Double?
    }

    /// Collects current GPU utilization and power metrics from IOKit
    public func collect() -> GPUSnapshot? {
        guard _isActive else { return nil }
        return GPUSnapshot(
            utilization: iokit.gpuUtilization(),
            powerWatts: iokit.gpuPowerWatts(),
            anePowerWatts: iokit.anePowerWatts()
        )
    }
}
