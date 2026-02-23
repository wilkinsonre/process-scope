import Foundation
import os

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

    private func validateClient(connection: NSXPCConnection) -> Bool {
        // TODO: Implement full audit token validation
        // Verify connecting process is signed with our Team ID
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
        reply(false, NSError(domain: "com.processscope.helper", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not implemented"]))
    }

    func reconnectNetworkVolume(path: String, reply: @escaping (Bool, (any Error)?) -> Void) {
        reply(false, NSError(domain: "com.processscope.helper", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not implemented"]))
    }

    func setProcessPriority(pid: pid_t, priority: Int32, reply: @escaping (Bool, (any Error)?) -> Void) {
        reply(false, NSError(domain: "com.processscope.helper", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not implemented"]))
    }
}
