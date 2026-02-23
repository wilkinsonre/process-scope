import Foundation
import os

/// Collects CPU metrics using Mach host APIs
public actor CPUCollector: SystemCollector {
    public nonisolated let id = "cpu"
    public nonisolated let displayName = "CPU"
    public nonisolated let requiresHelper = false
    public nonisolated var isAvailable: Bool { true }

    private let logger = Logger(subsystem: "com.processscope", category: "CPUCollector")
    private var _isActive = false
    private var previousTicks: [MachWrapper.CPUCoreTicks]?

    public init() {}

    public func activate() {
        _isActive = true
        previousTicks = MachWrapper.perCoreCPUTicks()
        logger.info("CPUCollector activated")
    }

    public func deactivate() {
        _isActive = false
        previousTicks = nil
        logger.info("CPUCollector deactivated")
    }

    // MARK: - Collection

    /// Snapshot of CPU usage across all cores
    public struct CPUSnapshot: Sendable {
        public let perCore: [MachWrapper.CPUCoreUsage]
        public let totalUsage: Double
        public let loadAverage: (one: Double, five: Double, fifteen: Double)
        public let coreCount: Int
    }

    /// Collects a snapshot of current CPU usage by diffing with previous tick counts
    public func collect() -> CPUSnapshot? {
        guard _isActive else { return nil }
        guard let currentTicks = MachWrapper.perCoreCPUTicks() else { return nil }

        let usage: [MachWrapper.CPUCoreUsage]
        if let prev = previousTicks {
            usage = MachWrapper.computeUsage(previous: prev, current: currentTicks)
        } else {
            usage = currentTicks.map { _ in MachWrapper.CPUCoreUsage(user: 0, system: 0, idle: 1, nice: 0) }
        }
        previousTicks = currentTicks

        let totalUsage = usage.isEmpty ? 0 : usage.reduce(0.0) { $0 + $1.totalUsage } / Double(usage.count) * 100
        let load = MachWrapper.loadAverage()

        return CPUSnapshot(
            perCore: usage,
            totalUsage: totalUsage,
            loadAverage: load,
            coreCount: usage.count
        )
    }
}

// MARK: - Mock

/// Mock CPU collector for testing
public final class MockCPUCollector: SystemCollector, @unchecked Sendable {
    public let id = "cpu-mock"
    public let displayName = "CPU (Mock)"
    public let requiresHelper = false
    public var isAvailable: Bool = true

    public var mockSnapshot: CPUCollector.CPUSnapshot?
    public private(set) var activateCount = 0
    public private(set) var deactivateCount = 0

    public init() {}

    public func activate() async { activateCount += 1 }
    public func deactivate() async { deactivateCount += 1 }
}
