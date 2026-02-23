import SwiftUI

/// Horizontal strip showing per-core CPU usage as a heatmap
struct HeatmapStrip: View {
    let values: [Double] // 0-100 per core

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                RoundedRectangle(cornerRadius: 2)
                    .fill(heatColor(for: value))
                    .frame(minWidth: 4)
                    .help("Core \(index): \(value, specifier: "%.1f")%")
            }
        }
    }

    private func heatColor(for value: Double) -> Color {
        switch value {
        case 0..<20: return .green.opacity(0.3)
        case 20..<50: return .green
        case 50..<75: return .yellow
        case 75..<90: return .orange
        default: return .red
        }
    }
}
