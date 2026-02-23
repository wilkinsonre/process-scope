import SwiftUI

/// Inspector panel showing full process details
struct ProcessInspectorView: View {
    let node: ProcessTreeNode

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text(node.enrichedLabel ?? node.process.name)
                        .font(.title2)
                    Text("PID \(node.process.pid)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                // Info sections
                inspectorSection("General") {
                    inspectorRow("User", value: node.process.user)
                    inspectorRow("Status", value: node.process.status.rawValue.capitalized)
                    inspectorRow("Parent PID", value: "\(node.process.ppid)")
                    if let start = node.process.startTime {
                        inspectorRow("Started", value: start.formatted())
                    }
                }

                if let execPath = node.process.executablePath {
                    inspectorSection("Executable") {
                        Text(execPath)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }

                if !node.process.arguments.isEmpty {
                    inspectorSection("Arguments") {
                        ForEach(Array(node.process.arguments.enumerated()), id: \.offset) { _, arg in
                            Text(arg)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                }

                if let workDir = node.process.workingDirectory {
                    inspectorSection("Working Directory") {
                        Text(workDir)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }

                inspectorSection("Resources") {
                    inspectorRow("Memory (RSS)", value: ByteCountFormatter.string(fromByteCount: Int64(node.process.rssBytes), countStyle: .memory))
                    inspectorRow("Virtual", value: ByteCountFormatter.string(fromByteCount: Int64(node.process.virtualBytes), countStyle: .memory))
                }

                // Children
                if !node.children.isEmpty {
                    inspectorSection("Children (\(node.children.count))") {
                        ForEach(node.children, id: \.process.pid) { child in
                            HStack {
                                Text(child.process.name)
                                    .font(.caption)
                                Spacer()
                                Text("\(child.process.pid)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .background(.regularMaterial)
    }

    private func inspectorSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func inspectorRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
        }
    }
}
