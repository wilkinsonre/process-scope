import Foundation
import os

// MARK: - Audit Entry

/// A single entry in the action audit trail
///
/// Each entry records what action was taken, on what target, the outcome,
/// and whether the user explicitly confirmed the action via a dialog.
public struct AuditEntry: Codable, Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let actionType: ActionType
    public let targetDescription: String
    public let result: ActionResult
    public let wasConfirmed: Bool

    /// Creates an audit entry
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        actionType: ActionType,
        targetDescription: String,
        result: ActionResult,
        wasConfirmed: Bool
    ) {
        self.id = id
        self.timestamp = timestamp
        self.actionType = actionType
        self.targetDescription = targetDescription
        self.result = result
        self.wasConfirmed = wasConfirmed
    }

    /// Parses an audit entry from a log file line
    /// - Parameter line: A single line from the audit log file
    /// - Returns: An `AuditEntry` if the line could be parsed, otherwise `nil`
    public static func parse(from line: String) -> AuditEntry? {
        // Format: [ISO8601] [ACTION_TYPE] [TARGET] [RESULT] [USER_CONFIRMED: yes/no]
        let components = line.components(separatedBy: "] [")
        guard components.count == 5 else { return nil }

        let timestampStr = components[0].trimmingCharacters(in: CharacterSet(charactersIn: "[ "))
        let actionRaw = components[1]
        let target = components[2]
        let resultStr = components[3]
        let confirmedStr = components[4].trimmingCharacters(in: CharacterSet(charactersIn: "] "))

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let timestamp = formatter.date(from: timestampStr) else { return nil }
        guard let result = ActionResult(rawValue: resultStr) else { return nil }
        guard let actionType = ActionType(rawValue: actionRaw) else { return nil }

        let wasConfirmed = confirmedStr.hasSuffix("yes")

        return AuditEntry(
            timestamp: timestamp,
            actionType: actionType,
            targetDescription: target,
            result: result,
            wasConfirmed: wasConfirmed
        )
    }

    /// Formats this entry as a log file line
    public var logLine: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let ts = formatter.string(from: timestamp)
        let confirmed = wasConfirmed ? "yes" : "no"
        let sanitizedTarget = targetDescription
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "[", with: "(")
            .replacingOccurrences(of: "]", with: ")")
        return "[\(ts)] [\(actionType.rawValue)] [\(sanitizedTarget)] [\(result.rawValue)] [USER_CONFIRMED: \(confirmed)]"
    }
}

// MARK: - Audit Trail

/// Append-only audit log for all actions executed by ProcessScope
///
/// Every action -- whether it succeeds, fails, or is cancelled -- is recorded
/// to `~/.processscope/actions.log`. The log is human-readable and append-only;
/// entries are never modified or deleted by the application (except via explicit
/// `clearAll` from the UI).
///
/// Thread safety is guaranteed by actor isolation.
public actor AuditTrail {
    private static let logger = Logger(subsystem: "com.processscope", category: "AuditTrail")

    /// Shared singleton instance used by the audit trail UI and action view model
    public static let shared = AuditTrail()

    private let logDirectoryPath: String
    private let logFilePath: String
    private let dateFormatter: ISO8601DateFormatter

    /// Creates an audit trail writing to the default log path
    /// - Parameter directory: Override directory for testing; defaults to `~/.processscope`
    public init(directory: String? = nil) {
        let dir = directory ?? (NSHomeDirectory() + "/.processscope")
        self.logDirectoryPath = dir
        self.logFilePath = dir + "/actions.log"
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.dateFormatter = formatter
    }

    // MARK: - Logging

    /// Records an action in the audit trail
    /// - Parameters:
    ///   - action: The type of action that was executed
    ///   - target: Description of the action target (process name, volume path, etc.)
    ///   - result: Whether the action succeeded, failed, or was cancelled
    ///   - userConfirmed: Whether the user explicitly confirmed via a dialog
    public func log(
        action: ActionType,
        target: String,
        result: ActionResult,
        userConfirmed: Bool
    ) {
        let entry = AuditEntry(
            actionType: action,
            targetDescription: target,
            result: result,
            wasConfirmed: userConfirmed
        )
        writeEntry(entry)
    }

    // MARK: - Reading

    /// Returns the most recent audit entries
    /// - Parameter limit: Maximum number of entries to return (most recent first)
    /// - Returns: Array of audit entries, newest first
    public func recentEntries(limit: Int = 100) -> [AuditEntry] {
        guard let data = FileManager.default.contents(atPath: logFilePath),
              let text = String(data: data, encoding: .utf8) else {
            return []
        }

        let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
        let recentLines = lines.suffix(limit).reversed()
        return recentLines.compactMap { AuditEntry.parse(from: $0) }
    }

    /// Returns all audit entries (potentially large)
    /// - Returns: Array of all audit entries, oldest first
    public func allEntries() -> [AuditEntry] {
        guard let data = FileManager.default.contents(atPath: logFilePath),
              let text = String(data: data, encoding: .utf8) else {
            return []
        }

        let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
        return lines.compactMap { AuditEntry.parse(from: $0) }
    }

    // MARK: - Clear

    /// Removes all entries from the audit log file
    ///
    /// This is the only mutation besides appending. Used from the audit
    /// trail UI when the user explicitly requests clearing the log.
    public func clearAll() {
        let fileURL = URL(fileURLWithPath: logFilePath)
        do {
            try Data().write(to: fileURL, options: .atomic)
            Self.logger.info("Audit log cleared")
        } catch {
            Self.logger.error("Failed to clear audit log: \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    private func writeEntry(_ entry: AuditEntry) {
        ensureDirectoryExists()

        let line = entry.logLine + "\n"
        guard let data = line.data(using: .utf8) else {
            Self.logger.error("Failed to encode audit entry as UTF-8")
            return
        }

        let fileURL = URL(fileURLWithPath: logFilePath)

        if FileManager.default.fileExists(atPath: logFilePath) {
            do {
                let handle = try FileHandle(forWritingTo: fileURL)
                handle.seekToEndOfFile()
                handle.write(data)
                try handle.close()
            } catch {
                Self.logger.error("Failed to append to audit log: \(error.localizedDescription)")
            }
        } else {
            do {
                try data.write(to: fileURL, options: .atomic)
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o600],
                    ofItemAtPath: logFilePath
                )
            } catch {
                Self.logger.error("Failed to create audit log: \(error.localizedDescription)")
            }
        }

        Self.logger.debug("Audit: \(entry.logLine)")
    }

    private func ensureDirectoryExists() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: logDirectoryPath) {
            do {
                try fm.createDirectory(
                    atPath: logDirectoryPath,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
            } catch {
                Self.logger.error("Failed to create audit directory: \(error.localizedDescription)")
            }
        }
    }
}
