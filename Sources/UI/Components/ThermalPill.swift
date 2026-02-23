import SwiftUI

/// Pill-shaped thermal state indicator
struct ThermalPill: View {
    let state: Int

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(stateColor)
                .frame(width: 8, height: 8)
            Text(stateLabel)
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(stateColor.opacity(0.15), in: Capsule())
    }

    private var stateColor: Color {
        switch state {
        case 0: .green
        case 1: .yellow
        case 2: .orange
        case 3: .red
        default: .secondary
        }
    }

    private var stateLabel: String {
        switch state {
        case 0: "Nominal"
        case 1: "Fair"
        case 2: "Serious"
        case 3: "Critical"
        default: "Unknown"
        }
    }
}
