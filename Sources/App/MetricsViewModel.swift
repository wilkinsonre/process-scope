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

    // MARK: - Disk (legacy)

    @Published public var diskUsage: Double = 0
    @Published public var diskTotal: UInt64 = 0

    // MARK: - Storage (expanded)

    @Published public var storageVolumes: [VolumeSnapshot] = []
    @Published public var networkVolumes: [NetworkVolumeSnapshot] = []
    @Published public var timeMachineState: TimeMachineState = .unavailable

    // MARK: - Power & Thermal

    @Published public var thermalState: Int = 0
    @Published public var powerSnapshot: PowerSnapshot?
    @Published public var powerHistory: [Double] = []
    @Published public var componentPower: IOKitWrapper.ComponentPower?
    @Published public var cpuFrequency: IOKitWrapper.CPUFrequency?
    @Published public var batteryInfo: IOKitWrapper.BatteryInfo?
    @Published public var cpuTemp: Double?
    @Published public var gpuTemp: Double?
    @Published public var isThrottled: Bool = false

    private let powerCollector = PowerCollector()

    // MARK: - Processes

    @Published public var processes: [ProcessRecord] = []
    @Published public var processTree: [ProcessTreeNode] = []
    @Published public var processCount: Int = 0

    // MARK: - Network

    @Published public var networkConnections: [NetworkConnectionRecord] = []

    // MARK: - Bluetooth

    @Published public var bluetoothSnapshot: BluetoothSnapshot = BluetoothSnapshot()

    // MARK: - Audio

    @Published public var audioSnapshot: AudioSnapshot = AudioSnapshot()

    // MARK: - Network Intelligence

    @Published public var sshSessions: [SSHSession] = []
    @Published public var tailscaleStatus: TailscaleStatus?
    @Published public var wifiSnapshot: WiFiSnapshot?
    @Published public var listeningPorts: [ListeningPort] = []
    @Published public var speedTestResult: SpeedTestResult?
    @Published public var speedTestState: SpeedTestState = .idle
    @Published public var isRunningSpeedTest: Bool = false

    private let sshCollector = SSHSessionCollector()
    private let tailscaleCollector = TailscaleCollector()
    private let wifiCollector = WiFiCollector()
    private let speedTestRunnerInstance = SpeedTestRunner()
    private let listeningPortsCollector = ListeningPortsCollector()

    // MARK: - Bluetooth & Audio Collectors

    private let bluetoothCollector = BluetoothCollector()
    private let audioCollector = AudioCollector()

    // MARK: - History limits

    private let maxHistoryPoints = 60

    private let processCollector = ProcessCollector()
    private let storageCollector = StorageCollector()
    private let networkVolumeCollector = NetworkVolumeCollector()
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

        Task {
            await processCollector.activate()
            await powerCollector.activate()
            await storageCollector.activate()
            await networkVolumeCollector.activate()
            await sshCollector.activate()
            await tailscaleCollector.activate()
            await wifiCollector.activate()
            await listeningPortsCollector.activate()
            await bluetoothCollector.activate()
            await audioCollector.activate()
        }
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

        // Power & Thermal
        if let snapshot = await powerCollector.collect() {
            powerSnapshot = snapshot
            thermalState = snapshot.thermalState
            componentPower = snapshot.componentPower
            cpuFrequency = snapshot.frequency
            batteryInfo = snapshot.battery
            cpuTemp = snapshot.cpuTemp
            gpuTemp = snapshot.gpuTemp
            isThrottled = snapshot.isThrottled
            if let watts = snapshot.totalWatts {
                appendHistory(&powerHistory, value: watts)
            }
        } else {
            thermalState = IOKitWrapper.shared.thermalState()
        }
    }

    public func updateStandardMetrics() async {
        let procs = await processCollector.collect()
        processes = procs
        processCount = procs.count
        processTree = ProcessTreeBuilder.buildTree(from: procs)

        // Bluetooth (Standard tier, 1s)
        bluetoothSnapshot = await bluetoothCollector.collect()

        // Audio (Standard tier, 1s)
        audioSnapshot = await audioCollector.collect()
    }

    public func updateExtendedMetrics() async {
        // SSH sessions (Extended tier, 3s)
        sshSessions = await sshCollector.collectSessions()

        // Tailscale status (Extended tier, 3s)
        tailscaleStatus = await tailscaleCollector.collectStatus()

        // Listening ports (Extended tier, 3s)
        listeningPorts = await listeningPortsCollector.collectListeningPorts()
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

        // Expanded storage collection
        let storageSnapshot = await storageCollector.collect()
        storageVolumes = storageSnapshot.volumes
        timeMachineState = storageSnapshot.timeMachineState

        let netVolSnapshot = await networkVolumeCollector.collect()
        networkVolumes = netVolSnapshot.volumes

        // WiFi snapshot (Slow tier, 10s)
        wifiSnapshot = await wifiCollector.collectSnapshot()
    }

    // MARK: - Speed Test

    /// Triggers an on-demand speed test
    ///
    /// Runs on a low-priority queue to avoid blocking the UI thread.
    /// Updates `speedTestResult` and `speedTestState` on completion.
    public func runSpeedTest() async {
        guard !isRunningSpeedTest else { return }
        isRunningSpeedTest = true
        speedTestState = .running

        do {
            let result = try await speedTestRunnerInstance.run()
            speedTestResult = result
            speedTestState = .completed(result)
        } catch {
            speedTestState = .failed(error.localizedDescription)
        }

        isRunningSpeedTest = false
    }

    // MARK: - History

    private func appendHistory(_ history: inout [Double], value: Double) {
        history.append(value)
        if history.count > maxHistoryPoints {
            history.removeFirst(history.count - maxHistoryPoints)
        }
    }
}
