import SwiftUI

/// Overview panel with 6 widget cards in an adaptive grid
struct OverviewPanel: View {
    @EnvironmentObject var metrics: MetricsViewModel

    private let columns = [
        GridItem(.adaptive(minimum: 280, maximum: 400), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Privacy indicators — only shown when mic or camera is active
                PrivacyIndicatorRow()

                LazyVGrid(columns: columns, spacing: 16) {
                    CPUOverviewCard()
                    MemoryOverviewCard()
                    GPUOverviewCard()
                    NetworkOverviewCard()
                    DiskOverviewCard()
                    ThermalOverviewCard()
                }
                .padding()
            }
        }
        .navigationTitle("Overview")
    }
}

// MARK: - CPU Card

struct CPUOverviewCard: View {
    @EnvironmentObject var metrics: MetricsViewModel

    var body: some View {
        WidgetCard(title: "CPU", symbol: "cpu") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    RingGauge(value: metrics.cpuTotalUsage / 100, color: .blue)
                        .frame(width: 60, height: 60)
                    VStack(alignment: .leading) {
                        Text("\(metrics.cpuTotalUsage, specifier: "%.1f")%")
                            .font(.title2.monospacedDigit())
                        Text("\(metrics.cpuPerCore.count) cores")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                SparklineView(data: metrics.cpuHistory, color: .blue)
                    .frame(height: 30)
                    .drawingGroup()
            }
        }
        .contextMenu {
            Button("Copy CPU Usage") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(
                    String(format: "%.1f%%", metrics.cpuTotalUsage),
                    forType: .string
                )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("CPU usage \(Int(metrics.cpuTotalUsage)) percent")
    }
}

// MARK: - Memory Card

struct MemoryOverviewCard: View {
    @EnvironmentObject var metrics: MetricsViewModel

    var body: some View {
        WidgetCard(title: "Memory", symbol: "memorychip") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    RingGauge(value: metrics.memoryPressure / 100, color: pressureColor)
                        .frame(width: 60, height: 60)
                    VStack(alignment: .leading) {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(metrics.memoryUsed), countStyle: .memory))
                            .font(.title2.monospacedDigit())
                        Text("of \(ByteCountFormatter.string(fromByteCount: Int64(metrics.memoryTotal), countStyle: .memory))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                SegmentedBar(segments: memorySegments)
                    .frame(height: 8)
            }
        }
        .contextMenu {
            Button("Copy Memory Used") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(
                    ByteCountFormatter.string(fromByteCount: Int64(metrics.memoryUsed), countStyle: .memory),
                    forType: .string
                )
            }
            Button("Copy Memory Pressure") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(
                    String(format: "%.1f%%", metrics.memoryPressure),
                    forType: .string
                )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Memory pressure \(Int(metrics.memoryPressure)) percent")
    }

    private var pressureColor: Color {
        if metrics.memoryPressure > 80 { return .red }
        if metrics.memoryPressure > 60 { return .orange }
        return .green
    }

    private var memorySegments: [SegmentedBar.Segment] {
        let total = Double(max(metrics.memoryTotal, 1))
        return [
            .init(value: Double(metrics.memoryActive) / total, color: .blue, label: "Active"),
            .init(value: Double(metrics.memoryWired) / total, color: .orange, label: "Wired"),
            .init(value: Double(metrics.memoryCompressed) / total, color: .purple, label: "Compressed"),
            .init(value: Double(metrics.memoryFree) / total, color: .secondary.opacity(0.3), label: "Free"),
        ]
    }
}

// MARK: - GPU Card

struct GPUOverviewCard: View {
    @EnvironmentObject var metrics: MetricsViewModel

    var body: some View {
        WidgetCard(title: "GPU", symbol: "gpu") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    RingGauge(value: (metrics.gpuUtilization ?? 0) / 100, color: .green)
                        .frame(width: 60, height: 60)
                    VStack(alignment: .leading) {
                        if let gpu = metrics.gpuUtilization {
                            Text("\(gpu, specifier: "%.1f")%")
                                .font(.title2.monospacedDigit())
                        } else {
                            Text("N/A")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                        Text("Apple GPU")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                SparklineView(data: metrics.gpuHistory, color: .green)
                    .frame(height: 30)
                    .drawingGroup()
            }
        }
        .contextMenu {
            Button("Copy GPU Usage") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(
                    String(format: "%.1f%%", metrics.gpuUtilization ?? 0),
                    forType: .string
                )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("GPU usage \(Int(metrics.gpuUtilization ?? 0)) percent")
    }
}

// MARK: - Network Card

struct NetworkOverviewCard: View {
    @EnvironmentObject var metrics: MetricsViewModel

    var body: some View {
        WidgetCard(title: "Network", symbol: "network") {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(metrics.networkConnections.count) connections")
                    .font(.title2.monospacedDigit())
                Text("Monitoring active interfaces")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contextMenu {
            Button("Copy Connection Count") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(
                    "\(metrics.networkConnections.count) connections",
                    forType: .string
                )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(metrics.networkConnections.count) network connections")
    }
}

// MARK: - Disk Card

struct DiskOverviewCard: View {
    var body: some View {
        WidgetCard(title: "Storage", symbol: "internaldrive") {
            VStack(alignment: .leading, spacing: 8) {
                let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/")
                let total = attrs?[.systemSize] as? UInt64 ?? 0
                let free = attrs?[.systemFreeSize] as? UInt64 ?? 0
                let used = total - free

                HStack {
                    RingGauge(value: total > 0 ? Double(used) / Double(total) : 0, color: .orange)
                        .frame(width: 60, height: 60)
                    VStack(alignment: .leading) {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(free), countStyle: .file) + " free")
                            .font(.title2.monospacedDigit())
                        Text("of \(ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
        .contextMenu {
            Button("Copy Disk Free") {
                let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/")
                let free = attrs?[.systemFreeSize] as? UInt64 ?? 0
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(
                    ByteCountFormatter.string(fromByteCount: Int64(free), countStyle: .file) + " free",
                    forType: .string
                )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Disk storage overview")
    }
}

// MARK: - Thermal Card

struct ThermalOverviewCard: View {
    @EnvironmentObject var metrics: MetricsViewModel

    var body: some View {
        WidgetCard(title: "Thermal", symbol: "thermometer.medium") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ThermalPill(state: metrics.thermalState)
                    Spacer()
                }
                Text(thermalDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contextMenu {
            Button("Copy Thermal State") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(thermalDescription, forType: .string)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Thermal state: \(thermalDescription)")
    }

    private var thermalDescription: String {
        switch metrics.thermalState {
        case 0: "System running normally"
        case 1: "Slightly elevated thermal state"
        case 2: "System may throttle performance"
        case 3: "Critical — performance significantly reduced"
        default: "Unknown"
        }
    }
}

// MARK: - Privacy Indicator Row

/// Shows microphone and camera privacy indicators when active.
/// Correlates with macOS orange (mic) and green (camera) menu bar dots.
struct PrivacyIndicatorRow: View {
    @EnvironmentObject var metrics: MetricsViewModel

    private var isVisible: Bool {
        metrics.audioSnapshot.micInUse || metrics.audioSnapshot.cameraInUse
    }

    var body: some View {
        if isVisible {
            HStack(spacing: 16) {
                if metrics.audioSnapshot.micInUse {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(.orange)
                            .frame(width: 8, height: 8)
                        Image(systemName: "mic.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        if let firstProcess = metrics.audioSnapshot.micInUseBy.first {
                            Text("Mic: \(firstProcess)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Mic active")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Microphone in use by \(metrics.audioSnapshot.micInUseBy.first ?? "unknown")")
                }

                if metrics.audioSnapshot.cameraInUse {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                        Image(systemName: "camera.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                        Text("Camera")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Camera in use")
                }

                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.orange.opacity(0.05))
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
