import SwiftUI
import os

// MARK: - Action Configuration

/// Persisted configuration controlling which action categories are enabled
///
/// All destructive action categories default to `false` (off). Users must
/// explicitly enable each category in Settings > Actions before those actions
/// appear in context menus, keyboard shortcuts, or the command palette.
///
/// Clipboard copy is the only category enabled by default, as it has no
/// side effects beyond writing to the pasteboard.
@MainActor
public final class ActionConfiguration: ObservableObject {
    private static let logger = Logger(subsystem: "com.processscope", category: "ActionConfiguration")

    // MARK: - Process Actions

    /// Allow SIGTERM to own-user processes
    @AppStorage("action.process.kill") public var processKillEnabled = false

    /// Allow SIGKILL (force kill) to own-user processes
    @AppStorage("action.process.forceKill") public var processForceKillEnabled = false

    /// Allow SIGSTOP/SIGCONT (suspend/resume) on processes
    @AppStorage("action.process.suspend") public var processSuspendEnabled = false

    /// Allow changing process priority via setpriority/renice
    @AppStorage("action.process.renice") public var processReniceEnabled = false

    // MARK: - Storage Actions

    /// Allow ejecting removable volumes via DiskArbitration
    @AppStorage("action.storage.eject") public var storageEjectEnabled = false

    /// Alias used by Settings UI
    public var ejectEnabled: Bool {
        get { storageEjectEnabled }
        set { storageEjectEnabled = newValue }
    }

    /// Allow force-ejecting volumes (requires helper for stubborn volumes)
    @AppStorage("action.storage.forceEject") public var storageForceEjectEnabled = false

    /// Alias used by Settings UI
    public var forceEjectEnabled: Bool {
        get { storageForceEjectEnabled }
        set { storageForceEjectEnabled = newValue }
    }

    // MARK: - Clipboard Actions

    /// Allow copying data to the system clipboard (safe, on by default)
    @AppStorage("action.clipboard.copy") public var clipboardCopyEnabled = true

    /// Alias used by Settings UI
    public var copyEnabled: Bool {
        get { clipboardCopyEnabled }
        set { clipboardCopyEnabled = newValue }
    }

    // MARK: - Docker Actions

    /// Allow stop/start/restart/pause/unpause of Docker containers
    @AppStorage("action.docker.lifecycle") public var dockerLifecycleEnabled = false

    // MARK: - Network Actions

    /// Allow network-related actions (flush DNS, kill connections)
    @AppStorage("action.network.enabled") public var networkActionsEnabled = false

    // MARK: - System Actions

    /// Allow system-wide actions (purge memory, restart Finder/Dock)
    @AppStorage("action.system.enabled") public var systemActionsEnabled = false

    // MARK: - Confirmation Behavior

    /// Always show confirmation dialog for destructive actions
    @AppStorage("action.confirm.destructive") public var alwaysConfirmDestructive = true

    /// Skip confirmation for reversible actions (suspend/resume, docker pause/unpause)
    @AppStorage("action.confirm.skipReversible") public var skipConfirmReversible = false

    // MARK: - Initialization

    public init() {}

    // MARK: - Action Gating

    /// Checks whether a specific action type is allowed by the current configuration
    /// - Parameter actionType: The action to check
    /// - Returns: `true` if the action's category is enabled, `false` otherwise
    public func isActionAllowed(_ actionType: ActionType) -> Bool {
        switch actionType {
        case .killProcess:
            return processKillEnabled
        case .forceKillProcess, .forceQuitApp:
            return processForceKillEnabled
        case .suspendProcess, .resumeProcess:
            return processSuspendEnabled
        case .killProcessGroup:
            return processKillEnabled
        case .reniceProcess:
            return processReniceEnabled
        case .ejectVolume:
            return storageEjectEnabled
        case .forceEjectVolume, .unmountVolume:
            return storageForceEjectEnabled
        case .copyToClipboard, .revealInFinder:
            return clipboardCopyEnabled
        case .dockerStop, .dockerStart, .dockerRestart, .dockerPause,
             .dockerUnpause, .dockerRemove:
            return dockerLifecycleEnabled
        case .flushDNS, .networkKillConnection:
            return networkActionsEnabled
        case .purgeMemory, .restartFinder, .restartDock:
            return systemActionsEnabled
        }
    }

    /// Whether a confirmation dialog should be shown for the given action
    /// - Parameter actionType: The action to check
    /// - Returns: `true` if confirmation is required before execution
    public func requiresConfirmation(_ actionType: ActionType) -> Bool {
        if actionType.isDestructive && alwaysConfirmDestructive {
            return true
        }
        if !actionType.isDestructive && skipConfirmReversible {
            return false
        }
        // Default: confirm everything except clipboard
        return actionType.category != .clipboard
    }

    // MARK: - Helper Requirements

    /// Set of action type raw values that require the privileged helper daemon
    public var helperRequiredActions: Set<String> {
        Set(ActionType.allCases.filter(\.requiresHelper).map(\.rawValue))
    }

    /// Checks if a given action needs the helper and the helper is not available
    /// - Parameters:
    ///   - actionType: The action to check
    ///   - helperInstalled: Whether the helper daemon is currently installed
    /// - Returns: `true` if the action is blocked by a missing helper
    public func isBlockedByMissingHelper(_ actionType: ActionType, helperInstalled: Bool) -> Bool {
        actionType.requiresHelper && !helperInstalled
    }
}
