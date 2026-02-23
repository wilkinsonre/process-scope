import SwiftUI
import Combine
import os

/// Central application state coordinating modules, polling, and data flow
@MainActor
public final class AppState: ObservableObject {
    private static let logger = Logger(subsystem: "com.processscope", category: "AppState")

    // MARK: - Published State

    @Published public var selectedModuleID: String? = "cpu"
    @Published public var isHelperInstalled = false
    @Published public var windowVisible = true

    // MARK: - Subsystems

    public let moduleRegistry = ModuleRegistry()
    public let pollingCoordinator: PollingCoordinator
    public let metricsViewModel: MetricsViewModel
    public let helperConnection = HelperConnection()

    private var cancellables = Set<AnyCancellable>()

    public init() {
        let polling = PollingCoordinator(registry: moduleRegistry)
        self.pollingCoordinator = polling
        self.metricsViewModel = MetricsViewModel()

        registerDefaultModules()
        setupPollingSubscriptions()

        Task {
            await moduleRegistry.activateEnabledModules()
            polling.start()
        }
    }

    // MARK: - Module Registration

    private func registerDefaultModules() {
        moduleRegistry.register(CPUModule())
        moduleRegistry.register(MemoryModule())
        moduleRegistry.register(GPUModule())
        moduleRegistry.register(ProcessesModule())
        moduleRegistry.register(NetworkModule())
        moduleRegistry.register(StorageModule())
        moduleRegistry.register(PowerThermalModule())
        moduleRegistry.register(BluetoothModule())
        moduleRegistry.register(AudioModule())
        moduleRegistry.register(DisplayModule())
        moduleRegistry.register(SecurityModule())
        moduleRegistry.register(DeveloperModule())
    }

    // MARK: - Polling Subscriptions

    private func setupPollingSubscriptions() {
        // Critical tier (500ms) — CPU, memory, GPU, thermal
        pollingCoordinator.subscribe(tier: .critical, subscriber: PollingSubscriber(id: "metrics-critical") { [weak self] in
            await self?.metricsViewModel.updateCriticalMetrics()
        })

        // Standard tier (1s) — Process list, per-process stats
        pollingCoordinator.subscribe(tier: .standard, subscriber: PollingSubscriber(id: "metrics-standard") { [weak self] in
            await self?.metricsViewModel.updateStandardMetrics()
        })

        // Extended tier (3s) — Network, disk I/O
        pollingCoordinator.subscribe(tier: .extended, subscriber: PollingSubscriber(id: "metrics-extended") { [weak self] in
            await self?.metricsViewModel.updateExtendedMetrics()
        })

        // Slow tier (10s) — Full tree rebuild
        pollingCoordinator.subscribe(tier: .slow, subscriber: PollingSubscriber(id: "metrics-slow") { [weak self] in
            await self?.metricsViewModel.updateSlowMetrics()
        })
    }
}
