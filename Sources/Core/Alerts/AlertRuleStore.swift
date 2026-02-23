import Foundation
import os

// MARK: - Alert Rule Store

/// Handles YAML import/export and JSON persistence for alert rules
///
/// Rules are persisted as JSON at `~/.processscope/alerts.json` for machine
/// consumption. YAML import/export is supported for human-editable configuration.
/// The YAML format matches `Resources/DefaultAlertRules.yaml`.
public enum AlertRuleStore {
    private static let logger = Logger(subsystem: "com.processscope", category: "AlertRuleStore")

    // MARK: - YAML Parsing

    /// Parses alert rules from YAML text
    ///
    /// Supports a simple subset of YAML sufficient for alert rule configuration.
    /// Each rule is a mapping under a `rules:` key with fields matching AlertRule.
    ///
    /// - Parameter yamlText: The YAML content to parse
    /// - Returns: Parsed alert rules, or `nil` if parsing fails
    public static func parseYAML(_ yamlText: String) -> [AlertRule]? {
        let lines = yamlText.components(separatedBy: "\n")
        var rules: [AlertRule] = []
        var currentRule: [String: String]?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip comments and empty lines
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            // Top-level "rules:" key
            if trimmed == "rules:" { continue }

            // New rule item (starts with "- name:")
            if trimmed.hasPrefix("- name:") {
                if let existing = currentRule, let rule = buildRule(from: existing) {
                    rules.append(rule)
                }
                currentRule = [:]
                let value = trimmed.dropFirst("- name:".count).trimmingCharacters(in: .whitespaces)
                currentRule?["name"] = stripQuotes(value)
                continue
            }

            // Key-value pair within a rule
            if let colonIndex = trimmed.firstIndex(of: ":"), currentRule != nil {
                let key = String(trimmed[trimmed.startIndex..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(trimmed[trimmed.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                currentRule?[key] = stripQuotes(value)
            }
        }

        // Don't forget the last rule
        if let existing = currentRule, let rule = buildRule(from: existing) {
            rules.append(rule)
        }

        return rules.isEmpty ? nil : rules
    }

    /// Exports alert rules to YAML text
    ///
    /// - Parameter rules: The rules to export
    /// - Returns: YAML-formatted string
    public static func exportYAML(_ rules: [AlertRule]) -> String {
        var lines: [String] = []
        lines.append("# ProcessScope Alert Rules")
        lines.append("# Edit this file to customize alert thresholds")
        lines.append("")
        lines.append("rules:")

        for rule in rules {
            lines.append("  - name: \"\(rule.name)\"")
            lines.append("    metric: \(rule.metric.rawValue)")
            lines.append("    condition: \(rule.condition.rawValue)")
            lines.append("    threshold: \(formatThreshold(rule.threshold))")
            lines.append("    duration: \(Int(rule.duration))")
            lines.append("    cooldown: \(Int(rule.cooldown))")
            lines.append("    severity: \(rule.severity.rawValue)")
            lines.append("    enabled: \(rule.isEnabled)")
            lines.append("    sound: \(rule.soundEnabled)")
            if let message = rule.message {
                lines.append("    message: \"\(message)\"")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Default Rules from Bundle

    /// Loads default rules from the bundled DefaultAlertRules.yaml
    /// - Returns: Parsed rules, or the hardcoded defaults if the file is missing
    public static func loadBundledDefaults() -> [AlertRule] {
        guard let url = Bundle.main.url(forResource: "DefaultAlertRules", withExtension: "yaml"),
              let text = try? String(contentsOf: url, encoding: .utf8),
              let rules = parseYAML(text) else {
            logger.info("Using hardcoded default alert rules (bundle YAML not found)")
            return AlertEngine.builtInRules()
        }
        logger.info("Loaded \(rules.count) default alert rules from bundle YAML")
        return rules
    }

    // MARK: - Private Helpers

    private static func buildRule(from dict: [String: String]) -> AlertRule? {
        guard let name = dict["name"],
              let metricStr = dict["metric"],
              let metric = AlertMetric(rawValue: metricStr),
              let conditionStr = dict["condition"],
              let condition = AlertCondition(rawValue: conditionStr),
              let thresholdStr = dict["threshold"],
              let threshold = Double(thresholdStr) else {
            return nil
        }

        let duration = dict["duration"].flatMap { Double($0) } ?? 0
        let cooldown = dict["cooldown"].flatMap { Double($0) } ?? 60
        let severity = dict["severity"].flatMap { AlertSeverity(rawValue: $0) } ?? .warning
        let enabled = dict["enabled"].map { $0.lowercased() == "true" } ?? true
        let sound = dict["sound"].map { $0.lowercased() == "true" } ?? false
        let message = dict["message"]

        return AlertRule(
            name: name,
            metric: metric,
            condition: condition,
            threshold: threshold,
            duration: duration,
            cooldown: cooldown,
            isEnabled: enabled,
            severity: severity,
            soundEnabled: sound,
            message: message
        )
    }

    private static func stripQuotes(_ value: String) -> String {
        var result = value
        if (result.hasPrefix("\"") && result.hasSuffix("\"")) ||
           (result.hasPrefix("'") && result.hasSuffix("'")) {
            result = String(result.dropFirst().dropLast())
        }
        return result
    }

    private static func formatThreshold(_ value: Double) -> String {
        if value == value.rounded() {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }
}
