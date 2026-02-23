---
name: storage-network
description: Storage and network intelligence collectors for ProcessScope Amendment A. Use when implementing external drive monitoring (DiskArbitration), SMART status, network volumes, SSH session detection, VPN/Tailscale integration, WiFi details (CoreWLAN), internet speed testing, listening port inventory, Bonjour/mDNS, or firewall status.
---

# Storage & Network Intelligence Collectors

## Storage Module — DiskArbitration Framework

### Volume Discovery & Monitoring

```swift
import DiskArbitration

actor StorageCollector: SystemCollector {
    typealias Snapshot = StorageSnapshot
    
    private var session: DASession?
    
    func start() {
        session = DASessionCreate(kCFAllocatorDefault)
        guard let session else { return }
        DASessionSetDispatchQueue(session, DispatchQueue(label: "com.processscope.storage"))
        
        // Register callbacks for mount/unmount/eject events
        DARegisterDiskAppearedCallback(session, nil, { disk, context in
            // Volume mounted — refresh snapshot
        }, nil)
        
        DARegisterDiskDisappearedCallback(session, nil, { disk, context in
            // Volume unmounted/ejected
        }, nil)
    }
    
    func collect() async throws -> StorageSnapshot {
        var volumes: [VolumeInfo] = []
        
        // Use statfs to enumerate mounted volumes
        var buf = [statfs](repeating: statfs(), count: 128)
        let count = getmntinfo_r_np(&buf, MNT_NOWAIT)
        
        for i in 0..<Int(count) {
            let fs = buf[i]
            let mountPoint = withUnsafePointer(to: fs.f_mntonname) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
            }
            let fsType = withUnsafePointer(to: fs.f_fstypename) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) { String(cString: $0) }
            }
            
            // statvfs for capacity
            var stvfs = statvfs()
            guard statvfs(mountPoint, &stvfs) == 0 else { continue }
            
            let total = UInt64(stvfs.f_blocks) * UInt64(stvfs.f_frsize)
            let free = UInt64(stvfs.f_bavail) * UInt64(stvfs.f_frsize)
            
            volumes.append(VolumeInfo(
                mountPoint: mountPoint,
                filesystem: fsType,
                totalBytes: total,
                freeBytes: free,
                // ... other fields populated below
            ))
        }
        
        return StorageSnapshot(volumes: volumes, timestamp: Date())
    }
}
```

### Connection Interface Detection (IOKit Registry Traversal)

```swift
func connectionInterface(for diskBSD: String) -> String? {
    // Walk IOKit registry from IOMedia → parent IOBlockStorageDevice → parent transport
    var matchDict = IOServiceMatching("IOMedia") as NSMutableDictionary
    matchDict["BSD Name"] = diskBSD
    
    var service: io_service_t = 0
    guard IOServiceGetMatchingService(kIOMainPortDefault, matchDict, &service) == KERN_SUCCESS else { return nil }
    defer { IOObjectRelease(service) }
    
    // Walk parents to find transport node
    var parent: io_registry_entry_t = 0
    var current = service
    
    while IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS {
        defer {
            if current != service { IOObjectRelease(current) }
            current = parent
        }
        
        var className = [CChar](repeating: 0, count: 128)
        IOObjectGetClass(parent, &className)
        let name = String(cString: className)
        
        if name.contains("USB") { return "USB" }
        if name.contains("Thunderbolt") { return "Thunderbolt" }
        if name.contains("NVMe") { return "NVMe (Internal)" }
        if name.contains("AHCI") { return "SATA" }
    }
    
    return nil
}
```

### SMART Status

```swift
func smartStatus(for bsdName: String) -> SMARTStatus? {
    // Try IOKit IOATASmartInterface first
    let matching = IOServiceMatching("IOBlockStorageDevice") as NSMutableDictionary
    matching["BSD Name"] = bsdName
    
    var service: io_service_t = 0
    guard IOServiceGetMatchingService(kIOMainPortDefault, matching, &service) == KERN_SUCCESS else { return nil }
    defer { IOObjectRelease(service) }
    
    var properties: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
          let dict = properties?.takeRetainedValue() as? [String: Any] else { return nil }
    
    // Check SMART Capable and SMART Status
    if let status = dict["SMART Status"] as? String {
        return status == "Verified" ? .healthy : .warning
    }
    
    // Fallback: shell out to smartctl (requires smartmontools via helper)
    return nil
}
```

### Eject Operations (DiskArbitration)

```swift
func ejectVolume(mountPoint: String) async throws {
    guard let session = DASessionCreate(kCFAllocatorDefault) else {
        throw StorageError.sessionFailed
    }
    
    guard let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, 
                                                  URL(fileURLWithPath: mountPoint) as CFURL) else {
        throw StorageError.diskNotFound
    }
    
    return try await withCheckedThrowingContinuation { continuation in
        DADiskEject(disk, DADiskEjectOptions(kDADiskEjectOptionDefault)) { disk, dissenter in
            if let dissenter {
                let status = DADissenterGetStatus(dissenter)
                continuation.resume(throwing: StorageError.ejectFailed(status: Int(status)))
            } else {
                continuation.resume()
            }
        }
    }
}

func openFileHandles(on mountPoint: String) -> [(pid: pid_t, name: String)] {
    // Use proc_pidinfo with PROC_PIDLISTFDS to find processes with
    // open file descriptors on the target volume
    var results: [(pid_t, String)] = []
    // Enumerate all processes, check their open FDs against mountPoint
    return results
}
```

### Time Machine Status

```swift
func timeMachineStatus() -> TimeMachineStatus? {
    // Parse tmutil status output
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
    task.arguments = ["status"]
    let pipe = Pipe()
    task.standardOutput = pipe
    
    try? task.run()
    task.waitUntilExit()
    
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let output = String(data: data, encoding: .utf8) else { return nil }
    
    // Parse plist-style output
    if output.contains("Running = 1") {
        // Extract percent from "Percent" key
        return .backingUp(percent: extractPercent(from: output))
    } else {
        return .idle(lastBackup: extractLastBackup())
    }
}
```

### Network Volume Details

```swift
func networkVolumeDetails(for mountPoint: String) -> NetworkVolumeInfo? {
    // For SMB volumes: smbutil statshares -a
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/sbin/smbutil")
    task.arguments = ["statshares", "-a"]
    // Parse: server, share, protocol version, signing, encryption
    
    // For NFS volumes: nfsstat -m
    // Parse: server, export, version, latency
    
    return nil
}
```

---

## Network Intelligence Module

### SSH Session Detection

```swift
actor SSHSessionCollector {
    func collect() async -> [SSHSession] {
        var sessions: [SSHSession] = []
        
        // Find all ssh processes (not sshd)
        let allProcs = SysctlWrapper.allProcesses()
        let sshProcs = allProcs.filter { proc in
            let name = processName(for: proc.kp_proc.p_pid)
            return name == "ssh" || name == "mosh-client"
        }
        
        for proc in sshProcs {
            let pid = proc.kp_proc.p_pid
            
            // Parse arguments for host, user, port, tunnels
            guard let args = SysctlWrapper.processArguments(for: pid) else { continue }
            let parsed = parseSSHArgs(args.arguments)
            
            // Get socket info for data transfer stats
            let sockets = LibProc.socketInfo(for: pid)
            let tcpSocket = sockets.first { $0.protocol == .tcp && $0.state == .established }
            
            sessions.append(SSHSession(
                pid: pid,
                user: parsed.user,
                host: parsed.host,
                port: parsed.port,
                tunnels: parsed.tunnels,  // -L, -R, -D flags
                keyType: parsed.keyFile,  // -i flag
                startTime: Date(timeIntervalSince1970: TimeInterval(proc.kp_proc.p_starttime.tv_sec)),
                bytesIn: tcpSocket?.bytesIn ?? 0,
                bytesOut: tcpSocket?.bytesOut ?? 0,
                state: tcpSocket?.tcpState ?? .unknown
            ))
        }
        
        return sessions
    }
    
    private func parseSSHArgs(_ args: [String]) -> SSHParsedArgs {
        var user: String?
        var host: String?
        var port: UInt16 = 22
        var tunnels: [SSHTunnel] = []
        var keyFile: String?
        
        var i = 0
        while i < args.count {
            switch args[i] {
            case "-p": i += 1; port = UInt16(args[i]) ?? 22
            case "-i": i += 1; keyFile = args[i]
            case "-L": i += 1; tunnels.append(.local(args[i]))
            case "-R": i += 1; tunnels.append(.remote(args[i]))
            case "-D": i += 1; tunnels.append(.dynamic(args[i]))
            default:
                // Last non-flag argument is [user@]host
                if !args[i].hasPrefix("-") {
                    let parts = args[i].split(separator: "@")
                    if parts.count == 2 {
                        user = String(parts[0])
                        host = String(parts[1])
                    } else {
                        host = args[i]
                    }
                }
            }
            i += 1
        }
        
        return SSHParsedArgs(user: user, host: host, port: port, tunnels: tunnels, keyFile: keyFile)
    }
}
```

### Tailscale Integration

```swift
actor TailscaleCollector {
    private let baseURL = URL(string: "http://100.100.100.100/localapi/v0/")!
    
    var isAvailable: Bool {
        // Check for tailscaled process AND 100.100.100.100 route
        get async {
            let tailscaled = SysctlWrapper.allProcesses().contains { processName(for: $0.kp_proc.p_pid) == "tailscaled" }
            guard tailscaled else { return false }
            // Verify route exists
            return await canReachTailscaleAPI()
        }
    }
    
    func status() async throws -> TailscaleStatus {
        let url = baseURL.appendingPathComponent("status")
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw CollectorError.unavailable("Tailscale API returned non-200")
        }
        return try JSONDecoder().decode(TailscaleStatus.self, from: data)
    }
}

struct TailscaleStatus: Codable {
    let selfStatus: TailscaleSelf  // "Self" key in JSON
    let peer: [String: TailscalePeer]
    let currentTailnet: TailnetInfo?
    
    enum CodingKeys: String, CodingKey {
        case selfStatus = "Self"
        case peer = "Peer"
        case currentTailnet = "CurrentTailnet"
    }
}

struct TailscalePeer: Codable {
    let hostName: String
    let dnsName: String
    let tailscaleIPs: [String]
    let os: String
    let online: Bool
    let lastSeen: Date?
    let curAddr: String?
    let relay: String?
    let exitNode: Bool
}
```

### WiFi Details (CoreWLAN)

```swift
import CoreWLAN

actor WiFiCollector {
    func collect() -> WiFiSnapshot? {
        guard let iface = CWWiFiClient.shared().interface() else { return nil }
        
        return WiFiSnapshot(
            ssid: iface.ssid(),
            bssid: iface.bssid(),
            channel: iface.wlanChannel()?.channelNumber,
            band: bandName(iface.wlanChannel()),
            rssi: iface.rssiValue(),  // dBm
            noiseMeasurement: iface.noiseMeasurement(),  // dBm
            snr: iface.rssiValue() - iface.noiseMeasurement(),
            txRate: iface.transmitRate(),  // Mbps
            security: securityName(iface.security()),
            countryCode: iface.countryCode()
        )
    }
    
    func scanForNetworks() -> [WiFiNetwork]? {
        guard let iface = CWWiFiClient.shared().interface() else { return nil }
        guard let networks = try? iface.scanForNetworks(withSSID: nil) else { return nil }
        
        return networks.map { net in
            WiFiNetwork(
                ssid: net.ssid ?? "(hidden)",
                bssid: net.bssid ?? "",
                rssi: net.rssiValue,
                channel: net.wlanChannel?.channelNumber ?? 0,
                band: bandName(net.wlanChannel)
            )
        }
    }
    
    private func bandName(_ channel: CWChannel?) -> String {
        guard let ch = channel else { return "Unknown" }
        switch ch.channelBand {
        case .band2GHz: return "2.4 GHz"
        case .band5GHz: return "5 GHz"
        case .band6GHz: return "6 GHz"
        @unknown default: return "Unknown"
        }
    }
}
```

### Internet Speed Testing

```swift
actor SpeedTestRunner {
    func run() async throws -> SpeedTestResult {
        // Use Apple's built-in networkQuality tool (macOS 12+)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/networkQuality")
        task.arguments = ["-v", "-c"]  // verbose + JSON output
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        try task.run()
        
        // Run on low-priority queue, don't block UI
        return try await withCheckedThrowingContinuation { continuation in
            task.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                do {
                    let result = try JSONDecoder().decode(NetworkQualityResult.self, from: data)
                    continuation.resume(returning: SpeedTestResult(
                        downloadMbps: result.dl_throughput / 1_000_000,
                        uploadMbps: result.ul_throughput / 1_000_000,
                        responsiveness: result.responsiveness,  // RPM
                        timestamp: Date()
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
```

### Listening Ports Inventory

```swift
func listeningPorts() -> [ListeningPort] {
    var ports: [ListeningPort] = []
    
    let allProcs = SysctlWrapper.allProcesses()
    for proc in allProcs {
        let pid = proc.kp_proc.p_pid
        let sockets = LibProc.socketInfo(for: pid)
        
        for socket in sockets where socket.state == .listen {
            let enrichedName = enrichmentEngine.enrich(pid) ?? processName(for: pid)
            ports.append(ListeningPort(
                port: socket.localPort,
                protocol: socket.protocol,
                bindAddress: socket.localAddress,  // 0.0.0.0 vs 127.0.0.1
                processName: enrichedName,
                pid: pid,
                isExposed: socket.localAddress == "0.0.0.0" || socket.localAddress == "::"
            ))
        }
    }
    
    return ports.sorted(by: { $0.port < $1.port })
}
```

### Bonjour/mDNS Service Discovery

```swift
import Foundation

class BonjourCollector: NSObject, NetServiceBrowserDelegate {
    private let browser = NetServiceBrowser()
    private var discoveredServices: [BonjourService] = []
    
    func startDiscovery() {
        browser.delegate = self
        // Search common service types
        let types = ["_http._tcp.", "_ssh._tcp.", "_airplay._tcp.", 
                     "_smb._tcp.", "_nfs._tcp.", "_rfb._tcp."]
        for type in types {
            browser.searchForServices(ofType: type, inDomain: "local.")
        }
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.resolve(withTimeout: 5.0)
        discoveredServices.append(BonjourService(
            name: service.name,
            type: service.type,
            domain: service.domain,
            host: service.hostName,
            port: service.port
        ))
    }
}
```

### Firewall Status

```swift
func firewallStatus() -> FirewallSnapshot {
    // Application Firewall
    let globalState = shellOutput("/usr/libexec/ApplicationFirewall/socketfilterfw", args: ["--getglobalstate"])
    let stealthMode = shellOutput("/usr/libexec/ApplicationFirewall/socketfilterfw", args: ["--getstealthmode"])
    
    // Packet Filter
    let pfStatus = shellOutput("/sbin/pfctl", args: ["-si"]) // Requires helper for root
    
    return FirewallSnapshot(
        applicationFirewallEnabled: globalState.contains("enabled"),
        stealthModeEnabled: stealthMode.contains("enabled"),
        packetFilterEnabled: pfStatus.contains("Status: Enabled")
    )
}
```
