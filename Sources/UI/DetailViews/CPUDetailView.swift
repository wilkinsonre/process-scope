import SwiftUI
import Charts

/// Detailed CPU view with per-core heatmap and sparklines
struct CPUDetailView: View {
    @EnvironmentObject var metrics: MetricsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Total CPU usage
                GroupBox("Total CPU Usage") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("\(metrics.cpuTotalUsage, specifier: "%.1f")%")
                                .font(.system(.largeTitle, design: .rounded).monospacedDigit())
                            Spacer()
                            let load = MachWrapper.loadAverage()
                            VStack(alignment: .trailing) {
                                Text("Load Average")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(load.one, specifier: "%.2f") / \(load.five, specifier: "%.2f") / \(load.fifteen, specifier: "%.2f")")
                                    .font(.caption.monospacedDigit())
                            }
                        }
                        SparklineView(data: metrics.cpuHistory, color: .blue, maxValue: 100)
                            .frame(height: 80)
                    }
                    .padding(.vertical, 4)
                }

                // Per-core heatmap
                GroupBox("Per-Core Usage") {
                    VStack(alignment: .leading, spacing: 8) {
                        HeatmapStrip(values: metrics.cpuPerCore)
                            .frame(height: 24)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: 4) {
                            ForEach(Array(metrics.cpuPerCore.enumerated()), id: \.offset) { index, value in
                                VStack(spacing: 2) {
                                    Text("C\(index)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text("\(value, specifier: "%.0f")%")
                                        .font(.caption.monospacedDigit())
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Top CPU consumers
                GroupBox("Top Processes") {
                    let topProcesses = metrics.processes
                        .sorted { $0.cpuTimeUser + $0.cpuTimeSystem > $1.cpuTimeUser + $1.cpuTimeSystem }
                        .prefix(10)

                    ForEach(Array(topProcesses), id: \.pid) { proc in
                        HStack {
                            Text(proc.name)
                                .lineLimit(1)
                            Spacer()
                            Text("PID \(proc.pid)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("CPU")
    }
}
