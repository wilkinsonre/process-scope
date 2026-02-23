import SwiftUI

/// Single row in the process tree
struct ProcessRowView: View {
    let node: ProcessTreeNode

    var body: some View {
        HStack(spacing: 8) {
            // Process icon
            Image(systemName: processIcon)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            // Name/enriched label
            VStack(alignment: .leading, spacing: 1) {
                Text(node.enrichedLabel ?? node.process.name)
                    .lineLimit(1)
                if let workDir = node.process.workingDirectory {
                    Text(workDir)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // PID
            Text("\(node.process.pid)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)

            // Memory
            Text(ByteCountFormatter.string(fromByteCount: Int64(node.memoryBytes), countStyle: .memory))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.vertical, 1)
    }

    private var processIcon: String {
        switch node.process.status {
        case .running: "play.circle.fill"
        case .sleeping: "moon.fill"
        case .stopped: "stop.circle.fill"
        case .zombie: "exclamationmark.triangle.fill"
        case .unknown: "questionmark.circle"
        }
    }
}
