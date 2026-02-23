import Foundation

// MARK: - Action Category

/// Categories of actions available in ProcessScope
///
/// Each category can be independently enabled or disabled in Settings.
/// Disabled categories have zero overhead and their actions are not
/// available in context menus or keyboard shortcuts.
public enum ActionCategory: String, Codable, Sendable, CaseIterable {
    case process = "Process"
    case storage = "Storage"
    case clipboard = "Clipboard"
    case docker = "Docker"
    case network = "Network"
    case system = "System"

    /// SF Symbol name for this category
    public var symbolName: String {
        switch self {
        case .process: "terminal"
        case .storage: "externaldrive"
        case .clipboard: "doc.on.clipboard"
        case .docker: "shippingbox"
        case .network: "network"
        case .system: "gearshape"
        }
    }

    /// Human-readable description for the settings UI
    public var displayName: String { rawValue }
}

// MARK: - Action Type

/// All discrete actions that ProcessScope can execute
///
/// Each action knows its display name, SF Symbol, category, whether it
/// requires the privileged helper, and whether it is destructive (requiring
/// a confirmation dialog before execution).
public enum ActionType: String, Codable, Sendable, CaseIterable {
    // Process actions
    case killProcess
    case forceKillProcess
    case suspendProcess
    case resumeProcess
    case killProcessGroup
    case reniceProcess
    case forceQuitApp

    // Storage actions
    case ejectVolume
    case forceEjectVolume
    case unmountVolume

    // Clipboard actions
    case copyToClipboard
    case revealInFinder

    // Docker actions (future M11 — declared now for registry completeness)
    case dockerStop
    case dockerStart
    case dockerRestart
    case dockerPause
    case dockerUnpause
    case dockerRemove

    // Network actions (future M12)
    case flushDNS
    case networkKillConnection

    // System actions (future M12)
    case purgeMemory
    case restartFinder
    case restartDock

    // MARK: - Display Properties

    /// Human-readable name shown in menus and confirmation dialogs
    public var displayName: String {
        switch self {
        case .killProcess: "Kill Process"
        case .forceKillProcess: "Force Kill Process"
        case .suspendProcess: "Suspend Process"
        case .resumeProcess: "Resume Process"
        case .killProcessGroup: "Kill Process Group"
        case .reniceProcess: "Change Priority"
        case .forceQuitApp: "Force Quit Application"
        case .ejectVolume: "Eject Volume"
        case .forceEjectVolume: "Force Eject Volume"
        case .unmountVolume: "Unmount Volume"
        case .copyToClipboard: "Copy to Clipboard"
        case .revealInFinder: "Reveal in Finder"
        case .dockerStop: "Stop Container"
        case .dockerStart: "Start Container"
        case .dockerRestart: "Restart Container"
        case .dockerPause: "Pause Container"
        case .dockerUnpause: "Unpause Container"
        case .dockerRemove: "Remove Container"
        case .flushDNS: "Flush DNS Cache"
        case .networkKillConnection: "Kill Connection"
        case .purgeMemory: "Purge Memory"
        case .restartFinder: "Restart Finder"
        case .restartDock: "Restart Dock"
        }
    }

    /// SF Symbol name for this action
    public var symbolName: String {
        switch self {
        case .killProcess: "xmark.circle"
        case .forceKillProcess: "xmark.circle.fill"
        case .suspendProcess: "pause.circle"
        case .resumeProcess: "play.circle"
        case .killProcessGroup: "xmark.rectangle"
        case .reniceProcess: "gauge.with.dots.needle.33percent"
        case .forceQuitApp: "power"
        case .ejectVolume: "eject"
        case .forceEjectVolume: "eject.fill"
        case .unmountVolume: "externaldrive.badge.minus"
        case .copyToClipboard: "doc.on.doc"
        case .revealInFinder: "folder"
        case .dockerStop: "stop.circle"
        case .dockerStart: "play.circle"
        case .dockerRestart: "arrow.clockwise.circle"
        case .dockerPause: "pause.circle"
        case .dockerUnpause: "play.circle.fill"
        case .dockerRemove: "trash"
        case .flushDNS: "arrow.triangle.2.circlepath"
        case .networkKillConnection: "xmark.shield"
        case .purgeMemory: "memorychip"
        case .restartFinder: "arrow.clockwise"
        case .restartDock: "dock.rectangle"
        }
    }

    /// The category this action belongs to
    public var category: ActionCategory {
        switch self {
        case .killProcess, .forceKillProcess, .suspendProcess, .resumeProcess,
             .killProcessGroup, .reniceProcess, .forceQuitApp:
            .process
        case .ejectVolume, .forceEjectVolume, .unmountVolume:
            .storage
        case .copyToClipboard, .revealInFinder:
            .clipboard
        case .dockerStop, .dockerStart, .dockerRestart, .dockerPause,
             .dockerUnpause, .dockerRemove:
            .docker
        case .flushDNS, .networkKillConnection:
            .network
        case .purgeMemory, .restartFinder, .restartDock:
            .system
        }
    }

    /// Whether this action requires the privileged helper daemon
    public var requiresHelper: Bool {
        switch self {
        case .forceEjectVolume, .flushDNS, .purgeMemory, .networkKillConnection:
            true
        case .reniceProcess:
            // Renice to lower priority (higher nice value) works without root,
            // but raising priority requires the helper
            true
        default:
            false
        }
    }

    /// Whether this action is destructive and must show a confirmation dialog
    public var isDestructive: Bool {
        switch self {
        case .killProcess, .forceKillProcess, .killProcessGroup, .forceQuitApp,
             .forceEjectVolume, .unmountVolume, .dockerRemove, .networkKillConnection:
            true
        case .suspendProcess, .ejectVolume, .flushDNS, .purgeMemory,
             .restartFinder, .restartDock, .reniceProcess:
            // These are impactful but reversible or low-risk
            true
        case .resumeProcess, .copyToClipboard, .revealInFinder,
             .dockerStop, .dockerStart, .dockerRestart, .dockerPause,
             .dockerUnpause:
            false
        }
    }

    /// Whether this action can be undone (suspend->resume, stop->start)
    public var undoAction: ActionType? {
        switch self {
        case .suspendProcess: .resumeProcess
        case .resumeProcess: .suspendProcess
        case .dockerStop: .dockerStart
        case .dockerStart: .dockerStop
        case .dockerPause: .dockerUnpause
        case .dockerUnpause: .dockerPause
        default: nil
        }
    }
}

// MARK: - Action Target

/// Identifies the target of an action
///
/// Carries optional context for different action types. For process actions,
/// `pid` and `name` are populated. For storage actions, `volumePath` is set.
/// For Docker actions, `containerID` is used.
public struct ActionTarget: Sendable, Equatable {
    /// Process ID (for process actions)
    public let pid: pid_t?

    /// Human-readable name of the target
    public let name: String

    /// Executable or file path
    public let path: String?

    /// Volume mount path (for storage actions)
    public let volumePath: String?

    /// Docker container ID (for Docker actions)
    public let containerID: String?

    /// Bundle identifier (for force quit via NSRunningApplication)
    public let bundleIdentifier: String?

    /// Creates an action target
    public init(
        pid: pid_t? = nil,
        name: String,
        path: String? = nil,
        volumePath: String? = nil,
        containerID: String? = nil,
        bundleIdentifier: String? = nil
    ) {
        self.pid = pid
        self.name = name
        self.path = path
        self.volumePath = volumePath
        self.containerID = containerID
        self.bundleIdentifier = bundleIdentifier
    }

    /// Formatted description for audit log entries
    public var auditDescription: String {
        var parts: [String] = [name]
        if let pid { parts.append("PID \(pid)") }
        if let path { parts.append(path) }
        if let volumePath { parts.append(volumePath) }
        if let containerID { parts.append(containerID) }
        return parts.joined(separator: " | ")
    }
}

// MARK: - Action Result

/// Outcome of an executed action
public enum ActionResult: String, Codable, Sendable {
    case success
    case failure
    case cancelled

    /// Human-readable name for display in the audit trail UI
    public var displayName: String {
        switch self {
        case .success: "Success"
        case .failure: "Failed"
        case .cancelled: "Cancelled"
        }
    }
}
