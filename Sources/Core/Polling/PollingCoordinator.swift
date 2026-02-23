import Foundation
import os
import Combine

/// Coordinates polling across five tiers with adaptive timing
@MainActor
public final class PollingCoordinator: ObservableObject {
    private static let logger = Logger(subsystem: "com.processscope", category: "PollingCoordinator")

    // MARK: - Published State

    @Published public private(set) var isRunning = false

    // MARK: - Configuration

    private let registry: ModuleRegistry
    private var timers: [PollingTier: Task<Void, Never>] = [:]
    private var subscribers: [PollingTier: [PollingSubscriber]] = [:]
    private var adaptivePolicy = AdaptivePollPolicy()

    public init(registry: ModuleRegistry) {
        self.registry = registry
    }

    // MARK: - Subscriber Management

    public func subscribe(tier: PollingTier, subscriber: PollingSubscriber) {
        subscribers[tier, default: []].append(subscriber)
    }

    public func unsubscribe(id: String) {
        for tier in PollingTier.allCases {
            subscribers[tier]?.removeAll { $0.id == id }
        }
    }

    // MARK: - Start/Stop

    public func start() {
        guard !isRunning else { return }
        isRunning = true

        let activeTiers = registry.activePollingTiers
        for tier in activeTiers {
            startTimer(for: tier)
        }
        Self.logger.info("Polling started with \(activeTiers.count) active tiers")
    }

    public func stop() {
        isRunning = false
        for (_, task) in timers { task.cancel() }
        timers.removeAll()
        Self.logger.info("Polling stopped")
    }

    public func restart() {
        stop()
        start()
    }

    // MARK: - Adaptive Policy

    public func setWindowVisible(_ visible: Bool) {
        let changed = adaptivePolicy.setWindowVisible(visible)
        if changed { restart() }
    }

    public func setBatteryMode(_ onBattery: Bool) {
        let changed = adaptivePolicy.setBatteryMode(onBattery)
        if changed { restart() }
    }

    // MARK: - Timer Management

    private func startTimer(for tier: PollingTier) {
        timers[tier]?.cancel()

        let interval = adaptivePolicy.adjustedInterval(for: tier)
        let task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                await self?.tick(tier: tier)
            }
        }
        timers[tier] = task
    }

    private func tick(tier: PollingTier) async {
        guard let subs = subscribers[tier] else { return }
        for subscriber in subs {
            await subscriber.onTick()
        }
    }
}

// MARK: - Polling Subscriber

public struct PollingSubscriber: Sendable {
    public let id: String
    public let onTick: @Sendable () async -> Void

    public init(id: String, onTick: @escaping @Sendable () async -> Void) {
        self.id = id
        self.onTick = onTick
    }
}

// MARK: - Adaptive Poll Policy

public struct AdaptivePollPolicy: Sendable {
    private var windowVisible: Bool = true
    private var onBattery: Bool = false

    public init() {}

    public mutating func setWindowVisible(_ visible: Bool) -> Bool {
        guard windowVisible != visible else { return false }
        windowVisible = visible
        return true
    }

    public mutating func setBatteryMode(_ battery: Bool) -> Bool {
        guard onBattery != battery else { return false }
        onBattery = battery
        return true
    }

    /// Returns adjusted interval for a polling tier
    public func adjustedInterval(for tier: PollingTier) -> TimeInterval {
        var interval = tier.interval
        if !windowVisible { interval *= 2 }
        if onBattery { interval *= 2 }
        return interval
    }
}
