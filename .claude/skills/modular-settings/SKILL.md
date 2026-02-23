---
name: modular-settings
description: Modular settings architecture and alert engine for ProcessScope. Use when implementing the ModuleRegistry, drag-to-reorder module configuration, alert threshold rules, YAML alert configuration, notification delivery (UNUserNotificationCenter), settings persistence, or the advanced settings panel.
---

# Modular Settings & Alert Engine

## Module Registry Architecture

Every module registers with a central registry. Disabled modules have ZERO overhead.

```swift
protocol ProcessScopeModule: AnyObject, Identifiable {
    var id: String { get }
    var displayName: String { get }
    var icon: String { get }
    var isEnabled: Bool { get set }
    var enabledByDefault: Bool { get }
    var order: Int { get set }
    var subFeatures: [SubFeature] { get }
    
    /// Called when module is enabled — start polling, allocate buffers
    func activate()
    /// Called when module is disabled — stop polling, deallocate everything
    func deactivate()
    /// Return the SwiftUI view for this module's detail page
    @MainActor func detailView() -> AnyView
}

class SubFeature: ObservableObject, Identifiable {
    let id: String
    let name: String
    @Published var isEnabled: Bool
    
    init(id: String, name: String, enabledByDefault: Bool) {
        self.id = id
        self.name = name
        self.isEnabled = enabledByDefault
    }
}
```

### Registry Implementation

```swift
@MainActor
class ModuleRegistry: ObservableObject {
    @Published var allModules: [any ProcessScopeModule] = []
    
    private let defaults = UserDefaults.standard
    
    func register(_ module: any ProcessScopeModule) {
        // Load persisted state
        let key = "module.\(module.id).enabled"
        if let stored = defaults.object(forKey: key) as? Bool {
            module.isEnabled = stored
        } else {
            module.isEnabled = module.enabledByDefault
        }
        
        let orderKey = "module.\(module.id).order"
        if let order = defaults.object(forKey: orderKey) as? Int {
            module.order = order
        }
        
        // Load sub-feature states
        for sub in module.subFeatures {
            let subKey = "module.\(module.id).sub.\(sub.id).enabled"
            if let stored = defaults.object(forKey: subKey) as? Bool {
                sub.isEnabled = stored
            }
        }
        
        allModules.append(module)
        allModules.sort { $0.order < $1.order }
        
        // Activate if enabled
        if module.isEnabled { module.activate() }
    }
    
    func setEnabled(_ module: any ProcessScopeModule, enabled: Bool) {
        module.isEnabled = enabled
        defaults.set(enabled, forKey: "module.\(module.id).enabled")
        
        if enabled {
            module.activate()
        } else {
            module.deactivate()  // ZERO overhead when disabled
        }
    }
    
    func reorder(from source: IndexSet, to destination: Int) {
        allModules.move(fromOffsets: source, toOffset: destination)
        for (i, module) in allModules.enumerated() {
            module.order = i
            defaults.set(i, forKey: "module.\(module.id).order")
        }
    }
    
    var enabledModules: [any ProcessScopeModule] {
        allModules.filter { $0.isEnabled }.sorted { $0.order < $1.order }
    }
}
```

### Example Module Registration

```swift
class CPUModule: ProcessScopeModule {
    let id = "cpu"
    let displayName = "CPU"
    let icon = "cpu"
    var isEnabled = true
    let enabledByDefault = true
    var order = 0
    
    let subFeatures: [SubFeature] = [
        SubFeature(id: "perCoreHeatmap", name: "Per-core heatmap", enabledByDefault: true),
        SubFeature(id: "epCluster", name: "E/P cluster breakdown", enabledByDefault: true),
        SubFeature(id: "frequency", name: "Frequency display", enabledByDefault: true),
    ]
    
    private var collector: CPUCollector?
    
    func activate() {
        collector = CPUCollector()
        // Register with polling coordinator
    }
    
    func deactivate() {
        // Unregister from polling coordinator
        collector = nil  // Deallocate everything
    }
    
    @MainActor func detailView() -> AnyView {
        AnyView(CPUDetailView())
    }
}
```

### Polling Coordinator Integration

```swift
final class PollingCoordinator: @unchecked Sendable {
    private var criticalSubscribers: [(String, () async -> Void)] = []
    private var standardSubscribers: [(String, () async -> Void)] = []
    private var extendedSubscribers: [(String, () async -> Void)] = []
    private var slowSubscribers: [(String, () async -> Void)] = []
    private var infrequentSubscribers: [(String, () async -> Void)] = []  // NEW: 60s tier
    
    func subscribe(moduleID: String, tier: PollingTier, handler: @escaping () async -> Void) {
        switch tier {
        case .critical: criticalSubscribers.append((moduleID, handler))
        case .standard: standardSubscribers.append((moduleID, handler))
        case .extended: extendedSubscribers.append((moduleID, handler))
        case .slow: slowSubscribers.append((moduleID, handler))
        case .infrequent: infrequentSubscribers.append((moduleID, handler))
        }
    }
    
    func unsubscribe(moduleID: String) {
        criticalSubscribers.removeAll { $0.0 == moduleID }
        standardSubscribers.removeAll { $0.0 == moduleID }
        extendedSubscribers.removeAll { $0.0 == moduleID }
        slowSubscribers.removeAll { $0.0 == moduleID }
        infrequentSubscribers.removeAll { $0.0 == moduleID }
    }
}

enum PollingTier {
    case critical    // 500ms
    case standard    // 1s
    case extended    // 3s
    case slow        // 10s
    case infrequent  // 60s (Amendment A addition)
}
```

---

## Alert Engine

### Alert Rule Data Model

```swift
struct AlertRule: Codable, Identifiable, ObservableObject {
    let id: UUID
    var name: String
    var condition: AlertCondition
    var duration: TimeInterval?  // nil = fire immediately, otherwise sustained
    var isEnabled: Bool
    var soundEnabled: Bool
    var message: String?
    
    @Published var isEditing: Bool = false
    
    enum CodingKeys: String, CodingKey {
        case id, name, condition, duration, isEnabled, soundEnabled, message
    }
}

enum AlertCondition: Codable {
    case cpuAbove(percent: Double)
    case memoryPressure(level: MemoryPressureLevel)
    case diskFreeBelow(percent: Double, volumePath: String)
    case thermalState(state: Int)  // 0-3
    case processRSSAbove(processName: String, bytes: UInt64)
    case volumeUnsafeDisconnect
    case customExpression(String)  // Future: DSL parser
    
    func evaluate(context: MetricsContext) -> Bool {
        switch self {
        case .cpuAbove(let threshold):
            return context.cpuTotal > threshold
        case .memoryPressure(let level):
            return context.memoryPressure.rawValue >= level.rawValue
        case .diskFreeBelow(let percent, let path):
            guard let volume = context.volumes.first(where: { $0.mountPoint == path }) else { return false }
            return volume.freePercent < percent
        case .thermalState(let state):
            return context.thermalState >= state
        case .processRSSAbove(let name, let bytes):
            return context.processes.contains { $0.name.contains(name) && $0.rssBytes > bytes }
        case .volumeUnsafeDisconnect:
            return context.hasUnsafeDisconnect
        case .customExpression:
            return false  // Future implementation
        }
    }
}
```

### Alert Engine (evaluates each polling tick)

```swift
actor AlertEngine {
    private var rules: [AlertRule] = []
    private var sustainedState: [UUID: Date] = [:]  // When condition first became true
    private var firedAlerts: [UUID: Date] = [:]  // Debounce: don't fire same alert twice in 60s
    
    func loadRules() {
        // Load from ~/.processscope/alerts.yaml + built-in defaults
        rules = loadYAMLAlertRules() ?? builtInRules()
    }
    
    func evaluate(context: MetricsContext) async -> [FiredAlert] {
        var alerts: [FiredAlert] = []
        
        for rule in rules where rule.isEnabled {
            let conditionMet = rule.condition.evaluate(context: context)
            
            if conditionMet {
                if let duration = rule.duration {
                    // Sustained condition check
                    if let start = sustainedState[rule.id] {
                        if Date().timeIntervalSince(start) >= duration {
                            if shouldFire(rule) {
                                alerts.append(FiredAlert(rule: rule, timestamp: Date()))
                                firedAlerts[rule.id] = Date()
                            }
                        }
                    } else {
                        sustainedState[rule.id] = Date()
                    }
                } else {
                    // Immediate fire
                    if shouldFire(rule) {
                        alerts.append(FiredAlert(rule: rule, timestamp: Date()))
                        firedAlerts[rule.id] = Date()
                    }
                }
            } else {
                sustainedState.removeValue(forKey: rule.id)
            }
        }
        
        return alerts
    }
    
    private func shouldFire(_ rule: AlertRule) -> Bool {
        // Debounce: don't fire same alert within 60 seconds
        guard let lastFired = firedAlerts[rule.id] else { return true }
        return Date().timeIntervalSince(lastFired) > 60
    }
    
    func builtInRules() -> [AlertRule] {
        [
            AlertRule(id: UUID(), name: "CPU Sustained High",
                     condition: .cpuAbove(percent: 90), duration: 30,
                     isEnabled: true, soundEnabled: false,
                     message: "CPU above 90% for 30 seconds"),
            AlertRule(id: UUID(), name: "Memory Pressure Critical",
                     condition: .memoryPressure(level: .critical), duration: nil,
                     isEnabled: true, soundEnabled: true, message: nil),
            AlertRule(id: UUID(), name: "Disk Nearly Full",
                     condition: .diskFreeBelow(percent: 5, volumePath: "/"), duration: nil,
                     isEnabled: true, soundEnabled: false,
                     message: "Boot volume below 5% free"),
            AlertRule(id: UUID(), name: "Thermal Throttling",
                     condition: .thermalState(state: 3), duration: nil,
                     isEnabled: true, soundEnabled: true, message: nil),
        ]
    }
}
```

### Notification Delivery

```swift
import UserNotifications

actor AlertNotificationService {
    private let center = UNUserNotificationCenter.current()
    
    func requestPermission() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }
    
    func deliver(_ alert: FiredAlert) async {
        let content = UNMutableNotificationContent()
        content.title = "ProcessScope"
        content.subtitle = alert.rule.name
        content.body = alert.rule.message ?? alert.rule.condition.description
        
        if alert.rule.soundEnabled {
            content.sound = .default
        }
        
        // Badge count for unacknowledged alerts
        content.badge = NSNumber(value: await unacknowledgedCount() + 1)
        
        let request = UNNotificationRequest(
            identifier: alert.id.uuidString,
            content: content,
            trigger: nil  // Deliver immediately
        )
        
        try? await center.add(request)
    }
    
    func clearBadge() {
        UNUserNotificationCenter.current().setBadgeCount(0)
    }
}
```

### YAML Alert Configuration

```yaml
# ~/.processscope/alerts.yaml
alerts:
  - name: "CPU Sustained High"
    condition: system.cpu.total > 90
    duration: 30s
    sound: false
    message: "CPU above 90% for 30 seconds"

  - name: "Memory Pressure Critical"
    condition: system.memory.pressure == critical
    sound: true

  - name: "Postgres Memory Leak"
    condition: process.name("postgres").rss > 2GB
    message: "Postgres RSS exceeded 2 GB"

  - name: "Disk Nearly Full"
    condition: volume.path("/").free_percent < 10
    message: "Boot volume below 10% free"

  - name: "Thermal Throttling"
    condition: system.thermal.state == critical
    sound: true

  - name: "External Drive Removed Unsafely"
    condition: volume.external.disconnected_without_eject
```

---

## Settings Persistence

```swift
// All settings use @AppStorage for automatic UserDefaults persistence
// Module order + enabled state persisted per-module
// Alert rules persisted as JSON to ~/.processscope/alerts.json
// Action audit trail at ~/.processscope/actions.log
// Custom enrichment rules at ~/.processscope/rules.yaml

// Advanced polling overrides
struct PollingSettings {
    @AppStorage("polling.dashboardVisible") var dashboardInterval: Double = 1.0
    @AppStorage("polling.menuBarOnly") var menuBarInterval: Double = 2.0
    @AppStorage("polling.onBattery") var batteryInterval: Double = 3.0
    @AppStorage("polling.critical") var criticalMs: Int = 500
    @AppStorage("polling.standard") var standardMs: Int = 1000
    @AppStorage("polling.extended") var extendedMs: Int = 3000
    @AppStorage("polling.slow") var slowMs: Int = 10000
    @AppStorage("polling.infrequent") var infrequentMs: Int = 60000
}
```
