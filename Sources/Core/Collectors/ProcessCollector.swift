import Foundation
import os

/// Collects process information from the system
public actor ProcessCollector: SystemCollector {
    public nonisolated let id = "processes"
    public nonisolated let displayName = "Processes"
    public nonisolated let requiresHelper = false

    private let logger = Logger(subsystem: "com.processscope", category: "ProcessCollector")
    private var _isActive = false

    public nonisolated var isAvailable: Bool { true }

    public init() {}

    public func activate() {
        _isActive = true
        logger.info("ProcessCollector activated")
    }

    public func deactivate() {
        _isActive = false
        logger.info("ProcessCollector deactivated")
    }

    // MARK: - Collection

    /// Collects all processes visible to the current user
    public func collect() -> [ProcessRecord] {
        guard _isActive else { return [] }

        let procs = SysctlWrapper.allProcesses()
        return procs.compactMap { kinfo -> ProcessRecord? in
            let pid = kinfo.kp_proc.p_pid
            guard pid > 0 else { return nil }

            let name = withUnsafePointer(to: kinfo.kp_proc.p_comm) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN)) {
                    String(cString: $0)
                }
            }

            let execPath = LibProcWrapper.processPath(for: pid)
            let argsResult = SysctlWrapper.processArguments(for: pid)
            let workDir = LibProcWrapper.workingDirectory(for: pid)
            let taskInfo = LibProcWrapper.taskInfo(for: pid)

            let status: ProcessStatus
            let pStat = Int32(kinfo.kp_proc.p_stat)
            switch pStat {
            case SRUN: status = .running
            case SSLEEP: status = .sleeping
            case SSTOP: status = .stopped
            case SZOMB: status = .zombie
            default: status = .unknown
            }

            let uid = kinfo.kp_eproc.e_ucred.cr_uid
            let user = userName(for: uid) ?? "uid:\(uid)"

            let startTime: Date?
            let tv = kinfo.kp_proc.p_starttime
            if tv.tv_sec > 0 {
                startTime = Date(timeIntervalSince1970: Double(tv.tv_sec) + Double(tv.tv_usec) / 1_000_000)
            } else {
                startTime = nil
            }

            return ProcessRecord(
                pid: pid,
                ppid: kinfo.kp_eproc.e_ppid,
                name: name,
                executablePath: execPath ?? argsResult?.execPath,
                arguments: argsResult?.arguments ?? [],
                workingDirectory: workDir,
                user: user,
                uid: uid,
                cpuTimeUser: taskInfo.map { UInt64($0.pti_total_user) } ?? 0,
                cpuTimeSystem: taskInfo.map { UInt64($0.pti_total_system) } ?? 0,
                rssBytes: taskInfo.map { UInt64($0.pti_resident_size) } ?? 0,
                virtualBytes: taskInfo.map { UInt64($0.pti_virtual_size) } ?? 0,
                startTime: startTime,
                status: status
            )
        }
    }

    private func userName(for uid: uid_t) -> String? {
        guard let pw = getpwuid(uid) else { return nil }
        return String(cString: pw.pointee.pw_name)
    }
}

/// Mock process collector for testing
public final class MockProcessCollector: SystemCollector, @unchecked Sendable {
    public let id = "processes-mock"
    public let displayName = "Processes (Mock)"
    public let requiresHelper = false
    public var isAvailable: Bool = true

    public var mockProcesses: [ProcessRecord] = []
    public private(set) var activateCount = 0
    public private(set) var deactivateCount = 0

    public init() {}

    public func activate() async { activateCount += 1 }
    public func deactivate() async { deactivateCount += 1 }

    public func collect() -> [ProcessRecord] { mockProcesses }
}
