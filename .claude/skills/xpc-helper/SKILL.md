---
name: xpc-helper
description: XPC helper tool patterns for privileged LaunchDaemon communication. Use when implementing the ProcessScope Helper daemon, setting up SMAppService registration, configuring NSXPCConnection, or handling audit token validation.
---

# XPC Helper Tool Patterns

## Architecture
```
App (user space) ──NSXPCConnection──> Helper (root, LaunchDaemon)
                  Mach service name:
                  com.processscope.helper
```

## Shared XPC Protocol

This file has target membership in BOTH the app and helper targets:

```swift
// Sources/Core/XPC/PSHelperProtocol.swift
import Foundation

/// Snapshot of all process data collected by the helper
struct ProcessSnapshot: Codable {
    let processes: [ProcessRecord]
    let timestamp: Date
}

struct ProcessRecord: Codable {
    let pid: pid_t
    let ppid: pid_t
    let name: String
    let executablePath: String?
    let arguments: [String]
    let workingDirectory: String?
    let user: String
    let cpuTimeUser: UInt64
    let cpuTimeSystem: UInt64
    let rssBytes: UInt64
    let virtualBytes: UInt64
}

struct SystemMetricsSnapshot: Codable {
    let cpuPerCore: [Double]
    let gpuUtilization: Double?
    let gpuPowerWatts: Double?
    let anePowerWatts: Double?
    let thermalState: Int  // 0=nominal, 1=fair, 2=serious, 3=critical
    let fanSpeedRPM: Int?
}

struct NetworkSnapshot: Codable {
    let connections: [NetworkConnectionRecord]
}

struct NetworkConnectionRecord: Codable {
    let pid: pid_t
    let localAddress: String
    let localPort: UInt16
    let remoteAddress: String
    let remotePort: UInt16
    let protocolType: String  // "tcp", "udp"
    let state: String
    let bytesIn: UInt64
    let bytesOut: UInt64
}

/// XPC protocol — defines what the app can ask the helper
@objc protocol PSHelperProtocol {
    func getProcessSnapshot(reply: @escaping (Data?, Error?) -> Void)
    func getSystemMetrics(reply: @escaping (Data?, Error?) -> Void)
    func getNetworkConnections(reply: @escaping (Data?, Error?) -> Void)
    func getHelperVersion(reply: @escaping (String) -> Void)
}
```

**IMPORTANT:** XPC protocols must use `@objc` and Objective-C compatible types. Complex types are serialized as `Data` via `Codable`, not passed directly.

## Helper Daemon Implementation

```swift
// Helper/main.swift
import Foundation

let delegate = HelperToolDelegate()
let listener = NSXPCListener(machServiceName: "com.processscope.helper")
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
```

```swift
// Helper/HelperTool.swift
import Foundation

class HelperToolDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        // CRITICAL: Validate the connecting app's code signature
        guard validateClient(connection: newConnection) else {
            return false
        }
        
        newConnection.exportedInterface = NSXPCInterface(with: PSHelperProtocol.self)
        newConnection.exportedObject = DataCollectionService()
        newConnection.invalidationHandler = { /* cleanup */ }
        newConnection.resume()
        return true
    }
    
    private func validateClient(connection: NSXPCConnection) -> Bool {
        // Use audit token to verify the connecting process is signed
        // with our Team ID
        let token = connection.auditToken
        // SecCodeCopySigningInformation with audit token
        // Verify Team ID matches expected value
        return true // TODO: Implement full validation
    }
}
```

## App-Side Connection Manager

```swift
// Sources/Core/XPC/HelperConnection.swift
import Foundation

actor HelperConnection {
    private var connection: NSXPCConnection?
    
    func connect() -> NSXPCConnection {
        if let existing = connection {
            return existing
        }
        
        let conn = NSXPCConnection(machServiceName: "com.processscope.helper")
        conn.remoteObjectInterface = NSXPCInterface(with: PSHelperProtocol.self)
        conn.invalidationHandler = { [weak self] in
            Task { await self?.handleInvalidation() }
        }
        conn.resume()
        connection = conn
        return conn
    }
    
    func getProcessSnapshot() async throws -> ProcessSnapshot {
        let conn = connect()
        let proxy = conn.remoteObjectProxyWithErrorHandler { error in
            // Handle XPC error
        } as! PSHelperProtocol
        
        return try await withCheckedThrowingContinuation { continuation in
            proxy.getProcessSnapshot { data, error in
                if let error { continuation.resume(throwing: error); return }
                guard let data else { continuation.resume(throwing: XPCError.noData); return }
                do {
                    let snapshot = try JSONDecoder().decode(ProcessSnapshot.self, from: data)
                    continuation.resume(returning: snapshot)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func handleInvalidation() {
        connection = nil
    }
}
```

## SMAppService Helper Registration

```swift
// Sources/App/HelperInstaller.swift
import ServiceManagement

enum HelperInstallStatus {
    case installed
    case notInstalled
    case requiresApproval
}

@MainActor
class HelperInstaller: ObservableObject {
    @Published var status: HelperInstallStatus = .notInstalled
    
    func checkStatus() {
        let service = SMAppService.daemon(plistName: "com.processscope.helper.plist")
        switch service.status {
        case .enabled:
            status = .installed
        case .requiresApproval:
            status = .requiresApproval
        case .notRegistered, .notFound:
            status = .notInstalled
        @unknown default:
            status = .notInstalled
        }
    }
    
    func install() throws {
        let service = SMAppService.daemon(plistName: "com.processscope.helper.plist")
        try service.register()
        checkStatus()
    }
    
    func uninstall() throws {
        let service = SMAppService.daemon(plistName: "com.processscope.helper.plist")
        try service.unregister()
        checkStatus()
    }
}
```

## Degraded Mode (No Helper)

When helper is not installed, the app still works with reduced capability:

```swift
actor ProcessDataProvider {
    private let helperConnection: HelperConnection?
    private let localCollector: LocalProcessCollector  // current-user only
    
    var isPrivileged: Bool { helperConnection != nil }
    
    func getProcesses() async throws -> [ProcessRecord] {
        if let helper = helperConnection {
            return try await helper.getProcessSnapshot().processes
        }
        // Fallback: can only see current user's processes
        return localCollector.collectCurrentUserProcesses()
    }
}
```

## Code Signing Requirements

For XPC to work:
1. Both app and helper signed with same Team ID
2. Helper must be in `Contents/Library/LaunchDaemons/` inside app bundle (for `SMAppService`)
3. Helper's `Info.plist` must declare `SMAuthorizedClients` with app's signing requirement
4. App's `Info.plist` must declare `SMPrivilegedExecutables` with helper's signing requirement

```xml
<!-- Helper Info.plist -->
<key>SMAuthorizedClients</key>
<array>
    <string>identifier "com.processscope.app" and anchor apple generic and certificate leaf[subject.OU] = "TEAM_ID"</string>
</array>
```
