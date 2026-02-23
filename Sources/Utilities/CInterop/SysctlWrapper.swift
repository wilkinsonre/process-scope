import Darwin
import Foundation
import os

/// Wrapper for sysctl-based process enumeration and argument parsing
public enum SysctlWrapper {
    private static let logger = Logger(subsystem: "com.processscope", category: "SysctlWrapper")

    // MARK: - Process Enumeration

    /// Returns all processes via KERN_PROC_ALL
    public static func allProcesses() -> [kinfo_proc] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL]
        var size: Int = 0

        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0 else {
            logger.error("sysctl KERN_PROC_ALL size query failed: \(errno)")
            return []
        }

        let count = size / MemoryLayout<kinfo_proc>.stride
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: count)

        guard sysctl(&mib, UInt32(mib.count), &procs, &size, nil, 0) == 0 else {
            logger.error("sysctl KERN_PROC_ALL data query failed: \(errno)")
            return []
        }

        let actualCount = size / MemoryLayout<kinfo_proc>.stride
        return Array(procs.prefix(actualCount))
    }

    // MARK: - Process Arguments (KERN_PROCARGS2)

    /// Parses KERN_PROCARGS2 to extract executable path and arguments
    /// Memory layout: [argc:4B][exec_path\0][nulls][argv[0]\0]...[argv[n]\0][env\0...]
    public static func processArguments(for pid: pid_t) -> (execPath: String, arguments: [String])? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size: Int = 0

        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0 else { return nil }

        let buffer = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 1)
        defer { buffer.deallocate() }

        guard sysctl(&mib, 3, buffer, &size, nil, 0) == 0 else { return nil }
        guard size > MemoryLayout<Int32>.size else { return nil }

        // First 4 bytes: argc
        let argc = buffer.load(as: Int32.self)
        var offset = MemoryLayout<Int32>.size

        // Extract executable path (null-terminated)
        guard offset < size else { return nil }
        let execPath = String(cString: buffer.advanced(by: offset).assumingMemoryBound(to: CChar.self))
        offset += execPath.utf8.count + 1

        // Skip padding nulls between exec path and argv[0]
        while offset < size && buffer.load(fromByteOffset: offset, as: UInt8.self) == 0 {
            offset += 1
        }

        // Extract arguments
        var args: [String] = []
        for _ in 0..<argc {
            guard offset < size else { break }
            let arg = String(cString: buffer.advanced(by: offset).assumingMemoryBound(to: CChar.self))
            args.append(arg)
            offset += arg.utf8.count + 1
        }

        let redactedArgs = args.map { redactSensitiveArgument($0) }
        return (execPath, redactedArgs)
    }

    // MARK: - Argument Redaction

    /// Redacts sensitive values from a single process argument string
    ///
    /// Patterns redacted:
    /// - `--password=<value>` becomes `--password=[REDACTED]`
    /// - `-p <value>` when preceded by mysql/psql (handled at list level)
    /// - `KEY=<value>`, `SECRET=<value>`, `TOKEN=<value>`, `PASSWORD=<value>` (case insensitive)
    /// - `Bearer <token>` becomes `Bearer [REDACTED]`
    static func redactSensitiveArgument(_ argument: String) -> String {
        var result = argument

        // Redact --password=<value>
        if let range = result.range(of: #"--password=[^\s]*"#, options: .regularExpression) {
            result = result.replacingCharacters(in: range, with: "--password=[REDACTED]")
        }

        // Redact KEY=value, SECRET=value, TOKEN=value, PASSWORD=value (case insensitive)
        // Matches patterns like AWS_SECRET_KEY=abc123, DB_PASSWORD=foo, API_TOKEN=bar
        if let range = result.range(
            of: #"(?i)([A-Z_]*(KEY|SECRET|TOKEN|PASSWORD)[A-Z_]*)=\S+"#,
            options: .regularExpression
        ) {
            let matched = String(result[range])
            if let eqIndex = matched.firstIndex(of: "=") {
                let prefix = matched[matched.startIndex...eqIndex]
                result = result.replacingCharacters(in: range, with: prefix + "[REDACTED]")
            }
        }

        // Redact Bearer tokens
        if let range = result.range(of: #"Bearer\s+\S+"#, options: .regularExpression) {
            result = result.replacingCharacters(in: range, with: "Bearer [REDACTED]")
        }

        return result
    }

    /// Redacts sensitive values from a list of process arguments, including
    /// context-dependent patterns like `mysql -p <password>`
    ///
    /// - Parameter arguments: The raw argument list from KERN_PROCARGS2
    /// - Returns: The argument list with sensitive values replaced by `[REDACTED]`
    public static func redactSensitiveArguments(_ arguments: [String]) -> [String] {
        var result: [String] = []
        var i = 0
        while i < arguments.count {
            let arg = arguments[i]

            // Check for mysql/psql -p <password> pattern
            if arg == "-p" && i > 0 && i + 1 < arguments.count {
                let joinedPrevious = arguments[0...i].joined(separator: " ").lowercased()
                if joinedPrevious.contains("mysql") || joinedPrevious.contains("psql") {
                    result.append(arg)
                    result.append("[REDACTED]")
                    i += 2
                    continue
                }
            }

            result.append(redactSensitiveArgument(arg))
            i += 1
        }
        return result
    }

    // MARK: - System Info

    /// Total physical memory in bytes
    public static func totalMemory() -> UInt64 {
        var size: UInt64 = 0
        var mib: [Int32] = [CTL_HW, HW_MEMSIZE]
        var len = MemoryLayout<UInt64>.size
        sysctl(&mib, 2, &size, &len, nil, 0)
        return size
    }

    /// Number of logical CPUs
    public static func logicalCPUCount() -> Int {
        var count: Int32 = 0
        var size = MemoryLayout<Int32>.size
        sysctlbyname("hw.logicalcpu", &count, &size, nil, 0)
        return Int(count)
    }

    /// Number of physical CPUs
    public static func physicalCPUCount() -> Int {
        var count: Int32 = 0
        var size = MemoryLayout<Int32>.size
        sysctlbyname("hw.physicalcpu", &count, &size, nil, 0)
        return Int(count)
    }

    /// Machine model identifier
    public static func machineModel() -> String? {
        var size: Int = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return nil }
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }
}
