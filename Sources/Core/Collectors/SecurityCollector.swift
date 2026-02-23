import Foundation
import os

// MARK: - Security Item Status

/// Status of an individual security feature
public enum SecurityItemStatus: String, Codable, Sendable {
    /// The feature is enabled and protecting the system
    case enabled
    /// The feature is disabled
    case disabled
    /// The status could not be determined (insufficient permissions, API unavailable)
    case unknown
}

// MARK: - Security Snapshot

/// A point-in-time snapshot of the system's security posture
public struct SecuritySnapshot: Codable, Sendable {
    /// System Integrity Protection (SIP) status
    public let sipStatus: SecurityItemStatus

    /// FileVault disk encryption status
    public let fileVaultStatus: SecurityItemStatus

    /// Application Firewall status
    public let firewallStatus: SecurityItemStatus

    /// Gatekeeper status (app notarization enforcement)
    public let gatekeeperStatus: SecurityItemStatus

    /// Remote Login (SSH server) enabled status
    public let remoteLoginEnabled: SecurityItemStatus

    /// Screen Sharing enabled status
    public let screenSharingEnabled: SecurityItemStatus

    /// Timestamp of collection
    public let timestamp: Date

    public init(
        sipStatus: SecurityItemStatus = .unknown,
        fileVaultStatus: SecurityItemStatus = .unknown,
        firewallStatus: SecurityItemStatus = .unknown,
        gatekeeperStatus: SecurityItemStatus = .unknown,
        remoteLoginEnabled: SecurityItemStatus = .unknown,
        screenSharingEnabled: SecurityItemStatus = .unknown,
        timestamp: Date = Date()
    ) {
        self.sipStatus = sipStatus
        self.fileVaultStatus = fileVaultStatus
        self.firewallStatus = firewallStatus
        self.gatekeeperStatus = gatekeeperStatus
        self.remoteLoginEnabled = remoteLoginEnabled
        self.screenSharingEnabled = screenSharingEnabled
        self.timestamp = timestamp
    }

    /// Overall security rating based on feature status
    public var overallRating: SecurityRating {
        let items: [SecurityItemStatus] = [sipStatus, fileVaultStatus, firewallStatus, gatekeeperStatus]
        let enabledCount = items.filter { $0 == .enabled }.count
        let disabledCount = items.filter { $0 == .disabled }.count

        if disabledCount == 0 && enabledCount == items.count {
            return .good
        } else if disabledCount > 0 {
            return .reviewNeeded
        } else {
            return .partial
        }
    }
}

/// Overall security posture rating
public enum SecurityRating: String, Codable, Sendable {
    /// All key security features are enabled
    case good = "Good"
    /// Some features could not be determined but none are known-disabled
    case partial = "Partial"
    /// One or more security features are disabled
    case reviewNeeded = "Review Needed"
}

// MARK: - Security Collector Protocol

/// Protocol for security posture collection, enabling mock injection for tests
public protocol SecurityCollecting: SystemCollector, Sendable {
    /// Collects the current security posture snapshot
    func collect() async -> SecuritySnapshot
}

// MARK: - Security Collector

/// Collects system security posture information
///
/// Checks SIP, FileVault, Firewall, and Gatekeeper status using a combination
/// of plist parsing and file system heuristics. Falls back gracefully when
/// shell commands or file access is unavailable.
///
/// Registered with ``SecurityModule`` on the slow (10s) polling tier.
public actor SecurityCollector: SecurityCollecting {
    public nonisolated let id = "security"
    public nonisolated let displayName = "Security"
    public nonisolated let requiresHelper = false
    public nonisolated var isAvailable: Bool { true }

    private let logger = Logger(subsystem: "com.processscope", category: "SecurityCollector")
    private var _isActive = false

    public init() {}

    public func activate() {
        _isActive = true
        logger.info("SecurityCollector activated")
    }

    public func deactivate() {
        _isActive = false
        logger.info("SecurityCollector deactivated")
    }

    // MARK: - Collection

    /// Collect a snapshot of the system's security posture
    public func collect() async -> SecuritySnapshot {
        guard _isActive else {
            return SecuritySnapshot()
        }

        let sip = checkSIP()
        let fileVault = checkFileVault()
        let firewall = checkFirewall()
        let gatekeeper = checkGatekeeper()
        let remoteLogin = checkRemoteLogin()
        let screenSharing = checkScreenSharing()

        return SecuritySnapshot(
            sipStatus: sip,
            fileVaultStatus: fileVault,
            firewallStatus: firewall,
            gatekeeperStatus: gatekeeper,
            remoteLoginEnabled: remoteLogin,
            screenSharingEnabled: screenSharing,
            timestamp: Date()
        )
    }

    // MARK: - SIP Check

    /// Check System Integrity Protection status via csrutil
    private func checkSIP() -> SecurityItemStatus {
        guard let output = runCommand("/usr/bin/csrutil", arguments: ["status"]) else {
            return .unknown
        }
        if output.contains("enabled") {
            return .enabled
        } else if output.contains("disabled") {
            return .disabled
        }
        return .unknown
    }

    // MARK: - FileVault Check

    /// Check FileVault status via fdesetup
    private func checkFileVault() -> SecurityItemStatus {
        guard let output = runCommand("/usr/bin/fdesetup", arguments: ["status"]) else {
            // Fallback: check for SystemKey file as a FileVault-enabled indicator
            if FileManager.default.fileExists(atPath: "/private/var/db/SystemKey") {
                return .enabled
            }
            return .unknown
        }
        if output.contains("FileVault is On") {
            return .enabled
        } else if output.contains("FileVault is Off") {
            return .disabled
        }
        return .unknown
    }

    // MARK: - Firewall Check

    /// Check Application Firewall status via plist
    private func checkFirewall() -> SecurityItemStatus {
        let plistPath = "/Library/Preferences/com.apple.alf.plist"

        // Try reading the firewall plist
        guard FileManager.default.fileExists(atPath: plistPath),
              let plistData = FileManager.default.contents(atPath: plistPath),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
            // Fallback: try socketfilterfw
            guard let output = runCommand(
                "/usr/libexec/ApplicationFirewall/socketfilterfw",
                arguments: ["--getglobalstate"]
            ) else {
                return .unknown
            }
            return output.contains("enabled") ? .enabled : .disabled
        }

        // globalstate: 0 = off, 1 = on, 2 = block all
        if let globalState = plist["globalstate"] as? Int {
            return globalState > 0 ? .enabled : .disabled
        }

        return .unknown
    }

    // MARK: - Gatekeeper Check

    /// Check Gatekeeper status via spctl
    private func checkGatekeeper() -> SecurityItemStatus {
        guard let output = runCommand("/usr/sbin/spctl", arguments: ["--status"]) else {
            return .unknown
        }
        if output.contains("assessments enabled") {
            return .enabled
        } else if output.contains("assessments disabled") {
            return .disabled
        }
        return .unknown
    }

    // MARK: - Remote Login Check

    /// Check if Remote Login (SSH) is enabled
    private func checkRemoteLogin() -> SecurityItemStatus {
        // Check if sshd is running by looking for the LaunchDaemon
        let disabledPlistPath = "/private/var/db/com.apple.xpc.launchd/disabled.plist"

        guard FileManager.default.isReadableFile(atPath: disabledPlistPath),
              let plistData = FileManager.default.contents(atPath: disabledPlistPath),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
            // Cannot read disabled plist, check if sshd process exists
            let allProcs = SysctlWrapper.allProcesses()
            let sshdRunning = allProcs.contains { proc in
                let pid = proc.kp_proc.p_pid
                guard pid > 0 else { return false }
                let name = LibProcWrapper.processName(for: pid) ?? ""
                return name == "sshd"
            }
            return sshdRunning ? .enabled : .unknown
        }

        // If com.openssh.sshd is in the disabled plist and set to true, SSH is disabled
        if let isDisabled = plist["com.openssh.sshd"] as? Bool {
            return isDisabled ? .disabled : .enabled
        }

        return .unknown
    }

    // MARK: - Screen Sharing Check

    /// Check if Screen Sharing is enabled
    private func checkScreenSharing() -> SecurityItemStatus {
        // Screen Sharing is controlled by the screensharingd LaunchDaemon
        let plistPath = "/System/Library/LaunchDaemons/com.apple.screensharing.plist"
        if !FileManager.default.fileExists(atPath: plistPath) {
            return .unknown
        }

        // Check if screensharingd is running
        let allProcs = SysctlWrapper.allProcesses()
        let running = allProcs.contains { proc in
            let pid = proc.kp_proc.p_pid
            guard pid > 0 else { return false }
            let name = LibProcWrapper.processName(for: pid) ?? ""
            return name == "screensharingd"
        }

        return running ? .enabled : .disabled
    }

    // MARK: - Shell Command Helper

    /// Runs a command and returns stdout, or nil on failure
    private func runCommand(_ executablePath: String, arguments: [String]) -> String? {
        guard FileManager.default.fileExists(atPath: executablePath) else {
            return nil
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: executablePath)
        task.arguments = arguments

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe() // Discard stderr

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            logger.debug("Command failed: \(executablePath) — \(error.localizedDescription)")
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Mock Security Collector

/// Mock security collector for testing
public final class MockSecurityCollector: SecurityCollecting, @unchecked Sendable {
    public let id = "security-mock"
    public let displayName = "Security (Mock)"
    public let requiresHelper = false
    public var isAvailable: Bool = true

    public var mockSnapshot: SecuritySnapshot = SecuritySnapshot()
    public private(set) var activateCount = 0
    public private(set) var deactivateCount = 0

    public init() {}

    public func activate() async { activateCount += 1 }
    public func deactivate() async { deactivateCount += 1 }

    public func collect() async -> SecuritySnapshot {
        mockSnapshot
    }
}
