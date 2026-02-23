import SwiftUI
import Charts

/// Mini sparkline chart for time series data
struct SparklineView: View {
    let data: [Double]
    let color: Color
    var maxValue: Double? = nil

    var body: some View {
        Chart {
            ForEach(Array(data.enumerated()), id: \.offset) { index, value in
                LineMark(
                    x: .value("Time", index),
                    y: .value("Value", value)
                )
                .foregroundStyle(color.gradient)
                .interpolationMethod(.catmullRom)

                AreaMark(
                    x: .value("Time", index),
                    y: .value("Value", value)
                )
                .foregroundStyle(color.opacity(0.1).gradient)
                .interpolationMethod(.catmullRom)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...(maxValue ?? (data.max() ?? 100) * 1.1))
    }
}
