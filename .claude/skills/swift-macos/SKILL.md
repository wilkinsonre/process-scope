---
name: swift-macos
description: Swift 6 and macOS native development patterns. Use when writing SwiftUI views, setting up Xcode targets, configuring code signing, implementing Swift Concurrency patterns, or working with macOS-specific APIs like SMAppService and NSXPCConnection.
---

# Swift 6 + macOS Native Development Patterns

## Swift 6 Concurrency Model

ProcessScope uses strict concurrency. Key patterns:

### Actors for Shared State
```swift
actor MetricsStore {
    private var cpuHistory: [Double] = []
    
    func append(_ value: Double) {
        cpuHistory.append(value)
        if cpuHistory.count > 60 { cpuHistory.removeFirst() }
    }
    
    func history() -> [Double] { cpuHistory }
}
```

### @MainActor for ViewModels
```swift
@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var cpuUsage: Double = 0
    @Published var memoryPressure: MemoryPressure = .nominal
    
    private let pollingCoordinator: PollingCoordinator
    
    func startMonitoring() {
        Task {
            for await snapshot in pollingCoordinator.criticalStream {
                cpuUsage = snapshot.cpuTotal
                memoryPressure = snapshot.memoryPressure
            }
        }
    }
}
```

### DispatchSourceTimer for Polling
```swift
final class PollingCoordinator: @unchecked Sendable {
    private let criticalTimer: DispatchSourceTimer
    private let criticalQueue = DispatchQueue(label: "com.processscope.poll.critical")
    
    init() {
        criticalTimer = DispatchSource.makeTimerSource(queue: criticalQueue)
        criticalTimer.schedule(deadline: .now(), repeating: .milliseconds(500))
    }
    
    func start() {
        criticalTimer.setEventHandler { [weak self] in
            self?.collectCriticalMetrics()
        }
        criticalTimer.resume()
    }
}
```

## Xcode Project Structure

Two targets required:
1. **ProcessScope** (App target) — SwiftUI app, Developer ID Application signed
2. **ProcessScopeHelper** (Command Line Tool target) — LaunchDaemon, Developer ID Application signed

Both must share:
- `PSHelperProtocol.swift` via target membership (not a framework)
- Same Team ID for XPC audit token validation

### Info.plist Keys (App)
```xml
<key>LSUIElement</key>
<true/>  <!-- Menu bar app, no dock icon when window closed -->
<key>NSMainStoryboardFile</key>
<!-- OMIT — pure SwiftUI lifecycle -->
```

### launchd.plist (Helper)
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.processscope.helper</string>
    <key>MachServices</key>
    <dict>
        <key>com.processscope.helper</key>
        <true/>
    </dict>
    <key>ProgramArguments</key>
    <array>
        <string>/Library/PrivilegedHelperTools/com.processscope.helper</string>
    </array>
</dict>
</plist>
```

## SwiftUI Patterns

### Menu Bar App Entry Point
```swift
@main
struct ProcessScopeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    var body: some Scene {
        WindowGroup {
            DashboardView()
        }
        MenuBarExtra("ProcessScope", systemImage: "gauge.with.dots.needle.33percent") {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)
        Settings {
            SettingsView()
        }
    }
}
```

### Sidebar Navigation
```swift
struct DashboardView: View {
    @State private var selection: SidebarItem = .overview
    
    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.icon)
            }
            .navigationSplitViewColumnWidth(200)
        } detail: {
            switch selection {
            case .overview: OverviewPanel()
            case .cpu: CPUDetailView()
            // ...
            }
        }
    }
}
```

### Ring Gauge Component
```swift
struct RingGauge: View {
    let value: Double // 0...1
    let label: String
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 8)
            Circle()
                .trim(from: 0, to: value)
                .stroke(gaugeColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text("\(Int(value * 100))%")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    var gaugeColor: Color {
        switch value {
        case ..<0.6: return .green
        case ..<0.85: return .yellow
        default: return .red
        }
    }
}
```

## Code Signing for Helper Tools

Entitlements file for the app (`ProcessScope.entitlements`):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.application-identifier</key>
    <string>$(TeamIdentifierPrefix)com.processscope.app</string>
</dict>
</plist>
```

**IMPORTANT:** ProcessScope cannot use App Sandbox — it needs to communicate with the helper via XPC Mach services and access Docker sockets. It ships outside the App Store.

## Swift Charts Usage
```swift
import Charts

struct SparklineView: View {
    let data: [TimeSeries]
    
    var body: some View {
        Chart(data) { point in
            LineMark(
                x: .value("Time", point.timestamp),
                y: .value("Value", point.value)
            )
            .foregroundStyle(.blue.gradient)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...100)
    }
}
```

## Error Handling Pattern
Every collector wraps failures gracefully:
```swift
protocol SystemCollector: Sendable {
    associatedtype Snapshot
    func collect() async throws -> Snapshot
}

// In ViewModel:
do {
    let gpuSnapshot = try await gpuCollector.collect()
    gpuUtilization = gpuSnapshot.utilization
} catch {
    gpuAvailable = false  // UI shows "unavailable"
    logger.warning("GPU collector failed: \(error)")
}
```
