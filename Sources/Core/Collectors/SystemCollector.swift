import Foundation

/// Protocol for all data collectors in ProcessScope
public protocol SystemCollector: AnyObject, Sendable {
    /// Unique identifier for this collector
    var id: String { get }

    /// Human-readable name
    var displayName: String { get }

    /// Whether this collector requires the privileged helper daemon
    var requiresHelper: Bool { get }

    /// Whether this collector is currently available
    var isAvailable: Bool { get }

    /// Activate the collector (start any background resources)
    func activate() async

    /// Deactivate the collector (release all resources for zero overhead)
    func deactivate() async
}

/// Error type for collectors
public enum CollectorError: LocalizedError {
    case unavailable(String)
    case permissionDenied(String)
    case timeout
    case helperRequired

    public var errorDescription: String? {
        switch self {
        case .unavailable(let reason): "Collector unavailable: \(reason)"
        case .permissionDenied(let reason): "Permission denied: \(reason)"
        case .timeout: "Collection timed out"
        case .helperRequired: "Privileged helper required"
        }
    }
}
