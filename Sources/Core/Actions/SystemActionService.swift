import Foundation
import AppKit
import os

// MARK: - System Action Service Protocol

/// Protocol for system-level actions, enabling mock injection for tests
public protocol SystemActionServiceProtocol: Sendable {
    /// Reveals a file or directory in Finder
    func revealInFinder(path: String) async
    /// Opens Activity Monitor.app
    func openActivityMonitor() async
    /// Empties the Trash via AppleScript (requires elevated privileges)
    func emptyTrash() async throws
    /// Toggles system-wide dark mode via AppleScript
    func toggleDarkMode() async throws
    /// Locks the screen
    func lockScreen() async
    /// Collects and returns a formatted system information string
    func copySysInfo() async -> String
    /// Restarts the Finder process
    func restartFinder() async throws
    /// Restarts the Dock process
    func restartDock() async throws
    /// Purges disk caches (requires privileged helper)
    func purgeMemory() async throws
}

// MARK: - System Action Error

/// Errors specific to system action operations
public enum SystemActionError: LocalizedError {
    case appleScriptFailed(String)
    case commandFailed(String, Int32)
    case helperRequired

    public var errorDescription: String? {
        switch self {
        case .appleScriptFailed(let detail):
            "AppleScript failed: \(detail)"
        case .commandFailed(let command, let exitCode):
            "Command '\(command)' failed with exit code \(exitCode)"
        case .helperRequired:
            "This action requires the privileged helper daemon"
        }
    }
}

// MARK: - System Action Service

/// Executes system-level actions: reveal in Finder, Activity Monitor, empty trash,
/// dark mode toggle, lock screen, system info collection, restart services, purge memory
///
/// Most actions use NSWorkspace or AppleScript for execution. The `purgeMemory`
/// action routes through the privileged helper daemon since it requires sudo.
///
/// Thread safety is guaranteed by actor isolation.
public actor SystemActionService: SystemActionServiceProtocol {
    private static let logger = Logger(subsystem: "com.processscope", category: "SystemActionService")

    private let helperConnection: HelperConnection

    /// Creates a system action service
    /// - Parameter helperConnection: XPC connection to the privileged helper
    public init(helperConnection: HelperConnection = HelperConnection()) {
        self.helperConnection = helperConnection
    }

    // MARK: - Reveal in Finder

    /// Reveals a file or directory in Finder by selecting it
    ///
    /// Uses `NSWorkspace.shared.selectFile` to open a Finder window
    /// with the specified item selected.
    ///
    /// - Parameter path: The absolute path to the file or directory to reveal
    @MainActor
    public func revealInFinder(path: String) async {
        Self.logger.info("Revealing in Finder: \(path)")
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Open Activity Monitor

    /// Opens Activity Monitor.app
    ///
    /// Uses `NSWorkspace` to launch Activity Monitor from its standard
    /// location in /System/Applications/Utilities/.
    @MainActor
    public func openActivityMonitor() async {
        Self.logger.info("Opening Activity Monitor")
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.open(url)
    }

    // MARK: - Empty Trash

    /// Empties the Trash via AppleScript
    ///
    /// Tells the Finder to empty the trash. This is a destructive operation
    /// that permanently deletes all items in the trash. Requires confirmation.
    ///
    /// - Throws: ``SystemActionError/appleScriptFailed(_:)`` if the AppleScript fails
    public func emptyTrash() async throws {
        Self.logger.info("Emptying Trash via AppleScript")
        try await runAppleScript("tell application \"Finder\" to empty trash")
    }

    // MARK: - Toggle Dark Mode

    /// Toggles the system-wide appearance between light and dark mode
    ///
    /// Uses AppleScript to toggle the System Events `dark mode` property.
    /// This is a reversible operation (its own undo).
    ///
    /// - Throws: ``SystemActionError/appleScriptFailed(_:)`` if the AppleScript fails
    public func toggleDarkMode() async throws {
        Self.logger.info("Toggling dark mode")
        let script = """
        tell application "System Events"
            tell appearance preferences
                set dark mode to not dark mode
            end tell
        end tell
        """
        try await runAppleScript(script)
    }

    // MARK: - Lock Screen

    /// Locks the screen
    ///
    /// Uses the `/usr/bin/pmset` command or CGSession approach to trigger
    /// the lock screen. Falls back to AppleScript if needed.
    @MainActor
    public func lockScreen() async {
        Self.logger.info("Locking screen")
        // Use the system command to lock the screen
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = ["displaysleepnow"]
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            Self.logger.error("Failed to lock screen via pmset: \(error.localizedDescription)")
        }
    }

    // MARK: - System Info

    /// Collects and returns a formatted system information string
    ///
    /// Gathers macOS version, hardware model, CPU, memory, and uptime
    /// information into a human-readable string suitable for clipboard copy.
    ///
    /// - Returns: Formatted system information string
    public func copySysInfo() async -> String {
        Self.logger.info("Collecting system information")
        return Self.collectSystemInfo()
    }

    /// Collects system information from various sources
    ///
    /// Uses `ProcessInfo`, `sysctl`, and other system APIs to gather
    /// comprehensive system details.
    ///
    /// - Returns: Formatted multi-line system information string
    public static func collectSystemInfo() -> String {
        let processInfo = ProcessInfo.processInfo

        // macOS version
        let osVersion = processInfo.operatingSystemVersionString

        // Host name
        let hostName = processInfo.hostName

        // Physical memory
        let physicalMemory = processInfo.physicalMemory
        let memoryFormatter = ByteCountFormatter()
        memoryFormatter.countStyle = .memory
        let memoryString = memoryFormatter.string(fromByteCount: Int64(physicalMemory))

        // CPU count
        let cpuCount = processInfo.processorCount
        let activeCPUCount = processInfo.activeProcessorCount

        // Uptime
        let uptime = processInfo.systemUptime
        let uptimeString = formatUptime(uptime)

        // Thermal state
        let thermalState: String
        switch processInfo.thermalState {
        case .nominal: thermalState = "Nominal"
        case .fair: thermalState = "Fair"
        case .serious: thermalState = "Serious"
        case .critical: thermalState = "Critical"
        @unknown default: thermalState = "Unknown"
        }

        // Build the info string
        var lines: [String] = []
        lines.append("ProcessScope System Information")
        lines.append("==============================")
        lines.append("macOS: \(osVersion)")
        lines.append("Host: \(hostName)")
        lines.append("Memory: \(memoryString)")
        lines.append("CPUs: \(cpuCount) total, \(activeCPUCount) active")
        lines.append("Uptime: \(uptimeString)")
        lines.append("Thermal State: \(thermalState)")
        lines.append("Architecture: \(machineArchitecture())")

        return lines.joined(separator: "\n")
    }

    // MARK: - Restart Finder

    /// Restarts the Finder process
    ///
    /// Sends `killall Finder` which causes macOS to automatically relaunch
    /// Finder. Open Finder windows will close and reopen.
    ///
    /// - Throws: ``SystemActionError/commandFailed(_:_:)`` if killall fails
    public func restartFinder() async throws {
        Self.logger.info("Restarting Finder")
        try await runKillall("Finder")
    }

    // MARK: - Restart Dock

    /// Restarts the Dock process
    ///
    /// Sends `killall Dock` which causes macOS to automatically relaunch
    /// the Dock. The Dock will briefly disappear and reappear.
    ///
    /// - Throws: ``SystemActionError/commandFailed(_:_:)`` if killall fails
    public func restartDock() async throws {
        Self.logger.info("Restarting Dock")
        try await runKillall("Dock")
    }

    // MARK: - Purge Memory

    /// Purges the disk cache
    ///
    /// Routes through the privileged helper daemon to execute `sudo purge`.
    /// Applications will need to re-read from disk, which may briefly
    /// slow things down.
    ///
    /// - Throws: ``HelperError`` if the helper is unavailable or the operation fails
    public func purgeMemory() async throws {
        Self.logger.info("Requesting memory purge via helper")
        try await helperConnection.purgeMemory()
    }

    // MARK: - Private Helpers

    /// Runs an AppleScript string and throws on failure
    /// - Parameter source: The AppleScript source code
    /// - Throws: ``SystemActionError/appleScriptFailed(_:)`` if execution fails
    private func runAppleScript(_ source: String) async throws {
        var errorInfo: NSDictionary?
        let script = NSAppleScript(source: source)
        script?.executeAndReturnError(&errorInfo)

        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            throw SystemActionError.appleScriptFailed(message)
        }
    }

    /// Runs `killall` for the specified process name
    /// - Parameter processName: The name of the process to kill
    /// - Throws: ``SystemActionError/commandFailed(_:_:)`` if killall fails
    private func runKillall(_ processName: String) async throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = [processName]

        let pipe = Pipe()
        task.standardError = pipe

        do {
            try task.run()
        } catch {
            throw SystemActionError.commandFailed("killall \(processName)", -1)
        }

        task.waitUntilExit()

        if task.terminationStatus != 0 {
            let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorStr = String(data: errorData, encoding: .utf8) ?? ""
            Self.logger.error("killall \(processName) failed: \(errorStr)")
            throw SystemActionError.commandFailed(
                "killall \(processName)",
                task.terminationStatus
            )
        }
    }

    // MARK: - Utility

    /// Formats an uptime interval as a human-readable string
    /// - Parameter seconds: The uptime in seconds
    /// - Returns: Formatted string like "3d 12h 45m"
    private static func formatUptime(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let days = totalSeconds / 86400
        let hours = (totalSeconds % 86400) / 3600
        let minutes = (totalSeconds % 3600) / 60

        var parts: [String] = []
        if days > 0 { parts.append("\(days)d") }
        if hours > 0 { parts.append("\(hours)h") }
        parts.append("\(minutes)m")

        return parts.joined(separator: " ")
    }

    /// Returns the machine architecture string
    /// - Returns: Architecture identifier (e.g., "arm64" or "x86_64")
    private static func machineArchitecture() -> String {
        #if arch(arm64)
        return "Apple Silicon (arm64)"
        #elseif arch(x86_64)
        return "Intel (x86_64)"
        #else
        return "Unknown"
        #endif
    }
}

// MARK: - Mock System Action Service

/// Mock implementation for testing system actions without executing real commands
public actor MockSystemActionService: SystemActionServiceProtocol {
    public var revealedPaths: [String] = []
    public var activityMonitorOpened = false
    public var trashEmptied = false
    public var darkModeToggled = false
    public var screenLocked = false
    public var sysInfoCollected = false
    public var finderRestarted = false
    public var dockRestarted = false
    public var memoryPurged = false
    public var shouldThrowOnEmptyTrash = false
    public var shouldThrowOnDarkMode = false
    public var shouldThrowOnRestartFinder = false
    public var shouldThrowOnRestartDock = false
    public var shouldThrowOnPurge = false
    public var mockSysInfo = "Mock System Info"

    public init() {}

    public func revealInFinder(path: String) async {
        revealedPaths.append(path)
    }

    public func openActivityMonitor() async {
        activityMonitorOpened = true
    }

    public func emptyTrash() async throws {
        if shouldThrowOnEmptyTrash {
            throw SystemActionError.appleScriptFailed("Mock: empty trash failed")
        }
        trashEmptied = true
    }

    public func toggleDarkMode() async throws {
        if shouldThrowOnDarkMode {
            throw SystemActionError.appleScriptFailed("Mock: toggle dark mode failed")
        }
        darkModeToggled = true
    }

    public func lockScreen() async {
        screenLocked = true
    }

    public func copySysInfo() async -> String {
        sysInfoCollected = true
        return mockSysInfo
    }

    public func restartFinder() async throws {
        if shouldThrowOnRestartFinder {
            throw SystemActionError.commandFailed("killall Finder", 1)
        }
        finderRestarted = true
    }

    public func restartDock() async throws {
        if shouldThrowOnRestartDock {
            throw SystemActionError.commandFailed("killall Dock", 1)
        }
        dockRestarted = true
    }

    public func purgeMemory() async throws {
        if shouldThrowOnPurge {
            throw SystemActionError.helperRequired
        }
        memoryPurged = true
    }
}
