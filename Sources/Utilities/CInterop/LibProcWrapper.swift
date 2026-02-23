import Darwin
import os

/// Wrapper for libproc functions — process paths, working directories, resource usage
public enum LibProcWrapper {
    private static let logger = Logger(subsystem: "com.processscope", category: "LibProcWrapper")

    // MARK: - Process Path

    /// Maximum size for process path buffer (4 * MAXPATHLEN)
    private static let procPidPathMaxSize = 4 * Int(MAXPATHLEN)

    /// Resolves the full executable path for a process
    public static func processPath(for pid: pid_t) -> String? {
        let pathBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: procPidPathMaxSize)
        defer { pathBuffer.deallocate() }

        let length = proc_pidpath(pid, pathBuffer, UInt32(procPidPathMaxSize))
        guard length > 0 else { return nil }
        return String(cString: pathBuffer)
    }

    // MARK: - Working Directory

    /// Returns the current working directory for a process
    public static func workingDirectory(for pid: pid_t) -> String? {
        var vnodeInfo = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        let result = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vnodeInfo, size)
        guard result == size else { return nil }

        return withUnsafePointer(to: &vnodeInfo.pvi_cdir.vip_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { cStr in
                String(cString: cStr)
            }
        }
    }

    // MARK: - Resource Usage

    /// Returns resource usage info for a process
    public static func processResourceUsage(for pid: pid_t) -> rusage_info_v4? {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rusagePtr in
                proc_pid_rusage(pid, RUSAGE_INFO_V4, rusagePtr)
            }
        }
        guard result == 0 else { return nil }
        return info
    }

    // MARK: - Task Info

    /// Returns task info (CPU times, memory) for a process
    public static func taskInfo(for pid: pid_t) -> proc_taskinfo? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        let result = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size)
        guard result == size else { return nil }
        return info
    }

    // MARK: - Socket Enumeration

    /// Returns file descriptors for a process (for socket enumeration)
    public static func fileDescriptors(for pid: pid_t) -> [proc_fdinfo] {
        var bufferSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard bufferSize > 0 else { return [] }

        let fdCount = Int(bufferSize) / MemoryLayout<proc_fdinfo>.size
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: fdCount)
        bufferSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, bufferSize)
        guard bufferSize > 0 else { return [] }

        let actualCount = Int(bufferSize) / MemoryLayout<proc_fdinfo>.size
        return Array(fds.prefix(actualCount))
    }

    /// Returns socket info for a specific file descriptor
    public static func socketInfo(pid: pid_t, fd: Int32) -> socket_fdinfo? {
        var info = socket_fdinfo()
        let size = Int32(MemoryLayout<socket_fdinfo>.size)
        let result = proc_pidfdinfo(pid, fd, PROC_PIDFDSOCKETINFO, &info, size)
        guard result > 0 else { return nil }
        return info
    }

    // MARK: - Process Name

    /// Returns the short process name
    public static func processName(for pid: pid_t) -> String? {
        let nameBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: Int(MAXCOMLEN) + 1)
        defer { nameBuffer.deallocate() }
        let result = proc_name(pid, nameBuffer, UInt32(MAXCOMLEN) + 1)
        guard result > 0 else { return nil }
        return String(cString: nameBuffer)
    }
}
