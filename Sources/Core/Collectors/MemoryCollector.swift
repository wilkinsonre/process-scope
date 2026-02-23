import Foundation
import os

/// Collects memory statistics using Mach VM APIs
public actor MemoryCollector: SystemCollector {
    public nonisolated let id = "memory"
    public nonisolated let displayName = "Memory"
    public nonisolated let requiresHelper = false
    public nonisolated var isAvailable: Bool { true }

    private let logger = Logger(subsystem: "com.processscope", category: "MemoryCollector")
    private var _isActive = false

    public init() {}

    public func activate() {
        _isActive = true
        logger.info("MemoryCollector activated")
    }

    public func deactivate() {
        _isActive = false
        logger.info("MemoryCollector deactivated")
    }

    // MARK: - Collection

    /// Snapshot of system memory usage and pressure
    public struct MemorySnapshot: Sendable {
        public let total: UInt64
        public let used: UInt64
        public let active: UInt64
        public let inactive: UInt64
        public let wired: UInt64
        public let compressed: UInt64
        public let free: UInt64
        public let pressure: Double // 0.0 to 1.0
        public let pressureLevel: MemoryPressureLevel
        public let swapUsed: UInt64
    }

    /// Collects a snapshot of current memory usage from Mach VM and sysctl
    public func collect() -> MemorySnapshot? {
        guard _isActive else { return nil }
        guard let stats = MachWrapper.memoryStatistics() else { return nil }

        let pressureLevel: MemoryPressureLevel
        if stats.pressure > 0.9 { pressureLevel = .critical }
        else if stats.pressure > 0.7 { pressureLevel = .warning }
        else { pressureLevel = .nominal }

        // Get swap info
        var swapUsage = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        sysctlbyname("vm.swapusage", &swapUsage, &swapSize, nil, 0)

        return MemorySnapshot(
            total: stats.total,
            used: stats.used,
            active: stats.active,
            inactive: stats.inactive,
            wired: stats.wired,
            compressed: stats.compressed,
            free: stats.free,
            pressure: stats.pressure,
            pressureLevel: pressureLevel,
            swapUsed: swapUsage.xsu_used
        )
    }
}

// MARK: - Mock

/// Mock memory collector for testing
public final class MockMemoryCollector: SystemCollector, @unchecked Sendable {
    public let id = "memory-mock"
    public let displayName = "Memory (Mock)"
    public let requiresHelper = false
    public var isAvailable: Bool = true
    public private(set) var activateCount = 0
    public private(set) var deactivateCount = 0

    public init() {}
    public func activate() async { activateCount += 1 }
    public func deactivate() async { deactivateCount += 1 }
}
