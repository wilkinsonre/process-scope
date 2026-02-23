---
name: swiftui-dashboard
description: SwiftUI dashboard patterns for ProcessScope. Use when building dashboard views, chart components, the process tree UI, menu bar widget, modular settings panel, action confirmation dialogs, or any detail view for the 12 modules. Includes patterns for virtualized lists, sparklines, heatmaps, adaptive layouts, and drag-to-reorder settings.
---

# SwiftUI Dashboard Patterns

## Design Language
- **Native macOS** — SF Symbols, system colors, vibrancy, no custom color palettes
- **Progressive disclosure** — Menu bar → Dashboard → Inspector
- System appearance respects Light/Dark/Auto
- `.font(.system(.body, design: .rounded))` for numeric displays
- No custom fonts — system only

## Sidebar Navigation Model (12 Modules)

```swift
struct SidebarItem: Identifiable, Hashable {
    let id: String
    let title: String
    let icon: String
    let isEnabled: Bool
    let order: Int
}

// Module registry drives sidebar dynamically
@MainActor
class SidebarViewModel: ObservableObject {
    @Published var items: [SidebarItem] = []
    
    func reload(from registry: ModuleRegistry) {
        items = registry.enabledModules
            .sorted(by: { $0.order < $1.order })
            .map { mod in
                SidebarItem(id: mod.id, title: mod.displayName, 
                           icon: mod.icon, isEnabled: mod.isEnabled, order: mod.order)
            }
        // Always prepend Overview
        items.insert(SidebarItem(id: "overview", title: "Overview", 
                                icon: "gauge.with.dots.needle.33percent", 
                                isEnabled: true, order: -1), at: 0)
    }
}

// Default module definitions
enum DefaultModule: String, CaseIterable {
    case cpu, memory, gpu, processes, storage, network
    case bluetooth, power, audio, display, security, developer
    
    var icon: String {
        switch self {
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .gpu: return "gpu"
        case .processes: return "list.bullet.indent"
        case .storage: return "internaldrive"
        case .network: return "network"
        case .bluetooth: return "wave.3.right"
        case .power: return "bolt.fill"
        case .audio: return "speaker.wave.2"
        case .display: return "display"
        case .security: return "lock.shield"
        case .developer: return "hammer"
        }
    }
    
    /// Modules enabled by default (PRD A3.2)
    var enabledByDefault: Bool {
        switch self {
        case .cpu, .memory, .gpu, .processes, .storage, .network, .power: return true
        case .bluetooth, .audio, .display, .security, .developer: return false
        }
    }
}
```

## Overview Panel Layout

Six widget cards in a responsive grid (base modules):

```swift
struct OverviewPanel: View {
    @EnvironmentObject var metrics: MetricsViewModel
    
    let columns = [
        GridItem(.adaptive(minimum: 280, maximum: 400), spacing: 16)
    ]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                CPUWidget(usage: metrics.cpuTotal, perCore: metrics.cpuPerCore)
                MemoryWidget(segments: metrics.memorySegments, pressure: metrics.memoryPressure)
                GPUWidget(utilization: metrics.gpuUtil, available: metrics.gpuAvailable)
                NetworkWidget(upload: metrics.netUp, download: metrics.netDown)
                DiskWidget(readRate: metrics.diskRead, writeRate: metrics.diskWrite)
                TopProcessesWidget(processes: metrics.topProcesses)
            }
            .padding()
        }
    }
}
```

## Widget Card Pattern

```swift
struct WidgetCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.headline)
            }
            content()
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
```

## Core Component Library

### Ring Gauge
```swift
struct RingGauge: View {
    let value: Double // 0...1
    let label: String
    
    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 8)
            Circle()
                .trim(from: 0, to: value)
                .stroke(gaugeColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text("\(Int(value * 100))%")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                Text(label).font(.caption2).foregroundStyle(.secondary)
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

### Segmented Bar (Memory)
```swift
struct SegmentedBar: View {
    let segments: [(label: String, value: Double, color: Color)]
    var total: Double { segments.map(\.value).reduce(0, +) }
    
    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                ForEach(segments.indices, id: \.self) { i in
                    let fraction = segments[i].value / total
                    RoundedRectangle(cornerRadius: 2)
                        .fill(segments[i].color)
                        .frame(width: geo.size.width * fraction)
                }
            }
        }
        .frame(height: 12)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
```

### Heatmap Strip (CPU Cores)
```swift
struct HeatmapStrip: View {
    let values: [Double]  // 0...1 per core
    var body: some View {
        HStack(spacing: 2) {
            ForEach(values.indices, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(heatColor(values[i]))
                    .frame(width: 12, height: 24)
            }
        }
    }
    func heatColor(_ value: Double) -> Color {
        switch value {
        case ..<0.3: return .green.opacity(0.3 + value)
        case ..<0.7: return .yellow.opacity(0.5 + value * 0.5)
        default: return .red.opacity(0.6 + value * 0.4)
        }
    }
}
```

### Sparkline with Swift Charts
```swift
import Charts

struct SparklineView: View {
    let data: [TimeSeriesPoint]
    let color: Color
    let showAxis: Bool
    
    var body: some View {
        Chart(data) { point in
            AreaMark(x: .value("Time", point.timestamp), y: .value("Value", point.value))
                .foregroundStyle(.linearGradient(
                    colors: [color.opacity(0.3), color.opacity(0.05)],
                    startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("Time", point.timestamp), y: .value("Value", point.value))
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
        }
        .chartXAxis(showAxis ? .automatic : .hidden)
        .chartYAxis(showAxis ? .automatic : .hidden)
    }
}
```

### Thermal Pill
```swift
struct ThermalPill: View {
    let state: ProcessInfo.ThermalState
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.caption)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(color.opacity(0.15), in: Capsule())
    }
    var label: String {
        switch state {
        case .nominal: "Nominal"; case .fair: "Fair"
        case .serious: "Serious"; case .critical: "Critical"
        @unknown default: "Unknown"
        }
    }
    var color: Color {
        switch state {
        case .nominal: .green; case .fair: .yellow
        case .serious: .orange; case .critical: .red
        @unknown default: .gray
        }
    }
}
```

## Process Tree View (Virtualized)

```swift
struct ProcessTreeView: View {
    @EnvironmentObject var processVM: ProcessViewModel
    @State private var selection: pid_t?
    
    var body: some View {
        HSplitView {
            List(selection: $selection) {
                OutlineGroup(processVM.rootProcesses, children: \.childrenOptional) { process in
                    ProcessRowView(process: process).tag(process.pid)
                }
            }
            .listStyle(.sidebar).frame(minWidth: 400)
            
            if let selected = selection, let process = processVM.process(for: selected) {
                ProcessInspectorView(process: process).frame(minWidth: 300)
            } else {
                Text("Select a process").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
```

## Action Confirmation Dialog Pattern

ALL destructive actions must use this pattern:

```swift
struct ActionConfirmationDialog: View {
    let action: PendingAction
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: action.warningIcon)
                .font(.largeTitle)
                .foregroundStyle(action.isDestructive ? .red : .orange)
            
            Text(action.title).font(.headline)
            Text(action.detail).font(.body).foregroundStyle(.secondary)
            
            if !action.affectedItems.isEmpty {
                GroupBox("Affected:") {
                    ForEach(action.affectedItems, id: \.self) { item in
                        Text("• \(item)").font(.caption)
                    }
                }
            }
            
            HStack {
                Button("Cancel", role: .cancel, action: onCancel)
                Button(action.confirmLabel, role: action.isDestructive ? .destructive : nil, action: onConfirm)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 380)
    }
}
```

## Context Menu Actions (per-row)

```swift
struct ProcessContextMenu: View {
    let process: EnrichedProcess
    @EnvironmentObject var actionVM: ActionViewModel
    
    var body: some View {
        Group {
            Button("Copy PID") { actionVM.copyToPasteboard("\(process.pid)") }
            Button("Copy Command Line") { actionVM.copyToPasteboard(process.fullCommandLine) }
            Button("Copy Process Path") { actionVM.copyToPasteboard(process.executablePath ?? "") }
            Divider()
            Button("Reveal in Finder") { actionVM.revealInFinder(process) }
            Divider()
            if actionVM.isSuspendEnabled {
                Button(process.isSuspended ? "Resume (⌘P)" : "Suspend (⌘P)") {
                    actionVM.toggleSuspend(process)
                }
            }
            if actionVM.isKillEnabled {
                Button("Kill Process (⌘⌫)") { actionVM.requestKill(process, force: false) }
                Button("Force Kill (⌘⇧⌫)") { actionVM.requestKill(process, force: true) }
            }
        }
    }
}
```

## Menu Bar Modes

```swift
struct MenuBarView: View {
    @EnvironmentObject var metrics: MetricsViewModel
    @AppStorage("menuBarMode") var mode: MenuBarMode = .compact
    
    var body: some View {
        switch mode {
        case .mini:
            Image(systemName: healthIcon).foregroundStyle(healthColor)
        case .compact:
            HStack(spacing: 6) {
                Label("\(Int(metrics.cpuTotal))%", systemImage: "cpu")
                Label("\(Int(metrics.memoryUsedPercent))%", systemImage: "memorychip")
                if metrics.gpuAvailable {
                    Label("\(Int(metrics.gpuUtil))%", systemImage: "gpu")
                }
            }
            .font(.system(.caption2, design: .monospaced))
        case .sparkline:
            HStack(spacing: 4) {
                MiniSparkline(data: metrics.cpuHistory, color: .blue).frame(width: 40, height: 14)
                MiniSparkline(data: metrics.memHistory, color: .green).frame(width: 40, height: 14)
            }
        }
    }
}
```

## Modular Settings Architecture

```swift
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }
            ModulesSettingsView()
                .tabItem { Label("Modules", systemImage: "square.grid.3x3") }
            ActionsSettingsView()
                .tabItem { Label("Actions", systemImage: "bolt.circle") }
            AlertsSettingsView()
                .tabItem { Label("Alerts", systemImage: "bell") }
            MenuBarSettingsView()
                .tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }
            AdvancedSettingsView()
                .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 600, height: 500)
    }
}
```

### Drag-to-Reorder Module List

```swift
struct ModulesSettingsView: View {
    @EnvironmentObject var registry: ModuleRegistry
    
    var body: some View {
        List {
            ForEach(registry.allModules) { module in
                ModuleToggleRow(module: module)
            }
            .onMove { from, to in
                registry.reorder(from: from, to: to)
            }
        }
    }
}

struct ModuleToggleRow: View {
    @ObservedObject var module: ModuleConfig
    @State private var isExpanded = false
    
    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(module.subFeatures) { sub in
                Toggle(sub.name, isOn: sub.$isEnabled)
                    .disabled(!module.isEnabled)
                    .padding(.leading)
            }
        } label: {
            HStack {
                Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                Toggle(isOn: $module.isEnabled) {
                    Label(module.displayName, systemImage: module.icon)
                }
            }
        }
    }
}
```

### Actions Settings Panel

```swift
struct ActionsSettingsView: View {
    @EnvironmentObject var actionConfig: ActionConfiguration
    
    var body: some View {
        Form {
            Section("Process Actions") {
                Toggle("Kill / Force Kill", isOn: $actionConfig.processKillEnabled)
                    .badge(actionConfig.helperInstalled ? nil : "Requires Helper")
                Toggle("Suspend / Resume", isOn: $actionConfig.processSuspendEnabled)
                Toggle("Renice (Priority)", isOn: $actionConfig.processReniceEnabled)
                Toggle("Force Quit Application", isOn: $actionConfig.forceQuitEnabled)
            }
            // Storage, Network, Docker, System sections follow same pattern
            
            Section("Confirmation Behavior") {
                Toggle("Always confirm destructive actions", isOn: $actionConfig.alwaysConfirmDestructive)
                Toggle("Skip confirmation for reversible actions", isOn: $actionConfig.skipConfirmReversible)
            }
        }
    }
}
```

### Alert Rule Editor

```swift
struct AlertRuleRow: View {
    @ObservedObject var rule: AlertRule
    
    var body: some View {
        HStack {
            Toggle("", isOn: $rule.isEnabled).labelsHidden()
            VStack(alignment: .leading) {
                Text(rule.name).font(.body)
                Text(rule.conditionDescription).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: { rule.isEditing = true }) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
        }
    }
}
```

## Volume Card (Storage Module)

```swift
struct VolumeCardView: View {
    let volume: VolumeInfo
    @EnvironmentObject var actionVM: ActionViewModel
    
    var body: some View {
        WidgetCard(title: volume.name, icon: volume.isExternal ? "externaldrive" : "internaldrive") {
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: volume.usedFraction)
                    .tint(volume.usedFraction > 0.9 ? .red : .accentColor)
                Text("\(volume.formattedUsed) / \(volume.formattedCapacity)")
                    .font(.caption)
                
                HStack {
                    Label(volume.connectionType, systemImage: "cable.connector")
                    Spacer()
                    Label(volume.filesystem, systemImage: "doc")
                }
                .font(.caption2).foregroundStyle(.secondary)
                
                if volume.isExternal {
                    HStack {
                        if volume.isSafeToEject {
                            Button("Eject") { actionVM.requestEject(volume) }
                                .buttonStyle(.bordered)
                        } else {
                            Label("\(volume.openFileCount) processes using volume", systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
            }
        }
    }
}
```

## SSH Session Row (Network Module)

```swift
struct SSHSessionRow: View {
    let session: SSHSession
    
    var body: some View {
        HStack {
            Image(systemName: "terminal")
            VStack(alignment: .leading) {
                Text("\(session.user)@\(session.host):\(session.port)")
                    .font(.system(.body, design: .monospaced))
                Text("Duration: \(session.formattedDuration) — ↑\(session.formattedUpload) ↓\(session.formattedDownload)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !session.tunnels.isEmpty {
                Label("\(session.tunnels.count) tunnels", systemImage: "arrow.triangle.branch")
                    .font(.caption2)
            }
        }
        .contextMenu {
            Button("SSH to Host") { NSWorkspace.shared.openTerminal(command: session.sshCommand) }
            Button("Copy SSH Command") { NSPasteboard.general.setString(session.sshCommand, forType: .string) }
        }
    }
}
```

## Bluetooth Device Card

```swift
struct BluetoothDeviceCard: View {
    let device: BluetoothDevice
    
    var body: some View {
        HStack {
            Image(systemName: device.typeIcon)  // "headphones", "computermouse", "keyboard"
            VStack(alignment: .leading) {
                Text(device.name).font(.body)
                if let battery = device.batteryLevel {
                    ProgressView(value: Double(battery) / 100.0)
                        .tint(battery < 20 ? .red : .green)
                    Text("\(battery)%").font(.caption2)
                }
                // AirPods: show L/R/Case separately
                if let airpods = device.airPodsDetail {
                    HStack(spacing: 12) {
                        BatteryPill(label: "L", level: airpods.left)
                        BatteryPill(label: "R", level: airpods.right)
                        BatteryPill(label: "Case", level: airpods.case_)
                    }
                }
            }
        }
    }
}
```

## Power Breakdown View

```swift
struct PowerBreakdownView: View {
    @EnvironmentObject var powerVM: PowerViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Total power sparkline
            SparklineView(data: powerVM.totalPowerHistory, color: .orange, showAxis: true)
                .frame(height: 100)
            
            Text("Total: \(powerVM.totalPowerWatts, specifier: "%.1f") W")
                .font(.system(.title2, design: .rounded))
            
            // Per-component breakdown
            ForEach(powerVM.components) { component in
                HStack {
                    Text(component.name).frame(width: 100, alignment: .leading)
                    ProgressView(value: component.watts / powerVM.totalPowerWatts)
                    Text("\(component.watts, specifier: "%.1f") W")
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 60, alignment: .trailing)
                }
            }
        }
        .padding()
    }
}
```
