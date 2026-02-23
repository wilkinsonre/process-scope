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
    @Published public var memoryHistory: [Double] = []

    // MARK: - GPU

    @Published public var gpuUtilization: Double?
    @Published public var gpuHistory: [Double] = []

    // MARK: - Disk

    @Published public var diskUsage: Double = 0
    @Published public var diskTotal: UInt64 = 0

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
    private let enricher: ProcessEnricher

    public init() {
        memoryTotal = SysctlWrapper.totalMemory()
        enricher = ProcessEnricher(rules: ProcessEnricher.defaultRules)

        // Initialize disk metrics from root volume
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/") {
            let total = attrs[.systemSize] as? UInt64 ?? 0
            let free = attrs[.systemFreeSize] as? UInt64 ?? 0
            diskTotal = total
            diskUsage = total > 0 ? Double(total - free) / Double(total) : 0
        }

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
            let usedPercent = memoryTotal > 0 ? (Double(stats.used) / Double(memoryTotal)) * 100 : 0
            appendHistory(&memoryHistory, value: usedPercent)
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
        // Full tree rebuild with enrichment
        let enrichedLabels = enricher.enrichBatch(processes)
        let cpuPercentages: [pid_t: Double] = [:] // CPU deltas computed elsewhere
        processTree = ProcessTreeBuilder.buildTree(
            from: processes,
            cpuPercentages: cpuPercentages,
            enrichedLabels: enrichedLabels
        )

        // Refresh disk usage from root volume
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/") {
            let total = attrs[.systemSize] as? UInt64 ?? 0
            let free = attrs[.systemFreeSize] as? UInt64 ?? 0
            diskTotal = total
            diskUsage = total > 0 ? Double(total - free) / Double(total) : 0
        }
    }

    // MARK: - History

    private func appendHistory(_ history: inout [Double], value: Double) {
        history.append(value)
        if history.count > maxHistoryPoints {
            history.removeFirst(history.count - maxHistoryPoints)
        }
    }
}
