import SwiftUI

/// Circular gauge showing a percentage value
struct RingGauge: View {
    let value: Double // 0.0 to 1.0
    let color: Color
    var lineWidth: CGFloat = 6

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(value, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: value)
            Text("\(Int(value * 100))")
                .font(.system(.caption2, design: .rounded).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}
