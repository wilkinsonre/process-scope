import Foundation

// MARK: - Alert Metric

/// Metrics that can be monitored by alert rules
///
/// Each case corresponds to a system metric collected by MetricsViewModel.
/// The raw value is used for JSON/YAML serialization and display in the UI.
public enum AlertMetric: String, Codable, Sendable, CaseIterable, Identifiable {
    case cpuUsage = "cpuUsage"
    case memoryPressure = "memoryPressure"
    case thermalState = "thermalState"
    case diskUsage = "diskUsage"
    case processCount = "processCount"
    case gpuUtilization = "gpuUtilization"
    case batteryLevel = "batteryLevel"
    case powerWatts = "powerWatts"

    public var id: String { rawValue }

    /// Human-readable display name for the metric
    public var displayName: String {
        switch self {
        case .cpuUsage: "CPU Usage (%)"
        case .memoryPressure: "Memory Pressure (%)"
        case .thermalState: "Thermal State"
        case .diskUsage: "Disk Usage (%)"
        case .processCount: "Process Count"
        case .gpuUtilization: "GPU Utilization (%)"
        case .batteryLevel: "Battery Level (%)"
        case .powerWatts: "Power Draw (W)"
        }
    }

    /// SF Symbol name for the metric
    public var symbolName: String {
        switch self {
        case .cpuUsage: "cpu"
        case .memoryPressure: "memorychip"
        case .thermalState: "thermometer.high"
        case .diskUsage: "internaldrive"
        case .processCount: "list.number"
        case .gpuUtilization: "gpu"
        case .batteryLevel: "battery.25percent"
        case .powerWatts: "bolt"
        }
    }

    /// Unit suffix displayed after metric values in the UI
    public var unitSuffix: String {
        switch self {
        case .cpuUsage, .memoryPressure, .diskUsage, .gpuUtilization, .batteryLevel:
            "%"
        case .thermalState:
            ""
        case .processCount:
            ""
        case .powerWatts:
            " W"
        }
    }
}

// MARK: - Alert Condition

/// Comparison operator for threshold evaluation
public enum AlertCondition: String, Codable, Sendable, CaseIterable, Identifiable {
    case greaterThan = "greaterThan"
    case lessThan = "lessThan"
    case equals = "equals"

    public var id: String { rawValue }

    /// Human-readable display name
    public var displayName: String {
        switch self {
        case .greaterThan: "Greater Than"
        case .lessThan: "Less Than"
        case .equals: "Equals"
        }
    }

    /// Symbol representation for compact display
    public var symbol: String {
        switch self {
        case .greaterThan: ">"
        case .lessThan: "<"
        case .equals: "="
        }
    }

    /// Evaluates whether the given value satisfies this condition against the threshold
    /// - Parameters:
    ///   - value: The current metric value
    ///   - threshold: The threshold to compare against
    /// - Returns: `true` if the condition is met
    public func evaluate(value: Double, threshold: Double) -> Bool {
        switch self {
        case .greaterThan: value > threshold
        case .lessThan: value < threshold
        case .equals: abs(value - threshold) < 0.001
        }
    }
}

// MARK: - Alert Severity

/// Severity level for alert rules
///
/// Determines the visual presentation (color, icon) and notification behavior.
public enum AlertSeverity: String, Codable, Sendable, CaseIterable, Identifiable {
    case info = "info"
    case warning = "warning"
    case critical = "critical"

    public var id: String { rawValue }

    /// Human-readable display name
    public var displayName: String {
        switch self {
        case .info: "Info"
        case .warning: "Warning"
        case .critical: "Critical"
        }
    }

    /// SF Symbol name for the severity level
    public var symbolName: String {
        switch self {
        case .info: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "exclamationmark.octagon.fill"
        }
    }
}

// MARK: - Alert Rule

/// A configurable threshold alert rule
///
/// Rules define when alerts should fire based on system metrics. Each rule
/// specifies a metric, a comparison condition, a threshold value, and optional
/// duration (sustained condition) and cooldown (debounce) parameters.
///
/// Rules are persisted as JSON at `~/.processscope/alerts.json` and can be
/// imported/exported as YAML for human-editable configuration.
public struct AlertRule: Codable, Sendable, Identifiable, Equatable, Hashable {
    /// Unique identifier for the rule
    public let id: UUID

    /// Human-readable name displayed in notifications and the rule list
    public var name: String

    /// The system metric this rule monitors
    public var metric: AlertMetric

    /// The comparison operator
    public var condition: AlertCondition

    /// The threshold value to compare against
    public var threshold: Double

    /// How long the condition must persist before firing (seconds).
    /// A value of 0 means fire immediately.
    public var duration: TimeInterval

    /// Minimum time between repeated alerts for this rule (seconds).
    /// Prevents the same alert from firing repeatedly.
    public var cooldown: TimeInterval

    /// Whether this rule is active
    public var isEnabled: Bool

    /// Severity level affecting notification presentation
    public var severity: AlertSeverity

    /// Whether to play a sound when this alert fires
    public var soundEnabled: Bool

    /// Optional custom message override for the notification body
    public var message: String?

    /// Creates a new alert rule
    public init(
        id: UUID = UUID(),
        name: String,
        metric: AlertMetric,
        condition: AlertCondition,
        threshold: Double,
        duration: TimeInterval = 0,
        cooldown: TimeInterval = 60,
        isEnabled: Bool = true,
        severity: AlertSeverity = .warning,
        soundEnabled: Bool = false,
        message: String? = nil
    ) {
        self.id = id
        self.name = name
        self.metric = metric
        self.condition = condition
        self.threshold = threshold
        self.duration = duration
        self.cooldown = cooldown
        self.isEnabled = isEnabled
        self.severity = severity
        self.soundEnabled = soundEnabled
        self.message = message
    }

    /// Formatted description of the rule condition for display
    public var conditionDescription: String {
        let thresholdStr: String
        if threshold == threshold.rounded() && threshold < 10000 {
            thresholdStr = String(format: "%.0f", threshold)
        } else {
            thresholdStr = String(format: "%.1f", threshold)
        }
        return "\(metric.displayName) \(condition.symbol) \(thresholdStr)\(metric.unitSuffix)"
    }
}

// MARK: - Alert Metric Values

/// Snapshot of current metric values for alert evaluation
///
/// All values are optional because not all metrics may be available
/// (e.g., battery level on a desktop Mac, GPU on headless systems).
public struct AlertMetricValues: Sendable, Equatable {
    public var cpuUsage: Double?
    public var memoryPressure: Double?
    public var thermalState: Double?
    public var diskUsage: Double?
    public var processCount: Double?
    public var gpuUtilization: Double?
    public var batteryLevel: Double?
    public var powerWatts: Double?

    public init(
        cpuUsage: Double? = nil,
        memoryPressure: Double? = nil,
        thermalState: Double? = nil,
        diskUsage: Double? = nil,
        processCount: Double? = nil,
        gpuUtilization: Double? = nil,
        batteryLevel: Double? = nil,
        powerWatts: Double? = nil
    ) {
        self.cpuUsage = cpuUsage
        self.memoryPressure = memoryPressure
        self.thermalState = thermalState
        self.diskUsage = diskUsage
        self.processCount = processCount
        self.gpuUtilization = gpuUtilization
        self.batteryLevel = batteryLevel
        self.powerWatts = powerWatts
    }

    /// Returns the current value for the given metric, or `nil` if unavailable
    public func value(for metric: AlertMetric) -> Double? {
        switch metric {
        case .cpuUsage: cpuUsage
        case .memoryPressure: memoryPressure
        case .thermalState: thermalState
        case .diskUsage: diskUsage
        case .processCount: processCount
        case .gpuUtilization: gpuUtilization
        case .batteryLevel: batteryLevel
        case .powerWatts: powerWatts
        }
    }
}

// MARK: - Alert Event

/// A fired alert event recorded in history
///
/// Created by the AlertEngine when a rule's conditions are satisfied.
/// Contains the rule that triggered, the metric value at the time, and
/// a human-readable message for the notification.
public struct AlertEvent: Codable, Sendable, Identifiable, Equatable {
    /// Unique identifier for this event
    public let id: UUID

    /// The rule that triggered this event
    public let rule: AlertRule

    /// When the alert fired
    public let timestamp: Date

    /// The metric value at the time the alert fired
    public let metricValue: Double

    /// Human-readable message for the notification body
    public let message: String

    /// Whether the user has acknowledged this alert
    public var isAcknowledged: Bool

    /// Creates an alert event
    public init(
        id: UUID = UUID(),
        rule: AlertRule,
        timestamp: Date = Date(),
        metricValue: Double,
        message: String,
        isAcknowledged: Bool = false
    ) {
        self.id = id
        self.rule = rule
        self.timestamp = timestamp
        self.metricValue = metricValue
        self.message = message
        self.isAcknowledged = isAcknowledged
    }
}
