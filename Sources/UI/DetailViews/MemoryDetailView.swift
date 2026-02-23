import SwiftUI

/// Detailed memory view with pressure gauge and breakdown
struct MemoryDetailView: View {
    @EnvironmentObject var metrics: MetricsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox("Memory Pressure") {
                    HStack(spacing: 20) {
                        RingGauge(value: metrics.memoryPressure / 100, color: pressureColor, lineWidth: 10)
                            .frame(width: 100, height: 100)

                        VStack(alignment: .leading, spacing: 8) {
                            memoryRow("Used", value: metrics.memoryUsed, color: .blue)
                            memoryRow("Active", value: metrics.memoryActive, color: .blue)
                            memoryRow("Wired", value: metrics.memoryWired, color: .orange)
                            memoryRow("Compressed", value: metrics.memoryCompressed, color: .purple)
                            memoryRow("Free", value: metrics.memoryFree, color: .green)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("Memory Breakdown") {
                    SegmentedBar(segments: [
                        .init(value: Double(metrics.memoryActive) / Double(max(metrics.memoryTotal, 1)), color: .blue, label: "Active"),
                        .init(value: Double(metrics.memoryWired) / Double(max(metrics.memoryTotal, 1)), color: .orange, label: "Wired"),
                        .init(value: Double(metrics.memoryCompressed) / Double(max(metrics.memoryTotal, 1)), color: .purple, label: "Compressed"),
                        .init(value: Double(metrics.memoryFree) / Double(max(metrics.memoryTotal, 1)), color: .secondary.opacity(0.3), label: "Free"),
                    ])
                    .frame(height: 16)
                    .padding(.vertical, 4)
                }

                GroupBox("Top Memory Consumers") {
                    let topProcesses = metrics.processes
                        .sorted { $0.rssBytes > $1.rssBytes }
                        .prefix(10)

                    ForEach(Array(topProcesses), id: \.pid) { proc in
                        HStack {
                            Text(proc.name)
                                .lineLimit(1)
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: Int64(proc.rssBytes), countStyle: .memory))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Memory")
    }

    private var pressureColor: Color {
        if metrics.memoryPressure > 80 { return .red }
        if metrics.memoryPressure > 60 { return .orange }
        return .green
    }

    private func memoryRow(_ label: String, value: UInt64, color: Color) -> some View {
        HStack {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(.caption)
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}
