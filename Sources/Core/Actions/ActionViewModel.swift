import SwiftUI
import os

// MARK: - Pending Action

/// Represents an action awaiting user confirmation
///
/// When a destructive or impactful action is requested, a `PendingAction`
/// is created and presented in a confirmation dialog. The user can confirm
/// or cancel before execution proceeds.
public struct PendingAction: Identifiable, Sendable {
    public let id = UUID()
    public let actionType: ActionType
    public let target: ActionTarget
    public let timestamp: Date

    /// Title displayed in the confirmation dialog header
    public let title: String
    /// Detailed description of what the action will do
    public let detail: String
    /// Label for the confirm button (e.g., "Kill", "Eject")
    public let confirmLabel: String
    /// Whether this action is destructive (renders confirm button in red)
    public let isDestructive: Bool
    /// List of affected items to display in the dialog (e.g., child processes)
    public let affectedItems: [String]

    /// Creates a pending action
    public init(
        actionType: ActionType,
        target: ActionTarget,
        title: String,
        detail: String,
        confirmLabel: String,
        isDestructive: Bool,
        affectedItems: [String] = []
    ) {
        self.actionType = actionType
        self.target = target
        self.title = title
        self.detail = detail
        self.confirmLabel = confirmLabel
        self.isDestructive = isDestructive
        self.affectedItems = affectedItems
        self.timestamp = Date()
    }
}

// MARK: - Action Error

/// Errors that can occur during action execution
public enum ActionError: LocalizedError {
    case actionNotAllowed(ActionType)
    case helperRequired(ActionType)
    case signalFailed(pid_t, Int32, Int32)
    case processNotFound(pid_t)
    case volumeNotFound(String)
    case executionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .actionNotAllowed(let type):
            "Action \"\(type.displayName)\" is not enabled. Enable it in Settings > Actions."
        case .helperRequired(let type):
            "Action \"\(type.displayName)\" requires the helper daemon. Install it in Settings > General."
        case .signalFailed(let pid, let signal, let errno):
            "Failed to send signal \(signal) to PID \(pid): errno \(errno)"
        case .processNotFound(let pid):
            "Process with PID \(pid) not found"
        case .volumeNotFound(let path):
            "Volume at \(path) not found"
        case .executionFailed(let reason):
            reason
        }
    }
}

// MARK: - Action View Model

/// Coordinates action execution with confirmation flow and audit logging
///
/// This is the central controller for all user-initiated actions. It enforces
/// the safety invariants: actions must be enabled in configuration, destructive
/// actions require confirmation, and every action is audit-logged regardless
/// of outcome.
///
/// Usage from SwiftUI views:
/// ```swift
/// Button("Kill Process") {
///     Task {
///         await actionVM.requestAction(.killProcess, target: target)
///     }
/// }
/// .confirmationDialog(
///     actionVM.pendingAction?.actionType.displayName ?? "",
///     isPresented: $actionVM.showConfirmation
/// ) {
///     Button("Confirm", role: .destructive) {
///         Task { await actionVM.confirmAction() }
///     }
/// }
/// ```
@MainActor
public final class ActionViewModel: ObservableObject {
    private static let logger = Logger(subsystem: "com.processscope", category: "ActionViewModel")

    // MARK: - Published State

    /// The action currently awaiting user confirmation, or `nil` if none
    @Published public var pendingAction: PendingAction?

    /// Whether an action is currently being executed
    @Published public var isExecuting = false

    /// Result of the most recently completed action
    @Published public var lastResult: ActionResult?

    /// Last error message, if any
    @Published public var lastErrorMessage: String?

    /// Controls the confirmation dialog presentation
    @Published public var showConfirmation = false

    // MARK: - Dependencies

    public let configuration: ActionConfiguration
    private let auditTrail: AuditTrail
    private let processActions: ProcessActionService
    private let storageActions: StorageActionService
    private let dockerService: any DockerServiceProtocol
    private let networkActions: any NetworkActionServiceProtocol
    private let systemActions: any SystemActionServiceProtocol
    private let helperConnection: HelperConnection

    /// Whether the privileged helper daemon is currently installed
    @Published public var isHelperInstalled: Bool

    /// Last ping result for display in the network detail view
    @Published public var lastPingResult: PingResult?

    /// Last traceroute result for display in the network detail view
    @Published public var lastTraceHops: [TraceHop]?

    /// Last DNS lookup result for display in the network detail view
    @Published public var lastDNSResult: DNSResult?

    /// Last system info string for clipboard copy
    @Published public var lastSysInfo: String?

    // MARK: - Initialization

    /// Creates an action view model with the given dependencies
    /// - Parameters:
    ///   - configuration: Persisted action toggles
    ///   - auditTrail: Audit log writer
    ///   - dockerService: Docker container lifecycle service
    ///   - networkActions: Network action service for SSH, ping, traceroute, DNS
    ///   - systemActions: System action service for Finder, Activity Monitor, etc.
    ///   - helperConnection: XPC connection to the privileged helper
    ///   - isHelperInstalled: Whether the helper daemon is currently installed
    public init(
        configuration: ActionConfiguration = ActionConfiguration(),
        auditTrail: AuditTrail = AuditTrail(),
        dockerService: (any DockerServiceProtocol)? = nil,
        networkActions: (any NetworkActionServiceProtocol)? = nil,
        systemActions: (any SystemActionServiceProtocol)? = nil,
        helperConnection: HelperConnection = HelperConnection(),
        isHelperInstalled: Bool = false
    ) {
        self.configuration = configuration
        self.auditTrail = auditTrail
        self.processActions = ProcessActionService()
        self.storageActions = StorageActionService()
        self.dockerService = dockerService ?? DockerService()
        self.networkActions = networkActions ?? NetworkActionService(helperConnection: helperConnection)
        self.systemActions = systemActions ?? SystemActionService(helperConnection: helperConnection)
        self.helperConnection = helperConnection
        self.isHelperInstalled = isHelperInstalled
    }

    // MARK: - Action Request Flow

    /// Requests execution of an action, showing a confirmation dialog if required
    ///
    /// This is the primary entry point for all action execution. It checks
    /// configuration gates, helper availability, and confirmation requirements
    /// before proceeding.
    ///
    /// - Parameters:
    ///   - type: The action to execute
    ///   - target: The target of the action (process, volume, etc.)
    public func requestAction(_ type: ActionType, target: ActionTarget) async {
        // Gate: is this action category enabled?
        guard configuration.isActionAllowed(type) else {
            Self.logger.info("Action \(type.rawValue) blocked — not enabled in configuration")
            lastErrorMessage = ActionError.actionNotAllowed(type).localizedDescription
            await auditTrail.log(
                action: type,
                target: target.auditDescription,
                result: .failure,
                userConfirmed: false
            )
            return
        }

        // Gate: does this action require the helper?
        if configuration.isBlockedByMissingHelper(type, helperInstalled: isHelperInstalled) {
            Self.logger.info("Action \(type.rawValue) blocked — helper not installed")
            lastErrorMessage = ActionError.helperRequired(type).localizedDescription
            await auditTrail.log(
                action: type,
                target: target.auditDescription,
                result: .failure,
                userConfirmed: false
            )
            return
        }

        // Check if confirmation is needed
        if configuration.requiresConfirmation(type) {
            let detail = buildConfirmationDescription(type: type, target: target)
            pendingAction = PendingAction(
                actionType: type,
                target: target,
                title: type.displayName + "?",
                detail: detail,
                confirmLabel: type.displayName.replacingOccurrences(of: " Process", with: "")
                    .replacingOccurrences(of: " Volume", with: ""),
                isDestructive: type.isDestructive
            )
            showConfirmation = true
        } else {
            // Execute immediately (clipboard, non-destructive actions)
            await executeAction(type, target: target, userConfirmed: false)
        }
    }

    /// Confirms and executes the pending action
    ///
    /// Called from the confirmation dialog's confirm button.
    public func confirmAction() async {
        guard let pending = pendingAction else { return }
        showConfirmation = false
        let type = pending.actionType
        let target = pending.target
        pendingAction = nil
        await executeAction(type, target: target, userConfirmed: true)
    }

    /// Cancels the pending action without executing it
    ///
    /// Called from the confirmation dialog's cancel button or dismiss.
    public func cancelAction() {
        guard let pending = pendingAction else { return }
        showConfirmation = false
        let type = pending.actionType
        let target = pending.target
        pendingAction = nil
        lastResult = .cancelled

        Task {
            await auditTrail.log(
                action: type,
                target: target.auditDescription,
                result: .cancelled,
                userConfirmed: false
            )
        }

        Self.logger.info("Action \(type.rawValue) cancelled by user")
    }

    // MARK: - Execution

    private func executeAction(_ type: ActionType, target: ActionTarget, userConfirmed: Bool) async {
        isExecuting = true
        lastErrorMessage = nil

        defer { isExecuting = false }

        do {
            try await dispatchAction(type, target: target)
            lastResult = .success
            await auditTrail.log(
                action: type,
                target: target.auditDescription,
                result: .success,
                userConfirmed: userConfirmed
            )
            Self.logger.info("Action \(type.rawValue) succeeded on \(target.name)")
        } catch {
            lastResult = .failure
            lastErrorMessage = error.localizedDescription
            await auditTrail.log(
                action: type,
                target: target.auditDescription,
                result: .failure,
                userConfirmed: userConfirmed
            )
            Self.logger.error("Action \(type.rawValue) failed on \(target.name): \(error.localizedDescription)")
        }
    }

    @MainActor
    private func dispatchAction(_ type: ActionType, target: ActionTarget) async throws {
        switch type {
        // Process actions
        case .killProcess:
            guard let pid = target.pid else { throw ActionError.processNotFound(0) }
            try await processActions.kill(pid: pid)

        case .forceKillProcess:
            guard let pid = target.pid else { throw ActionError.processNotFound(0) }
            try await processActions.forceKill(pid: pid)

        case .suspendProcess:
            guard let pid = target.pid else { throw ActionError.processNotFound(0) }
            try await processActions.suspend(pid: pid)

        case .resumeProcess:
            guard let pid = target.pid else { throw ActionError.processNotFound(0) }
            try await processActions.resume(pid: pid)

        case .killProcessGroup:
            guard let pid = target.pid else { throw ActionError.processNotFound(0) }
            try await processActions.killProcessGroup(pgid: pid)

        case .reniceProcess:
            guard let pid = target.pid else { throw ActionError.processNotFound(0) }
            // Default to lowering priority; callers can customize
            try await processActions.renice(pid: pid, priority: 10)

        case .forceQuitApp:
            if let bundleID = target.bundleIdentifier {
                try await processActions.forceQuitApp(bundleIdentifier: bundleID)
            } else if let pid = target.pid {
                try await processActions.forceKill(pid: pid)
            } else {
                throw ActionError.processNotFound(0)
            }

        // Storage actions
        case .ejectVolume:
            guard let path = target.volumePath else { throw ActionError.volumeNotFound("") }
            try await storageActions.ejectVolume(path: path)

        case .forceEjectVolume:
            guard let path = target.volumePath else { throw ActionError.volumeNotFound("") }
            try await storageActions.forceEjectVolume(path: path)

        case .unmountVolume:
            guard let path = target.volumePath else { throw ActionError.volumeNotFound("") }
            try await storageActions.unmountVolume(path: path)

        // Clipboard actions
        case .copyToClipboard:
            ClipboardService.copy(target.name)

        case .revealInFinder:
            if let path = target.path {
                ClipboardService.revealInFinder(path: path)
            }

        // Docker actions
        case .dockerStop:
            guard let containerID = target.containerID else {
                throw ActionError.executionFailed("No container ID specified")
            }
            try await dockerService.stopContainer(id: containerID)

        case .dockerStart:
            guard let containerID = target.containerID else {
                throw ActionError.executionFailed("No container ID specified")
            }
            try await dockerService.startContainer(id: containerID)

        case .dockerRestart:
            guard let containerID = target.containerID else {
                throw ActionError.executionFailed("No container ID specified")
            }
            try await dockerService.restartContainer(id: containerID)

        case .dockerPause:
            guard let containerID = target.containerID else {
                throw ActionError.executionFailed("No container ID specified")
            }
            try await dockerService.pauseContainer(id: containerID)

        case .dockerUnpause:
            guard let containerID = target.containerID else {
                throw ActionError.executionFailed("No container ID specified")
            }
            try await dockerService.unpauseContainer(id: containerID)

        case .dockerRemove:
            guard let containerID = target.containerID else {
                throw ActionError.executionFailed("No container ID specified")
            }
            try await dockerService.removeContainer(id: containerID, force: false)

        // Network actions
        case .sshToTerminal:
            let host = target.hostname ?? target.name
            try await networkActions.openSSHTerminal(host: host, user: nil, port: nil)

        case .flushDNS:
            try await networkActions.flushDNSCache()

        case .pingHost:
            let host = target.hostname ?? target.name
            let result = try await networkActions.pingHost(host, count: 5)
            lastPingResult = result

        case .traceRoute:
            let host = target.hostname ?? target.name
            let hops = try await networkActions.traceRoute(to: host)
            lastTraceHops = hops

        case .dnsLookup:
            let host = target.hostname ?? target.name
            let result = try await networkActions.lookupDNS(hostname: host)
            lastDNSResult = result

        case .networkKillConnection:
            // Kill connection requires the helper daemon to terminate a socket
            throw ActionError.executionFailed(
                "Connection termination requires the privileged helper daemon"
            )

        // System actions
        case .purgeMemory:
            try await systemActions.purgeMemory()

        case .restartFinder:
            try await systemActions.restartFinder()

        case .restartDock:
            try await systemActions.restartDock()

        case .openActivityMonitor:
            await systemActions.openActivityMonitor()

        case .revealPathInFinder:
            if let path = target.path {
                await systemActions.revealInFinder(path: path)
            }

        case .emptyTrash:
            try await systemActions.emptyTrash()

        case .toggleDarkMode:
            try await systemActions.toggleDarkMode()

        case .lockScreen:
            await systemActions.lockScreen()

        case .copySysInfo:
            let info = await systemActions.copySysInfo()
            lastSysInfo = info
            ClipboardService.copy(info)
        }
    }

    // MARK: - Confirmation Description Builder

    private func buildConfirmationDescription(type: ActionType, target: ActionTarget) -> String {
        switch type {
        case .killProcess:
            "This will send SIGTERM to \"\(target.name)\"" +
            (target.pid.map { " (PID \($0))" } ?? "") +
            ". The process will be asked to terminate gracefully."

        case .forceKillProcess:
            "This will send SIGKILL to \"\(target.name)\"" +
            (target.pid.map { " (PID \($0))" } ?? "") +
            ". The process will be terminated immediately without cleanup."

        case .suspendProcess:
            "This will suspend \"\(target.name)\"" +
            (target.pid.map { " (PID \($0))" } ?? "") +
            ". The process will freeze until resumed."

        case .resumeProcess:
            "This will resume \"\(target.name)\"" +
            (target.pid.map { " (PID \($0))" } ?? "") + "."

        case .killProcessGroup:
            "This will terminate all processes in the group of \"\(target.name)\"" +
            (target.pid.map { " (PGID \($0))" } ?? "") + "."

        case .reniceProcess:
            "This will change the scheduling priority of \"\(target.name)\"" +
            (target.pid.map { " (PID \($0))" } ?? "") + "."

        case .forceQuitApp:
            "This will force quit \"\(target.name)\". Unsaved work may be lost."

        case .ejectVolume:
            "This will eject the volume at \(target.volumePath ?? target.name)."

        case .forceEjectVolume:
            "This will forcefully eject the volume at \(target.volumePath ?? target.name). " +
            "Open files on this volume may be affected."

        case .unmountVolume:
            "This will unmount the volume at \(target.volumePath ?? target.name)."

        case .dockerStop:
            "This will stop container \"\(target.name)\"" +
            (target.containerID.map { " (\($0))" } ?? "") +
            ". The container can be started again later."

        case .dockerStart:
            "This will start container \"\(target.name)\"."

        case .dockerRestart:
            "This will restart container \"\(target.name)\"" +
            (target.containerID.map { " (\($0))" } ?? "") +
            ". Running processes inside will be stopped and restarted."

        case .dockerPause:
            "This will pause container \"\(target.name)\". " +
            "All processes inside will be frozen until unpaused."

        case .dockerUnpause:
            "This will unpause container \"\(target.name)\"."

        case .dockerRemove:
            "This will permanently remove container \"\(target.name)\"" +
            (target.containerID.map { " (\($0))" } ?? "") +
            ". This action cannot be undone."

        case .flushDNS:
            "This will clear the DNS resolver cache. All cached DNS entries will be flushed."

        case .purgeMemory:
            "This clears the filesystem cache. Apps will need to re-read from disk, " +
            "which may briefly slow things down."

        case .restartFinder:
            "Finder will quit and relaunch. Open Finder windows will close and reopen."

        case .restartDock:
            "The Dock will disappear briefly and reappear. Running apps are not affected."

        case .emptyTrash:
            "This will permanently delete all items in the Trash. This cannot be undone."

        case .toggleDarkMode:
            "This will toggle the system appearance between light and dark mode."

        case .networkKillConnection:
            "This will terminate the network connection for \"\(target.name)\". " +
            "The remote endpoint may attempt to reconnect."

        default:
            "Execute \(type.displayName) on \(target.name)?"
        }
    }

    // MARK: - Convenience Methods

    /// Recent audit entries for display in the UI
    public func recentAuditEntries(limit: Int = 50) async -> [AuditEntry] {
        await auditTrail.recentEntries(limit: limit)
    }

    // MARK: - Process Convenience Methods

    /// Requests a kill or force-kill action on a process record
    /// - Parameters:
    ///   - process: The process to kill
    ///   - force: If `true`, sends SIGKILL; otherwise sends SIGTERM
    public func requestKill(process: ProcessRecord, force: Bool) {
        let type: ActionType = force ? .forceKillProcess : .killProcess
        let target = ActionTarget(
            pid: process.pid,
            name: process.name,
            path: process.executablePath
        )
        Task { await requestAction(type, target: target) }
    }

    /// Requests a suspend action on a process record
    /// - Parameter process: The process to suspend
    public func requestSuspend(process: ProcessRecord) {
        let target = ActionTarget(
            pid: process.pid,
            name: process.name,
            path: process.executablePath
        )
        Task { await requestAction(.suspendProcess, target: target) }
    }

    /// Requests a resume action on a process record
    /// - Parameter process: The process to resume
    public func requestResume(process: ProcessRecord) {
        let target = ActionTarget(
            pid: process.pid,
            name: process.name,
            path: process.executablePath
        )
        Task { await requestAction(.resumeProcess, target: target) }
    }

    /// Requests an inspect action on a process record (placeholder for inspector panel)
    /// - Parameter process: The process to inspect
    public func requestInspect(process: ProcessRecord) {
        // Inspect does not require confirmation or audit logging;
        // it simply opens the process inspector panel. The UI layer
        // will handle the actual presentation.
        Self.logger.info("Inspect requested for PID \(process.pid)")
    }

    // MARK: - Network Convenience Methods

    /// Opens an SSH terminal session to the given host
    /// - Parameters:
    ///   - host: The remote hostname or IP address
    ///   - user: Optional username for the SSH connection
    ///   - port: Optional port number (defaults to 22)
    public func requestSSH(host: String, user: String? = nil, port: Int? = nil) {
        let target = ActionTarget(name: host, hostname: host)
        Task { await requestAction(.sshToTerminal, target: target) }
    }

    /// Requests a ping action on a host
    /// - Parameter host: The hostname or IP address to ping
    public func requestPing(host: String) {
        let target = ActionTarget(name: host, hostname: host)
        Task { await requestAction(.pingHost, target: target) }
    }

    /// Requests a traceroute action on a host
    /// - Parameter host: The hostname or IP address to trace
    public func requestTraceRoute(host: String) {
        let target = ActionTarget(name: host, hostname: host)
        Task { await requestAction(.traceRoute, target: target) }
    }

    /// Requests a DNS lookup for a hostname
    /// - Parameter hostname: The hostname to look up
    public func requestDNSLookup(hostname: String) {
        let target = ActionTarget(name: hostname, hostname: hostname)
        Task { await requestAction(.dnsLookup, target: target) }
    }

    /// Requests a DNS cache flush
    public func requestFlushDNS() {
        let target = ActionTarget(name: "system")
        Task { await requestAction(.flushDNS, target: target) }
    }

    // MARK: - System Convenience Methods

    /// Requests a memory purge
    public func requestPurgeMemory() {
        let target = ActionTarget(name: "system")
        Task { await requestAction(.purgeMemory, target: target) }
    }

    /// Requests a Finder restart
    public func requestRestartFinder() {
        let target = ActionTarget(name: "Finder")
        Task { await requestAction(.restartFinder, target: target) }
    }

    /// Requests a Dock restart
    public func requestRestartDock() {
        let target = ActionTarget(name: "Dock")
        Task { await requestAction(.restartDock, target: target) }
    }

    /// Opens Activity Monitor
    public func requestOpenActivityMonitor() {
        let target = ActionTarget(name: "Activity Monitor")
        Task { await requestAction(.openActivityMonitor, target: target) }
    }

    /// Reveals a path in Finder
    /// - Parameter path: The absolute file path to reveal
    public func requestRevealInFinder(path: String) {
        let target = ActionTarget(name: path, path: path)
        Task { await requestAction(.revealPathInFinder, target: target) }
    }

    /// Requests emptying the Trash
    public func requestEmptyTrash() {
        let target = ActionTarget(name: "Trash")
        Task { await requestAction(.emptyTrash, target: target) }
    }

    /// Toggles dark mode
    public func requestToggleDarkMode() {
        let target = ActionTarget(name: "Dark Mode")
        Task { await requestAction(.toggleDarkMode, target: target) }
    }

    /// Locks the screen
    public func requestLockScreen() {
        let target = ActionTarget(name: "Screen Lock")
        Task { await requestAction(.lockScreen, target: target) }
    }

    /// Copies system info to clipboard
    public func requestCopySysInfo() {
        let target = ActionTarget(name: "System Info")
        Task { await requestAction(.copySysInfo, target: target) }
    }
}
