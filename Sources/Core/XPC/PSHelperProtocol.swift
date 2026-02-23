import Foundation

// MARK: - Snapshot Types

/// Snapshot of all process data collected by the helper
public struct ProcessSnapshot: Codable, Sendable {
    public let processes: [ProcessRecord]
    public let timestamp: Date
}

/// Individual process record with resource usage
public struct ProcessRecord: Codable, Sendable, Identifiable {
    public var id: pid_t { pid }
    public let pid: pid_t
    public let ppid: pid_t
    public let name: String
    public let executablePath: String?
    public let arguments: [String]
    public let workingDirectory: String?
    public let user: String
    public let uid: uid_t
    public let cpuTimeUser: UInt64
    public let cpuTimeSystem: UInt64
    public let rssBytes: UInt64
    public let virtualBytes: UInt64
    public let startTime: Date?
    public let status: ProcessStatus

    public init(pid: pid_t, ppid: pid_t, name: String, executablePath: String? = nil,
                arguments: [String] = [], workingDirectory: String? = nil,
                user: String, uid: uid_t, cpuTimeUser: UInt64 = 0, cpuTimeSystem: UInt64 = 0,
                rssBytes: UInt64 = 0, virtualBytes: UInt64 = 0, startTime: Date? = nil,
                status: ProcessStatus = .running) {
        self.pid = pid; self.ppid = ppid; self.name = name
        self.executablePath = executablePath; self.arguments = arguments
        self.workingDirectory = workingDirectory; self.user = user; self.uid = uid
        self.cpuTimeUser = cpuTimeUser; self.cpuTimeSystem = cpuTimeSystem
        self.rssBytes = rssBytes; self.virtualBytes = virtualBytes
        self.startTime = startTime; self.status = status
    }
}

public enum ProcessStatus: String, Codable, Sendable {
    case running, sleeping, stopped, zombie, unknown
}

/// System-wide metrics snapshot
public struct SystemMetricsSnapshot: Codable, Sendable {
    public let cpuPerCore: [Double]
    public let cpuTotal: Double
    public let memoryUsed: UInt64
    public let memoryTotal: UInt64
    public let memoryPressure: MemoryPressureLevel
    public let gpuUtilization: Double?
    public let gpuPowerWatts: Double?
    public let anePowerWatts: Double?
    public let thermalState: Int
    public let fanSpeedRPM: Int?
    public let timestamp: Date
}

public enum MemoryPressureLevel: Int, Codable, Sendable {
    case nominal = 0, warning = 1, critical = 2
}

/// Network connection snapshot
public struct NetworkSnapshot: Codable, Sendable {
    public let connections: [NetworkConnectionRecord]
    public let timestamp: Date
}

public struct NetworkConnectionRecord: Codable, Sendable, Identifiable {
    public var id: String { "\(pid)-\(localPort)-\(remotePort)-\(protocolType)" }
    public let pid: pid_t
    public let localAddress: String
    public let localPort: UInt16
    public let remoteAddress: String
    public let remotePort: UInt16
    public let protocolType: String
    public let state: String
    public let bytesIn: UInt64
    public let bytesOut: UInt64
}

// MARK: - XPC Protocol

/// XPC protocol — defines what the app can ask the helper
@objc public protocol PSHelperProtocol {
    func getProcessSnapshot(reply: @escaping (Data?, Error?) -> Void)
    func getSystemMetrics(reply: @escaping (Data?, Error?) -> Void)
    func getNetworkConnections(reply: @escaping (Data?, Error?) -> Void)
    func getHelperVersion(reply: @escaping (String) -> Void)

    // Action stubs
    func killProcess(pid: pid_t, signal: Int32, reply: @escaping (Bool, Error?) -> Void)
    func purgeMemory(reply: @escaping (Bool, Error?) -> Void)
    func flushDNS(reply: @escaping (Bool, Error?) -> Void)
    func forceEjectVolume(path: String, reply: @escaping (Bool, Error?) -> Void)
    func reconnectNetworkVolume(path: String, reply: @escaping (Bool, Error?) -> Void)
    func setProcessPriority(pid: pid_t, priority: Int32, reply: @escaping (Bool, Error?) -> Void)
}
