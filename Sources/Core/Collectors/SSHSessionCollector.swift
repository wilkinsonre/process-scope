import Foundation
import os

// MARK: - SSH Session Data Types

/// Represents an active SSH or mosh session detected by process inspection
public struct SSHSession: Codable, Sendable, Identifiable {
    public var id: String { "\(pid)-\(host ?? "unknown")" }
    public let pid: pid_t
    public let user: String?
    public let host: String?
    public let port: UInt16
    public let identityFile: String?
    public let tunnels: [SSHTunnel]
    public let startTime: Date?

    public init(pid: pid_t, user: String?, host: String?, port: UInt16 = 22,
                identityFile: String? = nil, tunnels: [SSHTunnel] = [],
                startTime: Date? = nil) {
        self.pid = pid
        self.user = user
        self.host = host
        self.port = port
        self.identityFile = identityFile
        self.tunnels = tunnels
        self.startTime = startTime
    }

    /// Human-readable connection string
    public var connectionString: String {
        var parts: [String] = []
        if let user { parts.append(user + "@") }
        parts.append(host ?? "unknown")
        if port != 22 { parts.append(":\(port)") }
        return parts.joined()
    }
}

/// Represents an SSH tunnel (-L, -R, or -D flag)
public enum SSHTunnel: Codable, Sendable, Equatable {
    case local(String)
    case remote(String)
    case dynamic(String)

    public var displayString: String {
        switch self {
        case .local(let spec): return "L:\(spec)"
        case .remote(let spec): return "R:\(spec)"
        case .dynamic(let spec): return "D:\(spec)"
        }
    }
}

/// Parsed SSH arguments extracted from process argv
public struct SSHParsedArgs: Sendable {
    public let user: String?
    public let host: String?
    public let port: UInt16
    public let tunnels: [SSHTunnel]
    public let identityFile: String?
}

// MARK: - SSH Session Collector Protocol

/// Protocol for SSH session collection, enabling mock injection for tests
public protocol SSHSessionCollecting: AnyObject, Sendable {
    func collectSessions() async -> [SSHSession]
}

// MARK: - SSH Session Collector

/// Detects active SSH sessions by inspecting running ssh/mosh-client processes
/// and parsing their command-line arguments for connection details.
///
/// Subscribes to the Extended polling tier (3s). Uses process inspection via
/// `SysctlWrapper` and `LibProcWrapper` -- no privileged access required for
/// the current user's own ssh processes.
public actor SSHSessionCollector: SystemCollector, SSHSessionCollecting {
    public nonisolated let id = "ssh-sessions"
    public nonisolated let displayName = "SSH Sessions"
    public nonisolated let requiresHelper = false
    public nonisolated var isAvailable: Bool { true }

    private let logger = Logger(subsystem: "com.processscope", category: "SSHSessionCollector")
    private var _isActive = false

    public init() {}

    public func activate() {
        _isActive = true
        logger.info("SSHSessionCollector activated")
    }

    public func deactivate() {
        _isActive = false
        logger.info("SSHSessionCollector deactivated")
    }

    // MARK: - Collection

    /// Collects all visible SSH and mosh sessions from the process list
    public func collectSessions() async -> [SSHSession] {
        guard _isActive else { return [] }

        let allProcs = SysctlWrapper.allProcesses()
        var sessions: [SSHSession] = []

        for kinfo in allProcs {
            let pid = kinfo.kp_proc.p_pid
            guard pid > 0 else { continue }

            let name = LibProcWrapper.processName(for: pid)
            guard let name, (name == "ssh" || name == "mosh-client") else { continue }

            guard let argsResult = SysctlWrapper.processArguments(for: pid) else { continue }
            // Skip argv[0] (the executable path itself) when parsing
            let args = Array(argsResult.arguments.dropFirst())
            let parsed = SSHSessionCollector.parseSSHArgs(args)

            // Extract start time from kinfo_proc
            let startTime: Date?
            let tv = kinfo.kp_proc.p_starttime
            if tv.tv_sec > 0 {
                startTime = Date(timeIntervalSince1970: Double(tv.tv_sec) + Double(tv.tv_usec) / 1_000_000)
            } else {
                startTime = nil
            }

            sessions.append(SSHSession(
                pid: pid,
                user: parsed.user,
                host: parsed.host,
                port: parsed.port,
                identityFile: parsed.identityFile,
                tunnels: parsed.tunnels,
                startTime: startTime
            ))
        }

        return sessions
    }

    // MARK: - Argument Parsing

    /// Parses SSH command-line arguments to extract connection details
    ///
    /// Handles:
    /// - `[user@]host` destination
    /// - `-p port` port specification
    /// - `-i identity_file` key file
    /// - `-L local_forward`, `-R remote_forward`, `-D dynamic` tunnels
    ///
    /// - Parameter args: The argv array (excluding argv[0])
    /// - Returns: Parsed SSH arguments
    public static func parseSSHArgs(_ args: [String]) -> SSHParsedArgs {
        var user: String?
        var host: String?
        var port: UInt16 = 22
        var tunnels: [SSHTunnel] = []
        var identityFile: String?

        // Flags that consume the next argument
        let flagsWithValue: Set<String> = [
            "-p", "-i", "-L", "-R", "-D", "-l", "-o", "-b", "-c",
            "-E", "-e", "-F", "-I", "-J", "-m", "-O", "-Q", "-S", "-W", "-w"
        ]

        var i = 0
        while i < args.count {
            let arg = args[i]

            if flagsWithValue.contains(arg), i + 1 < args.count {
                let value = args[i + 1]
                switch arg {
                case "-p":
                    port = UInt16(value) ?? 22
                case "-i":
                    identityFile = value
                case "-L":
                    tunnels.append(.local(value))
                case "-R":
                    tunnels.append(.remote(value))
                case "-D":
                    tunnels.append(.dynamic(value))
                case "-l":
                    user = value
                default:
                    break
                }
                i += 2
                continue
            }

            // Skip flags that do not consume a value
            if arg.hasPrefix("-") {
                i += 1
                continue
            }

            // Non-flag argument is [user@]host
            let parts = arg.split(separator: "@", maxSplits: 1)
            if parts.count == 2 {
                user = user ?? String(parts[0])
                host = String(parts[1])
            } else {
                host = arg
            }
            i += 1
        }

        return SSHParsedArgs(
            user: user,
            host: host,
            port: port,
            tunnels: tunnels,
            identityFile: identityFile
        )
    }
}

// MARK: - Mock SSH Session Collector

/// Mock collector for testing SSH session UI without real processes
public final class MockSSHSessionCollector: SSHSessionCollecting, SystemCollector, @unchecked Sendable {
    public let id = "ssh-sessions-mock"
    public let displayName = "SSH Sessions (Mock)"
    public let requiresHelper = false
    public var isAvailable: Bool = true

    public var mockSessions: [SSHSession] = []
    public private(set) var activateCount = 0
    public private(set) var deactivateCount = 0

    public init() {}

    public func activate() async { activateCount += 1 }
    public func deactivate() async { deactivateCount += 1 }

    public func collectSessions() async -> [SSHSession] { mockSessions }
}
