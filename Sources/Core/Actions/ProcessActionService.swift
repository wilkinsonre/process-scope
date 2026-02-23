import Foundation
import AppKit
import os

// MARK: - Process Action Service

/// Executes process-level actions: kill, force kill, suspend, resume, renice
///
/// For the current user's processes, signals are sent directly via `kill(2)`.
/// For processes owned by other users, the privileged helper daemon is required
/// (routed through ``HelperConnection``). This service handles only the direct
/// signal path; helper routing is handled by ``ActionViewModel``.
///
/// All methods are isolated to the actor and throw on failure with errno context.
public actor ProcessActionService {
    private static let logger = Logger(subsystem: "com.processscope", category: "ProcessActionService")

    public init() {}

    // MARK: - Kill (SIGTERM)

    /// Sends SIGTERM to a process, requesting graceful termination
    /// - Parameter pid: The process ID to signal
    /// - Throws: ``ActionError/signalFailed(_:_:_:)`` if `kill(2)` returns non-zero
    public func kill(pid: pid_t) async throws {
        Self.logger.info("Sending SIGTERM to PID \(pid)")
        let result = Darwin.kill(pid, SIGTERM)
        guard result == 0 else {
            let err = errno
            Self.logger.error("SIGTERM to PID \(pid) failed: errno \(err)")
            throw ActionError.signalFailed(pid, SIGTERM, err)
        }
    }

    // MARK: - Force Kill (SIGKILL)

    /// Sends SIGKILL to a process, terminating it immediately
    ///
    /// The process cannot catch or ignore SIGKILL. Use this only when
    /// SIGTERM has failed or the process is unresponsive.
    /// - Parameter pid: The process ID to signal
    /// - Throws: ``ActionError/signalFailed(_:_:_:)`` if `kill(2)` returns non-zero
    public func forceKill(pid: pid_t) async throws {
        Self.logger.info("Sending SIGKILL to PID \(pid)")
        let result = Darwin.kill(pid, SIGKILL)
        guard result == 0 else {
            let err = errno
            Self.logger.error("SIGKILL to PID \(pid) failed: errno \(err)")
            throw ActionError.signalFailed(pid, SIGKILL, err)
        }
    }

    // MARK: - Suspend (SIGSTOP)

    /// Sends SIGSTOP to a process, freezing its execution
    ///
    /// The process will not consume CPU until resumed with ``resume(pid:)``.
    /// This is the undo counterpart of resume.
    /// - Parameter pid: The process ID to signal
    /// - Throws: ``ActionError/signalFailed(_:_:_:)`` if `kill(2)` returns non-zero
    public func suspend(pid: pid_t) async throws {
        Self.logger.info("Sending SIGSTOP to PID \(pid)")
        let result = Darwin.kill(pid, SIGSTOP)
        guard result == 0 else {
            let err = errno
            Self.logger.error("SIGSTOP to PID \(pid) failed: errno \(err)")
            throw ActionError.signalFailed(pid, SIGSTOP, err)
        }
    }

    // MARK: - Resume (SIGCONT)

    /// Sends SIGCONT to a suspended process, resuming its execution
    ///
    /// This is the undo counterpart of ``suspend(pid:)``.
    /// - Parameter pid: The process ID to signal
    /// - Throws: ``ActionError/signalFailed(_:_:_:)`` if `kill(2)` returns non-zero
    public func resume(pid: pid_t) async throws {
        Self.logger.info("Sending SIGCONT to PID \(pid)")
        let result = Darwin.kill(pid, SIGCONT)
        guard result == 0 else {
            let err = errno
            Self.logger.error("SIGCONT to PID \(pid) failed: errno \(err)")
            throw ActionError.signalFailed(pid, SIGCONT, err)
        }
    }

    // MARK: - Kill Process Group

    /// Sends SIGTERM to all processes in a process group
    ///
    /// The negative PID convention of `kill(2)` is used: `kill(-pgid, signal)`
    /// sends the signal to every process in the group.
    /// - Parameter pgid: The process group ID to signal
    /// - Throws: ``ActionError/signalFailed(_:_:_:)`` if `kill(2)` returns non-zero
    public func killProcessGroup(pgid: pid_t) async throws {
        Self.logger.info("Sending SIGTERM to process group \(pgid)")
        let result = Darwin.kill(-pgid, SIGTERM)
        guard result == 0 else {
            let err = errno
            Self.logger.error("SIGTERM to PGID \(pgid) failed: errno \(err)")
            throw ActionError.signalFailed(pgid, SIGTERM, err)
        }
    }

    // MARK: - Renice (setpriority)

    /// Changes the scheduling priority of a process
    ///
    /// Priority values range from -20 (highest) to 20 (lowest). Raising priority
    /// (lowering the nice value) requires root privileges via the helper daemon.
    /// Lowering priority (raising the nice value) works for own-user processes.
    /// - Parameters:
    ///   - pid: The process ID to renice
    ///   - priority: The new nice value (-20 to 20)
    /// - Throws: ``ActionError/signalFailed(_:_:_:)`` if `setpriority(2)` fails
    public func renice(pid: pid_t, priority: Int32) async throws {
        Self.logger.info("Setting priority of PID \(pid) to \(priority)")
        let result = setpriority(PRIO_PROCESS, id_t(pid), priority)
        guard result == 0 else {
            let err = errno
            Self.logger.error("setpriority for PID \(pid) failed: errno \(err)")
            throw ActionError.signalFailed(pid, 0, err)
        }
    }

    // MARK: - Force Quit Application

    /// Force-terminates a macOS application by its bundle identifier
    ///
    /// Uses `NSRunningApplication.forceTerminate()` which sends a SIGKILL
    /// to the application process.
    /// - Parameter bundleIdentifier: The CFBundleIdentifier of the app to quit
    /// - Throws: ``ActionError/executionFailed(_:)`` if the app is not running or termination fails
    @MainActor
    public func forceQuitApp(bundleIdentifier: String) async throws {
        Self.logger.info("Force quitting app: \(bundleIdentifier)")
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        guard let app = apps.first else {
            throw ActionError.executionFailed(
                "No running application found with bundle identifier \(bundleIdentifier)"
            )
        }
        let terminated = app.forceTerminate()
        guard terminated else {
            throw ActionError.executionFailed(
                "Failed to force terminate \(bundleIdentifier)"
            )
        }
    }
}
