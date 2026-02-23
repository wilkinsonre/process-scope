import Foundation
import os

/// Enriches raw process records with human-readable labels
///
/// The enrichment engine matches processes against a priority-ordered list of
/// ``EnrichmentRule`` instances and resolves template strings using process
/// metadata (arguments, working directory, ports, etc.).
public final class ProcessEnricher: Sendable {
    private static let logger = Logger(subsystem: "com.processscope", category: "ProcessEnricher")

    private let rules: [EnrichmentRule]

    /// Creates an enricher with the given ordered rule list
    /// - Parameter rules: Rules evaluated in order; first match wins
    public init(rules: [EnrichmentRule]) {
        self.rules = rules
    }

    // MARK: - Enrichment

    /// Enriches a single process record, returning a human-readable label or nil
    /// - Parameter process: The raw process record to enrich
    /// - Returns: A human-readable label if a rule matched, otherwise nil
    public func enrich(_ process: ProcessRecord) -> String? {
        for rule in rules {
            if let label = rule.match(process) {
                return label
            }
        }
        return nil
    }

    /// Enriches a batch of processes
    /// - Parameter processes: Array of process records to enrich
    /// - Returns: Dictionary mapping PIDs to their enriched labels (only matched processes)
    public func enrichBatch(_ processes: [ProcessRecord]) -> [pid_t: String] {
        var results: [pid_t: String] = [:]
        for process in processes {
            if let label = enrich(process) {
                results[process.pid] = label
            }
        }
        return results
    }

    // MARK: - Default Rules

    /// Returns the built-in default enrichment rules
    public static var defaultRules: [EnrichmentRule] {
        EnrichmentRuleParser.builtInRules
    }
}

// MARK: - Enrichment Rule

/// A rule that matches processes and produces enriched labels
///
/// Rules can match on process name, argument substrings, and argument regex
/// patterns. When all specified conditions match, the template string is
/// resolved using process metadata.
public struct EnrichmentRule: Sendable {
    public let name: String
    public let processName: String?
    public let argvContains: String?
    public let argvRegex: String?
    public let template: String
    public let priority: Int

    /// Creates an enrichment rule
    /// - Parameters:
    ///   - name: Human-readable rule name for debugging
    ///   - processName: Process name to match (case-insensitive)
    ///   - argvContains: Substring that must appear in joined arguments
    ///   - argvRegex: Regex pattern to match against joined arguments
    ///   - template: Template string with placeholders for label generation
    ///   - priority: Rule priority (higher values evaluated first when sorted)
    public init(name: String, processName: String? = nil, argvContains: String? = nil,
                argvRegex: String? = nil, template: String, priority: Int = 0) {
        self.name = name
        self.processName = processName
        self.argvContains = argvContains
        self.argvRegex = argvRegex
        self.template = template
        self.priority = priority
    }

    // MARK: - Matching

    /// Attempts to match a process against this rule
    /// - Parameter process: The process record to evaluate
    /// - Returns: A resolved label string if matched, otherwise nil
    public func match(_ process: ProcessRecord) -> String? {
        // Check process name match
        if let requiredName = processName {
            let procName = process.name.lowercased()
            let baseName = (process.executablePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? process.name).lowercased()
            guard procName == requiredName.lowercased() || baseName == requiredName.lowercased() else {
                return nil
            }
        }

        let argsJoined = process.arguments.joined(separator: " ")

        // Check argvContains
        if let contains = argvContains {
            guard argsJoined.localizedCaseInsensitiveContains(contains) else { return nil }
        }

        // Check argvRegex
        if let pattern = argvRegex {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
            let range = NSRange(argsJoined.startIndex..<argsJoined.endIndex, in: argsJoined)
            guard regex.firstMatch(in: argsJoined, range: range) != nil else { return nil }
        }

        // Resolve template
        return resolveTemplate(template, process: process)
    }

    // MARK: - Template Resolution

    private func resolveTemplate(_ template: String, process: ProcessRecord) -> String {
        var result = template
        let args = process.arguments

        // {argv_after:X|first} -- first argument after X
        let afterPattern = try? NSRegularExpression(pattern: #"\{argv_after:([^|]+)\|first\}"#)
        if let matches = afterPattern?.matches(in: result, range: NSRange(result.startIndex..., in: result)) {
            for match in matches.reversed() {
                guard let fullRange = Range(match.range, in: result),
                      let keyRange = Range(match.range(at: 1), in: result) else { continue }
                let key = String(result[keyRange])
                if let idx = args.firstIndex(where: { $0.contains(key) }), idx + 1 < args.count {
                    result.replaceSubrange(fullRange, with: args[idx + 1])
                } else {
                    result.replaceSubrange(fullRange, with: "")
                }
            }
        }

        // {argv_value:--flag|default:Y} -- value of --flag=value or --flag value
        let valuePattern = try? NSRegularExpression(pattern: #"\{argv_value:([^|]+)\|default:([^}]+)\}"#)
        if let matches = valuePattern?.matches(in: result, range: NSRange(result.startIndex..., in: result)) {
            for match in matches.reversed() {
                guard let fullRange = Range(match.range, in: result),
                      let flagRange = Range(match.range(at: 1), in: result),
                      let defaultRange = Range(match.range(at: 2), in: result) else { continue }
                let flag = String(result[flagRange])
                let defaultValue = String(result[defaultRange])

                var value = defaultValue
                for (i, arg) in args.enumerated() {
                    if arg.hasPrefix(flag + "=") {
                        value = String(arg.dropFirst(flag.count + 1))
                        break
                    }
                    if arg == flag, i + 1 < args.count {
                        value = args[i + 1]
                        break
                    }
                }
                result.replaceSubrange(fullRange, with: value)
            }
        }

        // {argv_match_basename} -- basename of first arg that looks like a file path
        result = result.replacingOccurrences(of: "{argv_match_basename}", with: {
            for arg in args.dropFirst() {
                if arg.contains("/") || arg.hasSuffix(".py") || arg.hasSuffix(".js") || arg.hasSuffix(".ts") || arg.hasSuffix(".rb") {
                    return URL(fileURLWithPath: arg).lastPathComponent
                }
            }
            return process.name
        }())

        // {cwd_basename} -- basename of working directory
        result = result.replacingOccurrences(of: "{cwd_basename}", with: {
            if let cwd = process.workingDirectory {
                return URL(fileURLWithPath: cwd).lastPathComponent
            }
            return ""
        }())

        // {port} -- first listening port from args
        result = result.replacingOccurrences(of: "{port}", with: {
            for (i, arg) in args.enumerated() {
                if arg == "--port" || arg == "-p" || arg == "-P", i + 1 < args.count {
                    return args[i + 1]
                }
                if arg.hasPrefix("--port=") {
                    return String(arg.dropFirst(7))
                }
            }
            return ""
        }())

        // {name} -- process name
        result = result.replacingOccurrences(of: "{name}", with: process.name)

        // Clean up extra spaces and trailing parens with empty content
        result = result.replacingOccurrences(of: "()", with: "")
        result = result.replacingOccurrences(of: "  ", with: " ")
        result = result.trimmingCharacters(in: .whitespaces)

        return result.isEmpty ? process.name : result
    }
}
