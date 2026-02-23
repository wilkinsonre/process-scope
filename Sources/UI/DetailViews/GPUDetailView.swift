import SwiftUI

struct GPUDetailView: View {
    @EnvironmentObject var metrics: MetricsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox("GPU Utilization") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            RingGauge(value: (metrics.gpuUtilization ?? 0) / 100, color: .green, lineWidth: 10)
                                .frame(width: 100, height: 100)
                            VStack(alignment: .leading) {
                                if let gpu = metrics.gpuUtilization {
                                    Text("\(gpu, specifier: "%.1f")%")
                                        .font(.system(.largeTitle, design: .rounded).monospacedDigit())
                                } else {
                                    Text("Unavailable")
                                        .font(.title2)
                                        .foregroundStyle(.secondary)
                                }
                                Text("Apple GPU")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        SparklineView(data: metrics.gpuHistory, color: .green, maxValue: 100)
                            .frame(height: 80)
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding()
        }
        .navigationTitle("GPU & Neural Engine")
    }
}
