import Foundation
import os

/// Parses enrichment rules from YAML or built-in defaults
public enum EnrichmentRuleParser {
    private static let logger = Logger(subsystem: "com.processscope", category: "EnrichmentRuleParser")

    // MARK: - YAML Parsing (simplified key: value format)

    /// Load rules from a YAML file at the given URL
    /// - Parameter url: File URL to a YAML enrichment rules file
    /// - Returns: Parsed rules, or nil if the file could not be read
    public static func loadRules(from url: URL) -> [EnrichmentRule]? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            logger.warning("Failed to load enrichment rules from \(url.path)")
            return nil
        }
        return parseYAML(content)
    }

    /// Parse YAML string into enrichment rules
    /// - Parameter yaml: YAML-formatted string with rule definitions
    /// - Returns: Array of parsed enrichment rules
    public static func parseYAML(_ yaml: String) -> [EnrichmentRule] {
        var rules: [EnrichmentRule] = []
        var currentRule: [String: String] = [:]
        var currentName: String?

        for line in yaml.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            // New rule starts with "- name:"
            if trimmed.hasPrefix("- name:") {
                // Save previous rule
                if let name = currentName {
                    rules.append(buildRule(name: name, from: currentRule))
                }
                currentName = trimmed.replacingOccurrences(of: "- name:", with: "").trimmingCharacters(in: .whitespaces)
                currentRule = [:]
                continue
            }

            // Key-value pairs
            if let colonIndex = trimmed.firstIndex(of: ":") {
                let key = String(trimmed[trimmed.startIndex..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(trimmed[trimmed.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                if !key.hasPrefix("-") {
                    // Strip surrounding quotes from YAML values
                    let unquoted = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    currentRule[key] = unquoted
                }
            }
        }

        // Don't forget last rule
        if let name = currentName {
            rules.append(buildRule(name: name, from: currentRule))
        }

        return rules
    }

    private static func buildRule(name: String, from dict: [String: String]) -> EnrichmentRule {
        EnrichmentRule(
            name: name,
            processName: dict["processName"],
            argvContains: dict["argvContains"],
            argvRegex: dict["argvRegex"],
            template: dict["template"] ?? "{name}",
            priority: Int(dict["priority"] ?? "0") ?? 0
        )
    }

    // MARK: - Built-in Rules

    /// Default built-in enrichment rules for common developer processes
    public static let builtInRules: [EnrichmentRule] = [
        // Python processes
        EnrichmentRule(name: "python-uvicorn", processName: "python3",
                      argvContains: "uvicorn",
                      template: "uvicorn {argv_after:uvicorn|first} (port {port})"),

        EnrichmentRule(name: "python-gunicorn", processName: "python3",
                      argvContains: "gunicorn",
                      template: "gunicorn {argv_after:gunicorn|first}"),

        EnrichmentRule(name: "python-flask", processName: "python3",
                      argvContains: "flask",
                      template: "Flask {cwd_basename}"),

        EnrichmentRule(name: "python-django", processName: "python3",
                      argvContains: "manage.py",
                      template: "Django {cwd_basename}"),

        EnrichmentRule(name: "python-celery", processName: "python3",
                      argvContains: "celery",
                      template: "Celery {argv_after:celery|first}"),

        EnrichmentRule(name: "python-jupyter", processName: "python3",
                      argvContains: "jupyter",
                      template: "Jupyter {argv_after:jupyter|first}"),

        EnrichmentRule(name: "python-generic", processName: "python3",
                      template: "Python {argv_match_basename}"),

        // Node.js processes
        EnrichmentRule(name: "node-next", processName: "node",
                      argvContains: "next",
                      template: "Next.js {cwd_basename}"),

        EnrichmentRule(name: "node-vite", processName: "node",
                      argvContains: "vite",
                      template: "Vite {cwd_basename}"),

        EnrichmentRule(name: "node-webpack", processName: "node",
                      argvContains: "webpack",
                      template: "Webpack {cwd_basename}"),

        EnrichmentRule(name: "node-express", processName: "node",
                      argvContains: "express",
                      template: "Express {cwd_basename} (port {port})"),

        EnrichmentRule(name: "node-generic", processName: "node",
                      template: "Node {argv_match_basename}"),

        // Ruby
        EnrichmentRule(name: "ruby-rails", processName: "ruby",
                      argvContains: "rails",
                      template: "Rails {cwd_basename}"),

        EnrichmentRule(name: "ruby-puma", processName: "ruby",
                      argvContains: "puma",
                      template: "Puma {cwd_basename} (port {port})"),

        // Go
        EnrichmentRule(name: "go-run", processName: "go",
                      argvContains: "run",
                      template: "Go {argv_after:run|first}"),

        // Docker
        EnrichmentRule(name: "docker-desktop", processName: "com.docker.backend",
                      template: "Docker Desktop"),

        // SSH
        EnrichmentRule(name: "ssh-session", processName: "ssh",
                      template: "SSH {argv_after:ssh|first}"),

        // Xcode build
        EnrichmentRule(name: "xcodebuild", processName: "xcodebuild",
                      template: "Xcode Build {cwd_basename}"),

        // Swift
        EnrichmentRule(name: "swift-build", processName: "swift",
                      argvContains: "build",
                      template: "Swift Build {cwd_basename}"),
    ]
}
