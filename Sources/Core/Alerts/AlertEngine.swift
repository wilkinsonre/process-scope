import Foundation
import os

// MARK: - Alert Engine

/// Evaluates alert rules against current system metrics
///
/// The engine is called on every polling tick (critical tier, 500ms) and checks
/// all enabled rules against the latest metric values. It tracks sustained
/// conditions (rules with duration > 0) and enforces cooldown periods to
/// prevent alert storms.
///
/// Thread safety is guaranteed by actor isolation. The engine owns the sustained
/// state dictionary and alert history, which are never shared across threads.
///
/// Usage:
/// ```swift
/// let engine = AlertEngine()
/// await engine.loadRules()
/// let events = await engine.evaluate(metrics: currentMetrics)
/// for event in events {
///     await notifier.deliver(event: event)
/// }
/// ```
public actor AlertEngine {
    private static let logger = Logger(subsystem: "com.processscope", category: "AlertEngine")

    // MARK: - State

    /// All configured alert rules
    private(set) var rules: [AlertRule] = []

    /// Tracks when each condition first became continuously true (rule ID -> first-true timestamp)
    private var sustainedState: [UUID: Date] = [:]

    /// Tracks when each rule last fired (rule ID -> last-fired timestamp) for cooldown enforcement
    private var lastFiredTimes: [UUID: Date] = [:]

    /// History of fired alert events (most recent first, capped at maxHistoryCount)
    private(set) var alertHistory: [AlertEvent] = []

    /// Maximum number of events retained in history
    private let maxHistoryCount: Int

    /// Count of unacknowledged alerts for badge display
    public var unacknowledgedCount: Int {
        alertHistory.filter { !$0.isAcknowledged }.count
    }

    // MARK: - Persistence

    /// Path to the JSON file where rules are persisted
    private let rulesFilePath: String

    /// Path to the JSON file where alert history is persisted
    private let historyFilePath: String

    // MARK: - Initialization

    /// Creates a new alert engine
    /// - Parameters:
    ///   - directory: Override directory for persistence; defaults to `~/.processscope`
    ///   - maxHistoryCount: Maximum number of events retained in history
    public init(directory: String? = nil, maxHistoryCount: Int = 100) {
        let dir = directory ?? (NSHomeDirectory() + "/.processscope")
        self.rulesFilePath = dir + "/alerts.json"
        self.historyFilePath = dir + "/alert-history.json"
        self.maxHistoryCount = maxHistoryCount
    }

    // MARK: - Rule Management

    /// Loads rules from disk, falling back to built-in defaults on first launch
    public func loadRules() {
        if let loaded = loadRulesFromDisk() {
            rules = loaded
            Self.logger.info("Loaded \(loaded.count) alert rules from disk")
        } else {
            rules = Self.builtInRules()
            saveRulesToDisk()
            Self.logger.info("Initialized with \(self.rules.count) built-in alert rules")
        }

        // Load history
        if let loadedHistory = loadHistoryFromDisk() {
            alertHistory = loadedHistory
        }
    }

    /// Returns all current rules
    public func getRules() -> [AlertRule] {
        rules
    }

    /// Adds a new rule
    /// - Parameter rule: The rule to add
    public func addRule(_ rule: AlertRule) {
        rules.append(rule)
        saveRulesToDisk()
        Self.logger.info("Added alert rule: \(rule.name)")
    }

    /// Updates an existing rule
    /// - Parameter rule: The updated rule (matched by ID)
    public func updateRule(_ rule: AlertRule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
            saveRulesToDisk()
            Self.logger.info("Updated alert rule: \(rule.name)")
        }
    }

    /// Removes a rule by ID
    /// - Parameter id: The ID of the rule to remove
    public func removeRule(id: UUID) {
        rules.removeAll { $0.id == id }
        sustainedState.removeValue(forKey: id)
        lastFiredTimes.removeValue(forKey: id)
        saveRulesToDisk()
        Self.logger.info("Removed alert rule: \(id)")
    }

    /// Replaces all rules with the built-in defaults
    public func resetToDefaults() {
        rules = Self.builtInRules()
        sustainedState.removeAll()
        lastFiredTimes.removeAll()
        saveRulesToDisk()
        Self.logger.info("Reset alert rules to defaults")
    }

    /// Replaces all rules (used by tests and YAML import)
    /// - Parameter newRules: The new rule set
    public func setRules(_ newRules: [AlertRule]) {
        rules = newRules
        saveRulesToDisk()
    }

    // MARK: - Evaluation

    /// Evaluates all enabled rules against the current metric values
    ///
    /// This method is designed to be called on every polling tick. It is lightweight
    /// and performs only simple comparisons and dictionary lookups.
    ///
    /// - Parameter metrics: Current snapshot of system metric values
    /// - Returns: Array of newly fired alert events (may be empty)
    public func evaluate(metrics: AlertMetricValues) -> [AlertEvent] {
        let now = Date()
        var firedEvents: [AlertEvent] = []

        for rule in rules where rule.isEnabled {
            guard let currentValue = metrics.value(for: rule.metric) else {
                // Metric unavailable -- clear sustained state
                sustainedState.removeValue(forKey: rule.id)
                continue
            }

            let conditionMet = rule.condition.evaluate(value: currentValue, threshold: rule.threshold)

            if conditionMet {
                if rule.duration > 0 {
                    // Sustained condition check
                    if let firstTrue = sustainedState[rule.id] {
                        let elapsed = now.timeIntervalSince(firstTrue)
                        if elapsed >= rule.duration {
                            if shouldFire(ruleID: rule.id, now: now, cooldown: rule.cooldown) {
                                let event = createEvent(rule: rule, metricValue: currentValue, now: now)
                                firedEvents.append(event)
                                lastFiredTimes[rule.id] = now
                            }
                        }
                        // else: still sustaining, not long enough yet
                    } else {
                        // Condition just became true -- start tracking
                        sustainedState[rule.id] = now
                    }
                } else {
                    // Immediate fire (duration == 0)
                    if shouldFire(ruleID: rule.id, now: now, cooldown: rule.cooldown) {
                        let event = createEvent(rule: rule, metricValue: currentValue, now: now)
                        firedEvents.append(event)
                        lastFiredTimes[rule.id] = now
                    }
                }
            } else {
                // Condition no longer met -- reset sustained state
                sustainedState.removeValue(forKey: rule.id)
            }
        }

        // Append to history
        if !firedEvents.isEmpty {
            alertHistory.insert(contentsOf: firedEvents, at: 0)
            trimHistory()
            saveHistoryToDisk()
        }

        return firedEvents
    }

    // MARK: - History Management

    /// Returns the alert history (most recent first)
    public func getHistory() -> [AlertEvent] {
        alertHistory
    }

    /// Acknowledges a specific alert event
    /// - Parameter id: The ID of the event to acknowledge
    public func acknowledgeEvent(id: UUID) {
        if let index = alertHistory.firstIndex(where: { $0.id == id }) {
            alertHistory[index].isAcknowledged = true
            saveHistoryToDisk()
        }
    }

    /// Acknowledges all alert events
    public func acknowledgeAll() {
        for i in alertHistory.indices {
            alertHistory[i].isAcknowledged = true
        }
        saveHistoryToDisk()
    }

    /// Clears all alert history
    public func clearHistory() {
        alertHistory.removeAll()
        saveHistoryToDisk()
        Self.logger.info("Alert history cleared")
    }

    // MARK: - Sustained State (for testing)

    /// Returns the sustained state dictionary (for testing)
    public func getSustainedState() -> [UUID: Date] {
        sustainedState
    }

    /// Returns the last fired times dictionary (for testing)
    public func getLastFiredTimes() -> [UUID: Date] {
        lastFiredTimes
    }

    // MARK: - Private Helpers

    /// Checks whether a rule is allowed to fire based on its cooldown period
    ///
    /// Enforces a minimum cooldown of 5 seconds to prevent alert flooding,
    /// even if a rule specifies a shorter cooldown.
    private func shouldFire(ruleID: UUID, now: Date, cooldown: TimeInterval) -> Bool {
        let effectiveCooldown = max(cooldown, 5.0)
        guard let lastFired = lastFiredTimes[ruleID] else { return true }
        return now.timeIntervalSince(lastFired) >= effectiveCooldown
    }

    /// Creates an alert event from a rule and metric value
    private func createEvent(rule: AlertRule, metricValue: Double, now: Date) -> AlertEvent {
        let valueStr: String
        if metricValue == metricValue.rounded() && metricValue < 10000 {
            valueStr = String(format: "%.0f", metricValue)
        } else {
            valueStr = String(format: "%.1f", metricValue)
        }

        let body = rule.message ?? "\(rule.metric.displayName) is \(valueStr)\(rule.metric.unitSuffix) (threshold: \(rule.condition.symbol) \(String(format: rule.threshold == rule.threshold.rounded() ? "%.0f" : "%.1f", rule.threshold))\(rule.metric.unitSuffix))"

        Self.logger.warning("Alert fired: \(rule.name) -- \(body)")

        return AlertEvent(
            rule: rule,
            timestamp: now,
            metricValue: metricValue,
            message: body
        )
    }

    /// Trims history to the maximum count
    private func trimHistory() {
        if alertHistory.count > maxHistoryCount {
            alertHistory = Array(alertHistory.prefix(maxHistoryCount))
        }
    }

    // MARK: - Disk Persistence

    private func loadRulesFromDisk() -> [AlertRule]? {
        guard FileManager.default.fileExists(atPath: rulesFilePath),
              let data = FileManager.default.contents(atPath: rulesFilePath) else {
            return nil
        }
        do {
            return try JSONDecoder().decode([AlertRule].self, from: data)
        } catch {
            Self.logger.error("Failed to decode alert rules: \(error.localizedDescription)")
            return nil
        }
    }

    private func saveRulesToDisk() {
        ensureDirectoryExists()
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(rules)
            try data.write(to: URL(fileURLWithPath: rulesFilePath), options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: rulesFilePath
            )
        } catch {
            Self.logger.error("Failed to save alert rules: \(error.localizedDescription)")
        }
    }

    private func loadHistoryFromDisk() -> [AlertEvent]? {
        guard FileManager.default.fileExists(atPath: historyFilePath),
              let data = FileManager.default.contents(atPath: historyFilePath) else {
            return nil
        }
        do {
            return try JSONDecoder().decode([AlertEvent].self, from: data)
        } catch {
            Self.logger.error("Failed to decode alert history: \(error.localizedDescription)")
            return nil
        }
    }

    private func saveHistoryToDisk() {
        ensureDirectoryExists()
        do {
            let data = try JSONEncoder().encode(alertHistory)
            try data.write(to: URL(fileURLWithPath: historyFilePath), options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: historyFilePath
            )
        } catch {
            Self.logger.error("Failed to save alert history: \(error.localizedDescription)")
        }
    }

    private func ensureDirectoryExists() {
        let dir = (rulesFilePath as NSString).deletingLastPathComponent
        if !FileManager.default.fileExists(atPath: dir) {
            try? FileManager.default.createDirectory(
                atPath: dir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
    }

    // MARK: - Built-in Rules

    /// Returns the default set of alert rules
    public static func builtInRules() -> [AlertRule] {
        [
            AlertRule(
                name: "High CPU Usage",
                metric: .cpuUsage,
                condition: .greaterThan,
                threshold: 90,
                duration: 10,
                cooldown: 60,
                severity: .warning,
                soundEnabled: false,
                message: "CPU usage has been above 90% for 10 seconds"
            ),
            AlertRule(
                name: "Memory Pressure Critical",
                metric: .memoryPressure,
                condition: .greaterThan,
                threshold: 80,
                duration: 5,
                cooldown: 30,
                severity: .critical,
                soundEnabled: true,
                message: "Memory pressure is critically high"
            ),
            AlertRule(
                name: "Thermal Throttling",
                metric: .thermalState,
                condition: .greaterThan,
                threshold: 1,
                duration: 0,
                cooldown: 120,
                severity: .warning,
                soundEnabled: false,
                message: "System is thermally throttled"
            ),
            AlertRule(
                name: "Low Battery",
                metric: .batteryLevel,
                condition: .lessThan,
                threshold: 15,
                duration: 0,
                cooldown: 300,
                severity: .warning,
                soundEnabled: true,
                message: "Battery level is below 15%"
            ),
            AlertRule(
                name: "Disk Nearly Full",
                metric: .diskUsage,
                condition: .greaterThan,
                threshold: 90,
                duration: 0,
                cooldown: 600,
                severity: .critical,
                soundEnabled: true,
                message: "Boot volume is nearly full (>90% used)"
            ),
            AlertRule(
                name: "High GPU Usage",
                metric: .gpuUtilization,
                condition: .greaterThan,
                threshold: 95,
                duration: 30,
                cooldown: 120,
                severity: .info,
                soundEnabled: false,
                message: "GPU utilization has been above 95% for 30 seconds"
            ),
            AlertRule(
                name: "High Power Draw",
                metric: .powerWatts,
                condition: .greaterThan,
                threshold: 50,
                duration: 60,
                cooldown: 300,
                severity: .info,
                soundEnabled: false,
                message: "System power draw has exceeded 50W for 60 seconds"
            ),
        ]
    }
}
