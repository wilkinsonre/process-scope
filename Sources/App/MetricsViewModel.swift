import SwiftUI
import Combine
import os

/// Central view model providing system metrics to all views
@MainActor
public final class MetricsViewModel: ObservableObject {
    private static let logger = Logger(subsystem: "com.processscope", category: "MetricsViewModel")

    // MARK: - CPU

    @Published public var cpuTotalUsage: Double = 0
    @Published public var cpuPerCore: [Double] = []
    @Published public var cpuHistory: [Double] = []
    private var previousCPUTicks: [MachWrapper.CPUCoreTicks]?

    // MARK: - Memory

    @Published public var memoryUsed: UInt64 = 0
    @Published public var memoryTotal: UInt64 = 0
    @Published public var memoryPressure: Double = 0
    @Published public var memoryActive: UInt64 = 0
    @Published public var memoryWired: UInt64 = 0
    @Published public var memoryCompressed: UInt64 = 0
    @Published public var memoryFree: UInt64 = 0

    // MARK: - GPU

    @Published public var gpuUtilization: Double?
    @Published public var gpuHistory: [Double] = []

    // MARK: - Thermal

    @Published public var thermalState: Int = 0

    // MARK: - Processes

    @Published public var processes: [ProcessRecord] = []
    @Published public var processTree: [ProcessTreeNode] = []
    @Published public var processCount: Int = 0

    // MARK: - Network

    @Published public var networkConnections: [NetworkConnectionRecord] = []

    // MARK: - History limits

    private let maxHistoryPoints = 60

    private let processCollector = ProcessCollector()

    public init() {
        memoryTotal = SysctlWrapper.totalMemory()
        Task { await processCollector.activate() }
    }

    // MARK: - Update Methods

    public func updateCriticalMetrics() async {
        // CPU
        if let currentTicks = MachWrapper.perCoreCPUTicks() {
            if let prev = previousCPUTicks {
                let usage = MachWrapper.computeUsage(previous: prev, current: currentTicks)
                cpuPerCore = usage.map { $0.totalUsage * 100 }
                cpuTotalUsage = cpuPerCore.isEmpty ? 0 : cpuPerCore.reduce(0, +) / Double(cpuPerCore.count)
                appendHistory(&cpuHistory, value: cpuTotalUsage)
            }
            previousCPUTicks = currentTicks
        }

        // Memory
        if let stats = MachWrapper.memoryStatistics() {
            memoryUsed = stats.used
            memoryActive = stats.active
            memoryWired = stats.wired
            memoryCompressed = stats.compressed
            memoryFree = stats.free
            memoryPressure = stats.pressure * 100
        }

        // GPU
        if let gpu = IOKitWrapper.shared.gpuUtilization() {
            gpuUtilization = gpu
            appendHistory(&gpuHistory, value: gpu)
        }

        // Thermal
        thermalState = IOKitWrapper.shared.thermalState()
    }

    public func updateStandardMetrics() async {
        let procs = await processCollector.collect()
        processes = procs
        processCount = procs.count
        processTree = ProcessTreeBuilder.buildTree(from: procs)
    }

    public func updateExtendedMetrics() async {
        // Network connections will be populated when network collector is wired
    }

    public func updateSlowMetrics() async {
        // Full tree rebuild with enrichment happens here
    }

    // MARK: - History

    private func appendHistory(_ history: inout [Double], value: Double) {
        history.append(value)
        if history.count > maxHistoryPoints {
            history.removeFirst(history.count - maxHistoryPoints)
        }
    }
}
