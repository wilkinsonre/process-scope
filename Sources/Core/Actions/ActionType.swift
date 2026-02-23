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

    // Docker actions (M11)
    case dockerStop
    case dockerStart
    case dockerRestart
    case dockerPause
    case dockerUnpause
    case dockerRemove

    // Network actions (M12)
    case sshToTerminal
    case flushDNS
    case pingHost
    case traceRoute
    case dnsLookup
    case networkKillConnection

    // System actions (M12)
    case purgeMemory
    case restartFinder
    case restartDock
    case openActivityMonitor
    case revealPathInFinder
    case emptyTrash
    case toggleDarkMode
    case lockScreen
    case copySysInfo

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
        case .sshToTerminal: "SSH to Terminal"
        case .flushDNS: "Flush DNS Cache"
        case .pingHost: "Ping Host"
        case .traceRoute: "Trace Route"
        case .dnsLookup: "DNS Lookup"
        case .networkKillConnection: "Kill Connection"
        case .purgeMemory: "Purge Memory"
        case .restartFinder: "Restart Finder"
        case .restartDock: "Restart Dock"
        case .openActivityMonitor: "Open Activity Monitor"
        case .revealPathInFinder: "Reveal in Finder"
        case .emptyTrash: "Empty Trash"
        case .toggleDarkMode: "Toggle Dark Mode"
        case .lockScreen: "Lock Screen"
        case .copySysInfo: "Copy System Info"
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
        case .sshToTerminal: "terminal"
        case .flushDNS: "arrow.triangle.2.circlepath"
        case .pingHost: "antenna.radiowaves.left.and.right"
        case .traceRoute: "point.topleft.down.to.point.bottomright.curvepath"
        case .dnsLookup: "magnifyingglass"
        case .networkKillConnection: "xmark.shield"
        case .purgeMemory: "memorychip"
        case .restartFinder: "arrow.clockwise"
        case .restartDock: "dock.rectangle"
        case .openActivityMonitor: "gauge.with.dots.needle.50percent"
        case .revealPathInFinder: "folder"
        case .emptyTrash: "trash"
        case .toggleDarkMode: "circle.lefthalf.filled"
        case .lockScreen: "lock"
        case .copySysInfo: "doc.on.doc"
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
        case .sshToTerminal, .flushDNS, .pingHost, .traceRoute, .dnsLookup,
             .networkKillConnection:
            .network
        case .purgeMemory, .restartFinder, .restartDock, .openActivityMonitor,
             .revealPathInFinder, .emptyTrash, .toggleDarkMode, .lockScreen,
             .copySysInfo:
            .system
        }
    }

    /// Whether this action requires the privileged helper daemon
    public var requiresHelper: Bool {
        switch self {
        case .forceEjectVolume, .flushDNS, .purgeMemory, .networkKillConnection,
             .emptyTrash:
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
             .forceEjectVolume, .unmountVolume, .dockerRemove, .networkKillConnection,
             .emptyTrash:
            true
        case .suspendProcess, .ejectVolume, .flushDNS, .purgeMemory,
             .restartFinder, .restartDock, .reniceProcess, .toggleDarkMode:
            // These are impactful but reversible or low-risk
            true
        case .resumeProcess, .copyToClipboard, .revealInFinder,
             .dockerStop, .dockerStart, .dockerRestart, .dockerPause,
             .dockerUnpause, .sshToTerminal, .pingHost, .traceRoute,
             .dnsLookup, .openActivityMonitor, .revealPathInFinder,
             .lockScreen, .copySysInfo:
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
        case .toggleDarkMode: .toggleDarkMode
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

    /// Hostname or IP address (for network actions)
    public let hostname: String?

    /// Creates an action target
    public init(
        pid: pid_t? = nil,
        name: String,
        path: String? = nil,
        volumePath: String? = nil,
        containerID: String? = nil,
        bundleIdentifier: String? = nil,
        hostname: String? = nil
    ) {
        self.pid = pid
        self.name = name
        self.path = path
        self.volumePath = volumePath
        self.containerID = containerID
        self.bundleIdentifier = bundleIdentifier
        self.hostname = hostname
    }

    /// Formatted description for audit log entries
    public var auditDescription: String {
        var parts: [String] = [name]
        if let pid { parts.append("PID \(pid)") }
        if let path { parts.append(path) }
        if let volumePath { parts.append(volumePath) }
        if let containerID { parts.append(containerID) }
        if let hostname { parts.append(hostname) }
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
