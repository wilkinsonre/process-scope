import SwiftUI
import os

// MARK: - Alert Settings View Model

/// View model for the alert settings UI
///
/// Provides a `@MainActor` bridge between the UI layer and the `AlertEngine` actor.
/// Maintains published copies of rules and history for SwiftUI binding, and
/// forwards mutations to the engine.
@MainActor
public final class AlertSettingsViewModel: ObservableObject {
    private static let logger = Logger(subsystem: "com.processscope", category: "AlertSettingsViewModel")

    // MARK: - Published State

    /// All configured alert rules
    @Published public var rules: [AlertRule] = []

    /// Alert history (most recent first)
    @Published public var alertHistory: [AlertEvent] = []

    /// Count of unacknowledged alerts (drives badge display)
    @Published public var unacknowledgedCount: Int = 0

    // MARK: - Dependencies

    private let engine: AlertEngine
    private let notifier: any AlertNotifying

    // MARK: - Initialization

    /// Creates the view model
    /// - Parameters:
    ///   - engine: The alert engine actor
    ///   - notifier: The notification delivery service
    public init(engine: AlertEngine, notifier: any AlertNotifying = AlertNotifier.shared) {
        self.engine = engine
        self.notifier = notifier
    }

    // MARK: - Refresh

    /// Refreshes rules and history from the engine
    public func refresh() {
        Task {
            rules = await engine.getRules()
            alertHistory = await engine.getHistory()
            unacknowledgedCount = await engine.unacknowledgedCount
        }
    }

    // MARK: - Rule CRUD

    /// Adds a new alert rule
    /// - Parameter rule: The rule to add
    public func addRule(_ rule: AlertRule) {
        Task {
            await engine.addRule(rule)
            rules = await engine.getRules()
        }
    }

    /// Updates an existing alert rule
    /// - Parameter rule: The updated rule (matched by ID)
    public func updateRule(_ rule: AlertRule) {
        Task {
            await engine.updateRule(rule)
            rules = await engine.getRules()
        }
    }

    /// Deletes an alert rule by ID
    /// - Parameter id: The ID of the rule to delete
    public func deleteRule(id: UUID) {
        Task {
            await engine.removeRule(id: id)
            rules = await engine.getRules()
        }
    }

    /// Toggles a rule's enabled state
    /// - Parameters:
    ///   - id: The ID of the rule to toggle
    ///   - enabled: The new enabled state
    public func toggleRule(id: UUID, enabled: Bool) {
        Task {
            var updatedRules = await engine.getRules()
            if let index = updatedRules.firstIndex(where: { $0.id == id }) {
                updatedRules[index].isEnabled = enabled
                await engine.updateRule(updatedRules[index])
                rules = await engine.getRules()
            }
        }
    }

    /// Resets all rules to built-in defaults
    public func resetToDefaults() {
        Task {
            await engine.resetToDefaults()
            rules = await engine.getRules()
            Self.logger.info("Alert rules reset to defaults")
        }
    }

    // MARK: - History

    /// Acknowledges all alerts and clears the badge
    public func acknowledgeAll() {
        Task {
            await engine.acknowledgeAll()
            await notifier.clearBadge()
            alertHistory = await engine.getHistory()
            unacknowledgedCount = 0
        }
    }

    /// Clears alert history
    public func clearHistory() {
        Task {
            await engine.clearHistory()
            await notifier.clearBadge()
            alertHistory = []
            unacknowledgedCount = 0
        }
    }

    // MARK: - Test Notification

    /// Sends a test notification to verify the notification pipeline
    public func sendTestNotification() {
        Task {
            let granted = await notifier.requestPermission()
            guard granted else {
                Self.logger.warning("Notification permission not granted -- cannot send test alert")
                return
            }

            let testRule = AlertRule(
                name: "Test Alert",
                metric: .cpuUsage,
                condition: .greaterThan,
                threshold: 0,
                duration: 0,
                cooldown: 0,
                severity: .info,
                soundEnabled: true,
                message: "This is a test notification from ProcessScope"
            )

            let testEvent = AlertEvent(
                rule: testRule,
                metricValue: 0,
                message: "This is a test notification from ProcessScope. If you see this, alerts are working correctly."
            )

            await notifier.deliver(event: testEvent)
            Self.logger.info("Test notification sent")
        }
    }

    // MARK: - Evaluation (called from MetricsViewModel)

    /// Evaluates all rules against the current metrics and delivers notifications
    ///
    /// This is the main integration point called from MetricsViewModel on each
    /// critical polling tick. It evaluates rules, delivers notifications for
    /// any fired events, and updates the badge count.
    ///
    /// - Parameter metrics: Current snapshot of system metric values
    public func evaluateAndNotify(metrics: AlertMetricValues) {
        Task {
            let events = await engine.evaluate(metrics: metrics)

            if !events.isEmpty {
                // Request permission if needed (no-op if already granted)
                _ = await notifier.requestPermission()

                for event in events {
                    await notifier.deliver(event: event)
                }

                // Update badge
                let count = await engine.unacknowledgedCount
                await notifier.updateBadge(count: count)

                // Refresh published state
                alertHistory = await engine.getHistory()
                unacknowledgedCount = count
            }
        }
    }
}
