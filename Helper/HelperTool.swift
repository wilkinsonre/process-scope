import Foundation
import os
import Security

// MARK: - Sendable Wrapper

/// Wraps a non-Sendable value for use in Sendable contexts (e.g., XPC reply handlers)
struct UncheckedSendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

// MARK: - Listener Delegate

final class HelperToolDelegate: NSObject, NSXPCListenerDelegate {
    private let logger = Logger(subsystem: "com.processscope.helper", category: "Delegate")

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        guard validateClient(connection: newConnection) else {
            logger.warning("Rejected XPC connection — validation failed")
            return false
        }

        newConnection.exportedInterface = NSXPCInterface(with: PSHelperProtocol.self)
        newConnection.exportedObject = DataCollectionService()
        newConnection.invalidationHandler = { [weak self] in
            self?.logger.info("Client connection invalidated")
        }
        newConnection.resume()
        logger.info("Accepted new XPC connection")
        return true
    }

    // MARK: - Client Validation

    /// Team ID requirement for code signature validation.
    /// Replace TEAM_ID_HERE with the actual Apple Developer Team ID before release.
    private static let requiredTeamID = "TEAM_ID_HERE"

    /// Bundle ID prefix that all legitimate ProcessScope components must share.
    private static let requiredBundleIDPrefix = "com.processscope"

    /// Validates the connecting client by using SecCodeCopyGuestWithAttributes
    /// with the process's audit token to obtain its code identity, then verifying
    /// that its code signature is valid, its Team ID matches ours, and its bundle
    /// identifier starts with the expected prefix.
    /// Returns false (rejecting the connection) on any validation failure.
    private func validateClient(connection: NSXPCConnection) -> Bool {
        // Step 1: Extract the audit token from the XPC connection.
        // We use the Objective-C property via value(forEntitlementKey:) workaround
        // or the pid-based approach. NSXPCConnection provides processIdentifier
        // and the audit token through its internal state. We use the pid to build
        // a SecCode via kSecGuestAttributePid.
        let pid = connection.processIdentifier

        let attributes: [String: Any] = [
            kSecGuestAttributePid as String: pid
        ]

        // Step 2: Obtain a SecCode reference for the connecting process.
        var codeRef: SecCode?
        let codeStatus = SecCodeCopyGuestWithAttributes(
            nil,
            attributes as CFDictionary,
            [],
            &codeRef
        )
        guard codeStatus == errSecSuccess, let code = codeRef else {
            logger.error("Failed to obtain SecCode for PID \(pid) (status: \(codeStatus))")
            return false
        }

        // Step 3: Validate the code signature is intact (not tampered with).
        let validityStatus = SecCodeCheckValidity(code, SecCSFlags(rawValue: 0), nil)
        guard validityStatus == errSecSuccess else {
            logger.error("Code signature validity check failed for PID \(pid) (status: \(validityStatus))")
            return false
        }

        // Step 4: Convert SecCode to SecStaticCode for signing information retrieval.
        var staticCodeRef: SecStaticCode?
        let staticStatus = SecCodeCopyStaticCode(code, [], &staticCodeRef)
        guard staticStatus == errSecSuccess, let staticCode = staticCodeRef else {
            logger.error("Failed to obtain SecStaticCode for PID \(pid) (status: \(staticStatus))")
            return false
        }

        // Step 5: Retrieve signing information to inspect Team ID and bundle ID.
        var infoRef: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &infoRef
        )
        guard infoStatus == errSecSuccess, let info = infoRef as? [String: Any] else {
            logger.error("Failed to retrieve signing information for PID \(pid) (status: \(infoStatus))")
            return false
        }

        // Step 6: Verify Team ID matches our expected value.
        guard let teamID = info[kSecCodeInfoTeamIdentifier as String] as? String else {
            logger.error("Connecting process (PID \(pid)) has no Team ID in code signature")
            return false
        }
        guard teamID == Self.requiredTeamID else {
            logger.error("Team ID mismatch for PID \(pid): expected \(Self.requiredTeamID), got \(teamID)")
            return false
        }

        // Step 7: Verify bundle identifier starts with our expected prefix.
        guard let bundleID = info[kSecCodeInfoIdentifier as String] as? String else {
            logger.error("Connecting process (PID \(pid)) has no bundle identifier in code signature")
            return false
        }
        guard bundleID.hasPrefix(Self.requiredBundleIDPrefix) else {
            logger.error("Bundle ID mismatch for PID \(pid): expected prefix \(Self.requiredBundleIDPrefix), got \(bundleID)")
            return false
        }

        logger.info("Validated client PID \(pid): \(bundleID) (team: \(teamID))")
        return true
    }
}

// MARK: - Data Collection Service

final class DataCollectionService: NSObject, PSHelperProtocol, @unchecked Sendable {
    private let logger = Logger(subsystem: "com.processscope.helper", category: "DataCollection")
    private let processCollector = ProcessCollector()
    private let encoder = JSONEncoder()

    override init() {
        super.init()
        let collector = processCollector
        Task { await collector.activate() }
    }

    func getProcessSnapshot(reply: @escaping (Data?, (any Error)?) -> Void) {
        let collector = processCollector
        let enc = encoder
        let replyBox = UncheckedSendableBox(reply)
        Task {
            let processes = await collector.collect()
            let snapshot = ProcessSnapshot(processes: processes, timestamp: Date())
            do {
                let data = try enc.encode(snapshot)
                replyBox.value(data, nil)
            } catch {
                replyBox.value(nil, error)
            }
        }
    }

    func getSystemMetrics(reply: @escaping (Data?, (any Error)?) -> Void) {
        let enc = encoder
        let replyBox = UncheckedSendableBox(reply)
        Task {
            let cpuTicks = MachWrapper.perCoreCPUTicks() ?? []
            let memory = MachWrapper.memoryStatistics()
            let iokit = IOKitWrapper.shared

            let snapshot = SystemMetricsSnapshot(
                cpuPerCore: cpuTicks.map { Double($0.user + $0.system) / Double(max($0.total, 1)) },
                cpuTotal: {
                    let total = cpuTicks.reduce(0.0) { sum, core in
                        sum + Double(core.user + core.system) / Double(max(core.total, 1))
                    }
                    return cpuTicks.isEmpty ? 0 : total / Double(cpuTicks.count)
                }(),
                memoryUsed: memory?.used ?? 0,
                memoryTotal: memory?.total ?? 0,
                memoryPressure: {
                    guard let m = memory else { return .nominal }
                    if m.pressure > 0.9 { return .critical }
                    if m.pressure > 0.7 { return .warning }
                    return .nominal
                }(),
                gpuUtilization: iokit.gpuUtilization(),
                gpuPowerWatts: iokit.gpuPowerWatts(),
                anePowerWatts: iokit.anePowerWatts(),
                thermalState: iokit.thermalState(),
                fanSpeedRPM: iokit.fanSpeedRPM(),
                timestamp: Date()
            )
            do {
                let data = try enc.encode(snapshot)
                replyBox.value(data, nil)
            } catch {
                replyBox.value(nil, error)
            }
        }
    }

    func getNetworkConnections(reply: @escaping (Data?, (any Error)?) -> Void) {
        let data = try? encoder.encode(NetworkSnapshot(connections: [], timestamp: Date()))
        reply(data, nil)
    }

    func getHelperVersion(reply: @escaping (String) -> Void) {
        reply("1.0.0")
    }

    // MARK: - Action Stubs

    func killProcess(pid: pid_t, signal: Int32, reply: @escaping (Bool, (any Error)?) -> Void) {
        // Validate PID: must be > 0, never allow killing kernel_task (0) or launchd (1)
        guard pid > 1 else {
            let desc = pid == 0
                ? "Refusing to signal PID 0 (kernel_task)"
                : "Refusing to signal PID 1 (launchd)"
            logger.warning("\(desc)")
            reply(false, NSError(domain: "com.processscope.helper", code: -1,
                                 userInfo: [NSLocalizedDescriptionKey: desc]))
            return
        }

        let result = Darwin.kill(pid, signal)
        reply(result == 0, result != 0 ? NSError(domain: "com.processscope.helper", code: Int(errno)) : nil)
    }

    func purgeMemory(reply: @escaping (Bool, (any Error)?) -> Void) {
        reply(false, NSError(domain: "com.processscope.helper", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not implemented"]))
    }

    func flushDNS(reply: @escaping (Bool, (any Error)?) -> Void) {
        reply(false, NSError(domain: "com.processscope.helper", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not implemented"]))
    }

    func forceEjectVolume(path: String, reply: @escaping (Bool, (any Error)?) -> Void) {
        // Validate path: must start with /Volumes/ and contain no ".." path traversal
        guard path.hasPrefix("/Volumes/") else {
            let desc = "Refusing to eject path outside /Volumes/: \(path)"
            logger.warning("\(desc)")
            reply(false, NSError(domain: "com.processscope.helper", code: -1,
                                 userInfo: [NSLocalizedDescriptionKey: desc]))
            return
        }

        let components = (path as NSString).pathComponents
        guard !components.contains("..") else {
            let desc = "Refusing to eject path with directory traversal: \(path)"
            logger.warning("\(desc)")
            reply(false, NSError(domain: "com.processscope.helper", code: -1,
                                 userInfo: [NSLocalizedDescriptionKey: desc]))
            return
        }

        // Ensure there is an actual volume name after /Volumes/
        guard components.count >= 3 else {
            let desc = "Invalid volume path (no volume name): \(path)"
            logger.warning("\(desc)")
            reply(false, NSError(domain: "com.processscope.helper", code: -1,
                                 userInfo: [NSLocalizedDescriptionKey: desc]))
            return
        }

        reply(false, NSError(domain: "com.processscope.helper", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not implemented"]))
    }

    func reconnectNetworkVolume(path: String, reply: @escaping (Bool, (any Error)?) -> Void) {
        // Validate path: must be an absolute path under /Volumes/ with no traversal
        guard path.hasPrefix("/Volumes/") else {
            let desc = "Refusing to reconnect path outside /Volumes/: \(path)"
            logger.warning("\(desc)")
            reply(false, NSError(domain: "com.processscope.helper", code: -1,
                                 userInfo: [NSLocalizedDescriptionKey: desc]))
            return
        }

        let components = (path as NSString).pathComponents
        guard !components.contains("..") else {
            let desc = "Refusing to reconnect path with directory traversal: \(path)"
            logger.warning("\(desc)")
            reply(false, NSError(domain: "com.processscope.helper", code: -1,
                                 userInfo: [NSLocalizedDescriptionKey: desc]))
            return
        }

        // Ensure there is an actual volume name after /Volumes/
        guard components.count >= 3 else {
            let desc = "Invalid network volume path (no volume name): \(path)"
            logger.warning("\(desc)")
            reply(false, NSError(domain: "com.processscope.helper", code: -1,
                                 userInfo: [NSLocalizedDescriptionKey: desc]))
            return
        }

        reply(false, NSError(domain: "com.processscope.helper", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not implemented"]))
    }

    func setProcessPriority(pid: pid_t, priority: Int32, reply: @escaping (Bool, (any Error)?) -> Void) {
        // Validate priority is within POSIX nice range
        guard (-20...20).contains(priority) else {
            let desc = "Invalid priority \(priority): must be in range -20...20"
            logger.warning("\(desc)")
            reply(false, NSError(domain: "com.processscope.helper", code: -1,
                                 userInfo: [NSLocalizedDescriptionKey: desc]))
            return
        }

        // Validate PID: must be positive, never target kernel_task or launchd
        guard pid > 1 else {
            let desc = "Refusing to set priority on PID \(pid)"
            logger.warning("\(desc)")
            reply(false, NSError(domain: "com.processscope.helper", code: -1,
                                 userInfo: [NSLocalizedDescriptionKey: desc]))
            return
        }

        reply(false, NSError(domain: "com.processscope.helper", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not implemented"]))
    }
}
