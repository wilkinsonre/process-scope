import Foundation
import UserNotifications
import os

// MARK: - Alert Notifier Protocol

/// Protocol for alert notification delivery, enabling testability
///
/// The default implementation uses `UNUserNotificationCenter`. Tests can
/// substitute a mock that records delivered events without system interaction.
public protocol AlertNotifying: Sendable {
    /// Requests notification permission from the user
    /// - Returns: `true` if permission was granted
    func requestPermission() async -> Bool

    /// Delivers a notification for the given alert event
    /// - Parameter event: The alert event to notify about
    func deliver(event: AlertEvent) async

    /// Updates the dock badge count
    /// - Parameter count: The number to display on the badge (0 clears it)
    func updateBadge(count: Int) async

    /// Clears the dock badge
    func clearBadge() async
}

// MARK: - Alert Notifier

/// Delivers alert notifications via UNUserNotificationCenter
///
/// Groups notifications by rule ID to prevent spam. Respects the sound
/// preference on each rule. Updates the dock badge with the count of
/// unacknowledged alerts.
public final class AlertNotifier: AlertNotifying, Sendable {
    private static let logger = Logger(subsystem: "com.processscope", category: "AlertNotifier")

    /// Notification category identifier for alert actions
    private static let alertCategoryID = "PROCESSSCOPE_ALERT"

    /// Shared singleton instance
    public static let shared = AlertNotifier()

    public init() {}

    // MARK: - Permission

    /// Requests authorization for alerts, sounds, and badge
    /// - Returns: `true` if the user granted permission
    public func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            Self.logger.info("Notification permission \(granted ? "granted" : "denied")")

            if granted {
                await registerCategories()
            }

            return granted
        } catch {
            Self.logger.error("Failed to request notification permission: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Delivery

    /// Delivers a notification for the given alert event
    ///
    /// Uses the rule's severity as a prefix in the title, the rule name as
    /// the subtitle, and the event message as the body. Notifications are
    /// grouped by rule ID so repeated alerts for the same rule collapse.
    ///
    /// - Parameter event: The alert event to deliver
    public func deliver(event: AlertEvent) async {
        let content = UNMutableNotificationContent()

        // Title includes severity
        content.title = "\(event.rule.severity.displayName): \(event.rule.name)"

        // Body is the descriptive message
        content.body = event.message

        // Sound based on rule preference
        if event.rule.soundEnabled {
            switch event.rule.severity {
            case .critical:
                content.sound = .defaultCritical
            case .warning, .info:
                content.sound = .default
            }
        }

        // Group by rule ID to avoid notification spam
        content.threadIdentifier = event.rule.id.uuidString

        // Category for action buttons
        content.categoryIdentifier = Self.alertCategoryID

        // User info for identifying the event later
        content.userInfo = [
            "alertEventID": event.id.uuidString,
            "alertRuleID": event.rule.id.uuidString,
            "severity": event.rule.severity.rawValue,
        ]

        let request = UNNotificationRequest(
            identifier: event.id.uuidString,
            content: content,
            trigger: nil // Deliver immediately
        )

        let center = UNUserNotificationCenter.current()
        do {
            try await center.add(request)
            Self.logger.info("Delivered notification for alert: \(event.rule.name)")
        } catch {
            Self.logger.error("Failed to deliver notification: \(error.localizedDescription)")
        }
    }

    // MARK: - Badge

    /// Updates the dock badge count
    /// - Parameter count: The number to display (0 clears the badge)
    public func updateBadge(count: Int) async {
        let center = UNUserNotificationCenter.current()
        do {
            try await center.setBadgeCount(count)
        } catch {
            Self.logger.error("Failed to update badge count: \(error.localizedDescription)")
        }
    }

    /// Clears the dock badge
    public func clearBadge() async {
        await updateBadge(count: 0)
    }

    // MARK: - Categories

    /// Registers notification categories with action buttons
    private func registerCategories() async {
        let acknowledgeAction = UNNotificationAction(
            identifier: "ACKNOWLEDGE",
            title: "Acknowledge",
            options: []
        )

        let muteAction = UNNotificationAction(
            identifier: "MUTE_RULE",
            title: "Mute This Rule",
            options: [.destructive]
        )

        let category = UNNotificationCategory(
            identifier: Self.alertCategoryID,
            actions: [acknowledgeAction, muteAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        let center = UNUserNotificationCenter.current()
        center.setNotificationCategories([category])
    }
}

// MARK: - Mock Notifier (for testing)

/// A mock notifier that records delivered events for testing
///
/// Does not interact with the system notification center. Stores all
/// delivered events in memory for assertion in tests.
public final class MockAlertNotifier: AlertNotifying, @unchecked Sendable {
    /// Events delivered during testing
    public private(set) var deliveredEvents: [AlertEvent] = []

    /// Whether permission was requested
    public private(set) var permissionRequested = false

    /// The last badge count that was set
    public private(set) var lastBadgeCount: Int = 0

    /// Whether to simulate permission being granted
    public var grantPermission: Bool = true

    private let lock = NSLock()

    public init() {}

    public func requestPermission() async -> Bool {
        lock.withLock {
            permissionRequested = true
        }
        return grantPermission
    }

    public func deliver(event: AlertEvent) async {
        lock.withLock {
            deliveredEvents.append(event)
        }
    }

    public func updateBadge(count: Int) async {
        lock.withLock {
            lastBadgeCount = count
        }
    }

    public func clearBadge() async {
        await updateBadge(count: 0)
    }

    /// Resets the mock state
    public func reset() {
        lock.withLock {
            deliveredEvents.removeAll()
            permissionRequested = false
            lastBadgeCount = 0
        }
    }
}
