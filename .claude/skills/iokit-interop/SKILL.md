---
name: iokit-interop
description: C interop patterns for macOS system monitoring — libproc, sysctl, IOKit, IOReport. Use when implementing data collectors, parsing KERN_PROCARGS2, reading GPU/thermal metrics, or wrapping any C API for Swift consumption.
---

# macOS C Interop for System Monitoring

## libproc Wrappers

### Process Path Resolution
```swift
import Darwin

func processPath(for pid: pid_t) -> String? {
    let pathBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: Int(PROC_PIDPATHINFO_MAXSIZE))
    defer { pathBuffer.deallocate() }
    
    let length = proc_pidpath(pid, pathBuffer, UInt32(PROC_PIDPATHINFO_MAXSIZE))
    guard length > 0 else { return nil }
    return String(cString: pathBuffer)
}
```

### Process Resource Usage
```swift
func processResourceUsage(for pid: pid_t) -> rusage_info_v4? {
    var info = rusage_info_v4()
    let result = withUnsafeMutablePointer(to: &info) { ptr in
        proc_pid_rusage(pid, RUSAGE_INFO_V4, UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: rusage_info_t?.self))
    }
    guard result == 0 else { return nil }
    return info
}
```

### Working Directory via proc_pidinfo
```swift
func workingDirectory(for pid: pid_t) -> String? {
    var vnodeInfo = proc_vnodepathinfo()
    let size = MemoryLayout<proc_vnodepathinfo>.size
    let result = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vnodeInfo, Int32(size))
    guard result == size else { return nil }
    
    return withUnsafePointer(to: &vnodeInfo.pvi_cdir.vip_path) { ptr in
        ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { cStr in
            String(cString: cStr)
        }
    }
}
```

## sysctl Wrappers

### Full Process List
```swift
func allProcesses() -> [kinfo_proc] {
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL]
    var size: Int = 0
    
    // First call: get buffer size
    guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0 else { return [] }
    
    let count = size / MemoryLayout<kinfo_proc>.stride
    var procs = [kinfo_proc](repeating: kinfo_proc(), count: count)
    
    // Second call: fill buffer
    guard sysctl(&mib, UInt32(mib.count), &procs, &size, nil, 0) == 0 else { return [] }
    
    let actualCount = size / MemoryLayout<kinfo_proc>.stride
    return Array(procs.prefix(actualCount))
}
```

### KERN_PROCARGS2 — The Critical API
This is how ProcessScope discovers what a process is actually doing.

**Memory layout returned by KERN_PROCARGS2:**
```
┌──────────┬──────────────┬──────┬──────────┬──────┬──────────────┬──────┐
│ argc (4B)│ exec_path\0  │ nulls│ argv[0]\0│ ...  │ argv[argc-1]\0│env\0 │
└──────────┴──────────────┴──────┴──────────┴──────┴──────────────┴──────┘
```

```swift
func processArguments(for pid: pid_t) -> (execPath: String, arguments: [String])? {
    var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
    var size: Int = 0
    
    // Get buffer size
    guard sysctl(&mib, 3, nil, &size, nil, 0) == 0 else { return nil }
    
    let buffer = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 1)
    defer { buffer.deallocate() }
    
    guard sysctl(&mib, 3, buffer, &size, nil, 0) == 0 else { return nil }
    
    // First 4 bytes: argc
    let argc = buffer.load(as: Int32.self)
    var offset = MemoryLayout<Int32>.size
    
    // Extract executable path (null-terminated)
    let execPath = String(cString: buffer.advanced(by: offset).assumingMemoryBound(to: CChar.self))
    offset += execPath.utf8.count + 1
    
    // Skip padding nulls
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
    
    return (execPath, args)
}
```

**IMPORTANT:** Reading other users' processes requires root privileges — this is why the Helper daemon exists.

## IOKit — GPU Metrics

### GPU Utilization via IOAccelerator
```swift
import IOKit

func gpuUtilization() -> Double? {
    var iterator: io_iterator_t = 0
    let matching = IOServiceMatching("IOAccelerator")
    
    guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
        return nil
    }
    defer { IOObjectRelease(iterator) }
    
    var service = IOIteratorNext(iterator)
    defer { if service != 0 { IOObjectRelease(service) } }
    
    guard service != 0 else { return nil }
    
    var properties: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
          let dict = properties?.takeRetainedValue() as? [String: Any],
          let perfStats = dict["PerformanceStatistics"] as? [String: Any] else {
        return nil
    }
    
    // Keys vary by GPU generation — check for common ones
    if let utilization = perfStats["GPU Activity(%)"] as? Double {
        return utilization
    }
    if let deviceUtil = perfStats["Device Utilization %"] as? Int {
        return Double(deviceUtil)
    }
    
    return nil
}
```

## IOReport — Apple Silicon Power/Frequency

IOReport is semi-private but required for power metrics. Wrap in a single module:

```swift
// IOKitWrapper.swift — ALL IOReport access goes through here
// Reference implementations: asitop, mactop, macmon on GitHub

import IOKit

/// Opaque wrapper for IOReport channel subscriptions.
/// If Apple provides a public API in macOS 17+, replace this file only.
final class IOReportWrapper: @unchecked Sendable {
    
    func gpuPowerWatts() throws -> Double {
        // IOReportCopyChannelGroup + IOReportCreateSubscription
        // Filter for "GPU Energy" subgroup
        // Calculate watts from energy delta / time delta
        throw CollectorError.unavailable("IOReport not implemented yet")
    }
    
    func cpuFrequencyMHz(cluster: CPUCluster) throws -> Double {
        // IOReportCopyChannelGroup for "CPU Stats"
        // Residency-weighted frequency calculation
        throw CollectorError.unavailable("IOReport not implemented yet")
    }
    
    func anePowerWatts() throws -> Double {
        // "ANE Energy" subgroup
        throw CollectorError.unavailable("IOReport not implemented yet")
    }
}
```

**Known limitation:** IOReport APIs are not guaranteed stable across macOS versions. This wrapper is the ONLY file that touches IOReport. All consumers use the protocol interface.

## CPU Metrics via Mach

### Per-Core Utilization
```swift
import Darwin.Mach

func perCoreCPUUsage() -> [CPUCoreUsage]? {
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
    guard result == KERN_SUCCESS, let info = cpuInfo else { return nil }
    defer {
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(numCPUInfo) * vm_size_t(MemoryLayout<integer_t>.size))
    }
    
    var cores: [CPUCoreUsage] = []
    for i in 0..<Int(numCPU) {
        let offset = Int(CPU_STATE_MAX) * i
        let user   = Double(info[offset + Int(CPU_STATE_USER)])
        let system = Double(info[offset + Int(CPU_STATE_SYSTEM)])
        let idle   = Double(info[offset + Int(CPU_STATE_IDLE)])
        let nice   = Double(info[offset + Int(CPU_STATE_NICE)])
        let total  = user + system + idle + nice
        cores.append(CPUCoreUsage(
            user: user / total,
            system: system / total,
            idle: idle / total
        ))
    }
    return cores
}
```

## Memory Pressure
```swift
func memoryStatistics() -> vm_statistics64? {
    var stats = vm_statistics64()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
    
    let result = withUnsafeMutablePointer(to: &stats) { ptr in
        ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
            host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
        }
    }
    guard result == KERN_SUCCESS else { return nil }
    return stats
}
```

## Network Sockets per Process
```swift
func socketInfo(for pid: pid_t) -> [SocketInfo] {
    var bufferSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
    guard bufferSize > 0 else { return [] }
    
    let fdCount = Int(bufferSize) / MemoryLayout<proc_fdinfo>.size
    var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: fdCount)
    bufferSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, bufferSize)
    
    return fds
        .filter { $0.proc_fdtype == PROX_FDTYPE_SOCKET }
        .compactMap { fd -> SocketInfo? in
            var socketInfo = socket_fdinfo()
            let result = proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &socketInfo, Int32(MemoryLayout<socket_fdinfo>.size))
            guard result > 0 else { return nil }
            return SocketInfo(from: socketInfo)
        }
}
```

## Docker Socket Integration
```swift
// Use URLSession with unix domain socket
func dockerContainers() async throws -> [DockerContainer] {
    let socketPath = findDockerSocket()  // /var/run/docker.sock, ~/.colima/default/docker.sock, etc.
    let config = URLSessionConfiguration.default
    config.protocolClasses = [UnixSocketURLProtocol.self]
    
    let session = URLSession(configuration: config)
    let url = URL(string: "http://localhost/v1.43/containers/json")!
    let (data, _) = try await session.data(from: url)
    return try JSONDecoder().decode([DockerContainer].self, from: data)
}
```

## Error Handling
Every C API call must check return values. Common patterns:
- `sysctl` returns 0 on success, -1 on error (check `errno`)
- `proc_pidinfo` returns bytes filled, 0 on error
- `IOServiceGetMatchingServices` returns `KERN_SUCCESS`
- `host_processor_info` returns `KERN_SUCCESS`

Never crash on API failure — return nil and let the UI show "unavailable".
