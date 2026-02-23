import Darwin
import Darwin.Mach
import os

/// Wrapper for Mach host APIs — CPU per-core usage and memory statistics
public enum MachWrapper {
    private static let logger = Logger(subsystem: "com.processscope", category: "MachWrapper")

    // MARK: - CPU Core Usage

    public struct CPUCoreUsage: Sendable {
        public let user: Double
        public let system: Double
        public let idle: Double
        public let nice: Double

        public var totalUsage: Double { user + system + nice }
    }

    /// Returns per-core CPU usage ticks (must diff with previous snapshot for percentages)
    public static func perCoreCPUTicks() -> [CPUCoreTicks]? {
        var numCPU: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCPUInfo: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPU,
            &cpuInfo,
            &numCPUInfo
        )
        guard result == KERN_SUCCESS, let info = cpuInfo else {
            logger.error("host_processor_info failed: \(result)")
            return nil
        }
        defer {
            vm_deallocate(mach_task_self_,
                         vm_address_t(bitPattern: info),
                         vm_size_t(numCPUInfo) * vm_size_t(MemoryLayout<integer_t>.size))
        }

        var cores: [CPUCoreTicks] = []
        for i in 0..<Int(numCPU) {
            let offset = Int(CPU_STATE_MAX) * i
            cores.append(CPUCoreTicks(
                user: UInt64(info[offset + Int(CPU_STATE_USER)]),
                system: UInt64(info[offset + Int(CPU_STATE_SYSTEM)]),
                idle: UInt64(info[offset + Int(CPU_STATE_IDLE)]),
                nice: UInt64(info[offset + Int(CPU_STATE_NICE)])
            ))
        }
        return cores
    }

    public struct CPUCoreTicks: Sendable {
        public let user: UInt64
        public let system: UInt64
        public let idle: UInt64
        public let nice: UInt64

        public var total: UInt64 { user + system + idle + nice }
    }

    /// Computes per-core usage percentages from two tick snapshots
    public static func computeUsage(previous: [CPUCoreTicks], current: [CPUCoreTicks]) -> [CPUCoreUsage] {
        zip(previous, current).map { prev, cur in
            let dUser = Double(cur.user &- prev.user)
            let dSystem = Double(cur.system &- prev.system)
            let dIdle = Double(cur.idle &- prev.idle)
            let dNice = Double(cur.nice &- prev.nice)
            let dTotal = dUser + dSystem + dIdle + dNice
            guard dTotal > 0 else {
                return CPUCoreUsage(user: 0, system: 0, idle: 1, nice: 0)
            }
            return CPUCoreUsage(
                user: dUser / dTotal,
                system: dSystem / dTotal,
                idle: dIdle / dTotal,
                nice: dNice / dTotal
            )
        }
    }

    // MARK: - Memory Statistics

    public struct MemoryStats: Sendable {
        public let free: UInt64
        public let active: UInt64
        public let inactive: UInt64
        public let wired: UInt64
        public let compressed: UInt64
        public let pageSize: UInt64
        public let total: UInt64

        public var used: UInt64 { active + wired + compressed }
        public var pressure: Double { Double(used) / Double(total) }
    }

    public static func memoryStatistics() -> MemoryStats? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            logger.error("host_statistics64 failed: \(result)")
            return nil
        }

        var pageSizeValue: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSizeValue)
        let pageSize = UInt64(pageSizeValue)
        let total = SysctlWrapper.totalMemory()

        return MemoryStats(
            free: UInt64(stats.free_count) * pageSize,
            active: UInt64(stats.active_count) * pageSize,
            inactive: UInt64(stats.inactive_count) * pageSize,
            wired: UInt64(stats.wire_count) * pageSize,
            compressed: UInt64(stats.compressor_page_count) * pageSize,
            pageSize: pageSize,
            total: total
        )
    }

    // MARK: - Load Average

    public static func loadAverage() -> (one: Double, five: Double, fifteen: Double) {
        var loadavg = [Double](repeating: 0, count: 3)
        getloadavg(&loadavg, 3)
        return (loadavg[0], loadavg[1], loadavg[2])
    }
}
