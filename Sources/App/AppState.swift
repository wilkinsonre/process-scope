import SwiftUI
import Combine
import IOKit.ps
import os

/// Central application state coordinating modules, polling, and data flow
@MainActor
public final class AppState: ObservableObject {
    private static let logger = Logger(subsystem: "com.processscope", category: "AppState")

    // MARK: - Published State

    @Published public var selectedModuleID: String? = "cpu"
    @Published public var isHelperInstalled = false
    @Published public var windowVisible = true {
        didSet { pollingCoordinator.setWindowVisible(windowVisible) }
    }

    // MARK: - Subsystems

    public let moduleRegistry = ModuleRegistry()
    public let pollingCoordinator: PollingCoordinator
    public let metricsViewModel: MetricsViewModel
    public let helperConnection = HelperConnection()

    // MARK: - Alert Engine

    public let alertEngine = AlertEngine()
    public let alertViewModel: AlertSettingsViewModel

    private var cancellables = Set<AnyCancellable>()
    private var batteryObserver: Any?

    public init() {
        let polling = PollingCoordinator(registry: moduleRegistry)
        self.pollingCoordinator = polling
        self.metricsViewModel = MetricsViewModel()

        // Initialize alert subsystem
        let alertVM = AlertSettingsViewModel(engine: alertEngine)
        self.alertViewModel = alertVM
        metricsViewModel.alertViewModel = alertVM

        // Load alert rules from disk (or initialize defaults)
        Task {
            await alertEngine.loadRules()
            alertVM.refresh()
        }

        registerDefaultModules()
        setupPollingSubscriptions()
        setupBatteryMonitoring()

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

    // MARK: - Adaptive Polling Hooks

    private func setupBatteryMonitoring() {
        // Check initial battery state
        updateBatteryState()

        // Monitor power source changes via IOKit
        let loop = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let appState = Unmanaged<AppState>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in
                appState.updateBatteryState()
            }
        }, Unmanaged.passUnretained(self).toOpaque())

        if let loop = loop?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), loop, .defaultMode)
        }
    }

    private func updateBatteryState() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [Any],
              !sources.isEmpty else {
            // No battery (desktop Mac) — never in battery mode
            pollingCoordinator.setBatteryMode(false)
            return
        }

        let info = IOPSGetProvidingPowerSourceType(snapshot)?.takeRetainedValue() as String?
        let onBattery = info == kIOPSBatteryPowerValue as String
        pollingCoordinator.setBatteryMode(onBattery)
        Self.logger.debug("Battery mode: \(onBattery)")
    }

    /// Call from window delegate to track visibility
    public func setWindowVisible(_ visible: Bool) {
        windowVisible = visible
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
