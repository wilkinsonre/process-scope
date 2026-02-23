import SwiftUI

/// Overview panel with 6 widget cards in an adaptive grid
struct OverviewPanel: View {
    @EnvironmentObject var metrics: MetricsViewModel

    private let columns = [
        GridItem(.adaptive(minimum: 280, maximum: 400), spacing: 16)
    ]

    var body: some View {
        ScrollView {
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
            }
        }
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
            }
        }
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
