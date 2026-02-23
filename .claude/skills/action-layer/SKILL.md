---
name: action-layer
description: Action layer implementation for ProcessScope. Use when implementing process kill/suspend/resume, drive eject operations, Docker container lifecycle actions, network actions (SSH-to-terminal, DNS flush, speed test, ping), system actions, clipboard operations, audit trail logging, and confirmation dialog flows.
---

# Action Layer Implementation

## Design Principles (from PRD A2.1)
1. **Off by default** — every action category disabled until user enables in Settings → Actions
2. **Confirm before destroy** — destructive actions show ConfirmationDialog with context
3. **Audit trail** — all actions logged to `~/.processscope/actions.log`
4. **Keyboard-first** — every action has a keyboard shortcut
5. **Undo where possible** — suspend→resume, stop→start
6. **Helper-gated** — privileged actions route through XPC helper

## Action Infrastructure

### Action Configuration (persisted)

```swift
@MainActor
class ActionConfiguration: ObservableObject {
    // Process Actions
    @AppStorage("action.process.kill") var processKillEnabled = false
    @AppStorage("action.process.suspend") var processSuspendEnabled = false
    @AppStorage("action.process.renice") var processReniceEnabled = false
    @AppStorage("action.process.forceQuit") var forceQuitEnabled = true
    
    // Storage Actions
    @AppStorage("action.storage.eject") var ejectEnabled = true
    @AppStorage("action.storage.forceEject") var forceEjectEnabled = false
    @AppStorage("action.storage.reconnect") var reconnectEnabled = false
    
    // Network Actions
    @AppStorage("action.network.sshTerminal") var sshTerminalEnabled = true
    @AppStorage("action.network.speedTest") var speedTestEnabled = true
    @AppStorage("action.network.pingTrace") var pingTraceEnabled = true
    @AppStorage("action.network.killConnection") var killConnectionEnabled = false
    @AppStorage("action.network.dnsFlush") var dnsFlushEnabled = false
    
    // Docker Actions
    @AppStorage("action.docker.lifecycle") var dockerLifecycleEnabled = true
    @AppStorage("action.docker.logs") var dockerLogsEnabled = true
    @AppStorage("action.docker.exec") var dockerExecEnabled = true
    @AppStorage("action.docker.remove") var dockerRemoveEnabled = false
    @AppStorage("action.docker.pull") var dockerPullEnabled = false
    
    // System Actions
    @AppStorage("action.system.purge") var purgeEnabled = false
    @AppStorage("action.system.restartServices") var restartServicesEnabled = false
    @AppStorage("action.system.power") var powerActionsEnabled = false
    
    // Confirmation Behavior
    @AppStorage("action.confirm.destructive") var alwaysConfirmDestructive = true
    @AppStorage("action.confirm.skipReversible") var skipConfirmReversible = false
}
```

### Audit Trail

```swift
actor AuditTrail {
    private let logPath: String
    private let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    
    init() {
        let dir = NSHomeDirectory() + "/.processscope"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        logPath = dir + "/actions.log"
    }
    
    func log(action: String, target: String, outcome: ActionOutcome) {
        let entry = "\(dateFormatter.string(from: Date())) | \(action) | \(target) | \(outcome.rawValue)\n"
        if let data = entry.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logPath) {
                let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: logPath))
                handle?.seekToEndOfFile()
                handle?.write(data)
                handle?.closeFile()
            } else {
                try? data.write(to: URL(fileURLWithPath: logPath))
            }
        }
    }
    
    func readLog() -> [AuditEntry] {
        guard let data = FileManager.default.contents(atPath: logPath),
              let text = String(data: data, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { AuditEntry(line: String($0)) }
    }
}

enum ActionOutcome: String {
    case success, failed, cancelled, helperUnavailable = "helper_unavailable"
}
```

### Confirmation Flow

```swift
@MainActor
class ActionViewModel: ObservableObject {
    @Published var pendingAction: PendingAction?
    @Published var showConfirmation = false
    
    private let auditTrail = AuditTrail()
    private let helperConnection: HelperConnection
    private let config: ActionConfiguration
    
    func requestKill(_ process: EnrichedProcess, force: Bool) {
        guard config.processKillEnabled else { return }
        
        pendingAction = PendingAction(
            title: force ? "Force Kill Process?" : "Kill Process?",
            detail: "This will \(force ? "forcefully terminate" : "send SIGTERM to") \"\(process.enrichedLabel)\" (PID \(process.pid))",
            warningIcon: "exclamationmark.triangle.fill",
            isDestructive: true,
            confirmLabel: force ? "Force Kill" : "Kill",
            affectedItems: process.children.map { $0.enrichedLabel },
            execute: { [weak self] in
                await self?.executeKill(process, force: force)
            }
        )
        showConfirmation = true
    }
    
    func toggleSuspend(_ process: EnrichedProcess) {
        guard config.processSuspendEnabled else { return }
        
        // Suspend/resume is reversible — may skip confirmation
        if config.skipConfirmReversible {
            Task { await executeSuspendToggle(process) }
        } else {
            pendingAction = PendingAction(
                title: process.isSuspended ? "Resume Process?" : "Suspend Process?",
                detail: "\"\(process.enrichedLabel)\" — this is reversible",
                warningIcon: "pause.circle",
                isDestructive: false,
                confirmLabel: process.isSuspended ? "Resume" : "Suspend",
                affectedItems: [],
                execute: { [weak self] in await self?.executeSuspendToggle(process) }
            )
            showConfirmation = true
        }
    }
    
    func confirmAction() {
        guard let action = pendingAction else { return }
        showConfirmation = false
        Task { await action.execute() }
    }
}
```

## Process Actions

```swift
extension ActionViewModel {
    private func executeKill(_ process: EnrichedProcess, force: Bool) async {
        let signal: Int32 = force ? SIGKILL : SIGTERM
        let actionName = force ? "FORCE_KILL" : "KILL"
        
        // Own user's processes: direct signal
        // Other users' processes: route through helper
        if isOwnProcess(process) {
            let result = kill(process.pid, signal)
            await auditTrail.log(
                action: actionName,
                target: "\(process.enrichedLabel) (PID \(process.pid))",
                outcome: result == 0 ? .success : .failed
            )
        } else {
            do {
                try await helperConnection.killProcess(pid: process.pid, signal: signal)
                await auditTrail.log(action: actionName, target: "\(process.enrichedLabel) (PID \(process.pid))", outcome: .success)
            } catch {
                await auditTrail.log(action: actionName, target: "\(process.enrichedLabel) (PID \(process.pid))", outcome: .failed)
            }
        }
    }
    
    private func executeSuspendToggle(_ process: EnrichedProcess) async {
        let signal: Int32 = process.isSuspended ? SIGCONT : SIGSTOP
        let actionName = process.isSuspended ? "RESUME" : "SUSPEND"
        let result = kill(process.pid, signal)
        await auditTrail.log(
            action: actionName,
            target: "\(process.enrichedLabel) (PID \(process.pid))",
            outcome: result == 0 ? .success : .failed
        )
    }
    
    func killProjectProcesses(_ project: ProjectGroup) {
        pendingAction = PendingAction(
            title: "Kill All \(project.name) Processes?",
            detail: "This will terminate \(project.processes.count) processes",
            warningIcon: "exclamationmark.triangle.fill",
            isDestructive: true,
            confirmLabel: "Kill All",
            affectedItems: project.processes.map { $0.enrichedLabel },
            execute: { [weak self] in
                for proc in project.processes {
                    await self?.executeKill(proc, force: false)
                }
            }
        )
        showConfirmation = true
    }
}
```

## Docker Container Actions

```swift
actor DockerActionService {
    private let socketPath: String
    private let session: URLSession
    
    init(socketPath: String = "/var/run/docker.sock") {
        self.socketPath = socketPath
        let config = URLSessionConfiguration.default
        // Configure for Unix domain socket
        self.session = URLSession(configuration: config)
    }
    
    func stopContainer(id: String) async throws {
        try await post("/containers/\(id)/stop")
    }
    
    func startContainer(id: String) async throws {
        try await post("/containers/\(id)/start")
    }
    
    func restartContainer(id: String) async throws {
        try await post("/containers/\(id)/restart")
    }
    
    func pauseContainer(id: String) async throws {
        try await post("/containers/\(id)/pause")
    }
    
    func unpauseContainer(id: String) async throws {
        try await post("/containers/\(id)/unpause")
    }
    
    func removeContainer(id: String) async throws {
        try await delete("/containers/\(id)")
    }
    
    func containerLogs(id: String, tail: Int = 100) async throws -> String {
        let url = URL(string: "http://localhost/v1.43/containers/\(id)/logs?stdout=1&stderr=1&tail=\(tail)")!
        let (data, _) = try await session.data(from: url)
        return String(data: data, encoding: .utf8) ?? ""
    }
    
    func execShellInTerminal(containerID: String) {
        // Open Terminal.app with: docker exec -it <id> sh
        let script = "tell application \"Terminal\" to do script \"docker exec -it \(containerID) sh\""
        let appleScript = NSAppleScript(source: script)
        appleScript?.executeAndReturnError(nil)
    }
    
    func inspectContainer(id: String) async throws -> DockerContainerDetail {
        let url = URL(string: "http://localhost/v1.43/containers/\(id)/json")!
        let (data, _) = try await session.data(from: url)
        return try JSONDecoder().decode(DockerContainerDetail.self, from: data)
    }
    
    func pullImage(name: String) async throws {
        try await post("/images/create?fromImage=\(name)")
    }
    
    private func post(_ path: String) async throws {
        var request = URLRequest(url: URL(string: "http://localhost/v1.43\(path)")!)
        request.httpMethod = "POST"
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw DockerError.requestFailed(path: path)
        }
    }
    
    private func delete(_ path: String) async throws {
        var request = URLRequest(url: URL(string: "http://localhost/v1.43\(path)")!)
        request.httpMethod = "DELETE"
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw DockerError.requestFailed(path: path)
        }
    }
}
```

## Network Actions

```swift
extension ActionViewModel {
    func sshToHost(_ session: SSHSession) {
        guard config.sshTerminalEnabled else { return }
        let command = session.sshCommand  // "ssh user@host -p port"
        let script = "tell application \"Terminal\" to do script \"\(command)\""
        let appleScript = NSAppleScript(source: script)
        appleScript?.executeAndReturnError(nil)
        Task { await auditTrail.log(action: "SSH_TO_HOST", target: session.host, outcome: .success) }
    }
    
    func flushDNS() {
        guard config.dnsFlushEnabled else { return }
        requestConfirmation(
            title: "Flush DNS Cache?",
            detail: "This will clear the DNS resolver cache",
            isDestructive: false
        ) { [weak self] in
            // Requires helper for sudo
            try await self?.helperConnection.flushDNS()
            await self?.auditTrail.log(action: "DNS_FLUSH", target: "system", outcome: .success)
        }
    }
    
    func ping(host: String) async -> [PingResult] {
        // Background ICMP ping with results
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/sbin/ping")
        task.arguments = ["-c", "10", host]
        // Parse output lines for latency
        return []
    }
    
    func traceroute(host: String) async -> [TracerouteHop] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/traceroute")
        task.arguments = [host]
        // Parse hop-by-hop output
        return []
    }
}
```

## System Actions

```swift
extension ActionViewModel {
    func purgeMemory() {
        guard config.purgeEnabled else { return }
        requestConfirmation(
            title: "Purge Disk Cache?",
            detail: "This clears the filesystem cache. Apps will need to re-read from disk, which may briefly slow things down.",
            isDestructive: false
        ) { [weak self] in
            try await self?.helperConnection.purgeMemory()  // sudo purge
            await self?.auditTrail.log(action: "PURGE_MEMORY", target: "system", outcome: .success)
        }
    }
    
    func restartFinder() {
        requestConfirmation(title: "Restart Finder?", detail: "Finder windows will close and reopen", isDestructive: false) { [weak self] in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            task.arguments = ["Finder"]
            try task.run()
            await self?.auditTrail.log(action: "RESTART_FINDER", target: "Finder", outcome: .success)
        }
    }
    
    func restartDock() {
        requestConfirmation(title: "Restart Dock?", detail: "The Dock will disappear briefly and reappear", isDestructive: false) { [weak self] in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            task.arguments = ["Dock"]
            try task.run()
            await self?.auditTrail.log(action: "RESTART_DOCK", target: "Dock", outcome: .success)
        }
    }
}
```

## Clipboard Actions (Global)

```swift
extension ActionViewModel {
    func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
    
    func revealInFinder(_ process: EnrichedProcess) {
        guard let path = process.executablePath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
    
    /// Context-aware copy: changes based on what's selected
    func contextualCopy(process: EnrichedProcess?) {
        guard let proc = process else { return }
        let text = "\(proc.enrichedLabel) (PID \(proc.pid)) — \(proc.arguments.joined(separator: " "))"
        copyToPasteboard(text)
    }
}
```

## Keyboard Shortcuts

```swift
extension View {
    func processActionShortcuts(actionVM: ActionViewModel, selectedProcess: EnrichedProcess?) -> some View {
        self
            .keyboardShortcut(.delete, modifiers: .command)  // ⌘⌫ Kill
            // NOTE: SwiftUI keyboard shortcuts are limited
            // Full implementation uses NSEvent.addLocalMonitorForEvents
    }
}

// Full keyboard shortcut handling via AppDelegate
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
            return event
        }
    }
    
    private func handleKeyEvent(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        
        switch (event.keyCode, flags) {
        case (51, .command):          // ⌘⌫ Kill
            actionVM.requestKill(selectedProcess, force: false)
        case (51, [.command, .shift]): // ⌘⇧⌫ Force Kill
            actionVM.requestKill(selectedProcess, force: true)
        case (35, .command):           // ⌘P Suspend/Resume toggle
            actionVM.toggleSuspend(selectedProcess)
        case (3, [.command, .shift]):  // ⌘⇧F Reveal in Finder
            actionVM.revealInFinder(selectedProcess)
        case (8, .command):            // ⌘C Copy (contextual)
            actionVM.contextualCopy(process: selectedProcess)
        case (8, [.command, .shift]):  // ⌘⇧C Copy command line
            actionVM.copyToPasteboard(selectedProcess?.fullCommandLine ?? "")
        default: break
        }
    }
}
```

## XPC Helper Protocol Extensions (for actions)

```swift
// Add to PSHelperProtocol.swift
@objc protocol PSHelperProtocol {
    // ... existing data collection methods ...
    
    // Action methods
    func killProcess(pid: Int32, signal: Int32, reply: @escaping (Bool, Error?) -> Void)
    func purgeMemory(reply: @escaping (Bool, Error?) -> Void)
    func flushDNS(reply: @escaping (Bool, Error?) -> Void)
    func forceEjectVolume(mountPoint: String, reply: @escaping (Bool, Error?) -> Void)
    func reconnectNetworkVolume(path: String, reply: @escaping (Bool, Error?) -> Void)
    func setProcessPriority(pid: Int32, priority: Int32, reply: @escaping (Bool, Error?) -> Void)
}
```
