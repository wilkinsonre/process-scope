import SwiftUI

/// Process tree view with enriched labels
struct ProcessExplorerView: View {
    @EnvironmentObject var metrics: MetricsViewModel
    @State private var searchText = ""
    @State private var selectedPID: pid_t?
    @State private var showInspector = false

    var body: some View {
        HSplitView {
            // Process tree
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Filter processes...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(.regularMaterial)

                Divider()

                // Process list (virtualized via List + OutlineGroup)
                List(selection: $selectedPID) {
                    OutlineGroup(filteredTree, id: \.process.pid, children: \.optionalChildren) { node in
                        ProcessRowView(node: node)
                            .tag(node.process.pid)
                            .id(node.process.pid)
                            .contextMenu {
                                Button("Copy PID") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString("\(node.process.pid)", forType: .string)
                                }
                                Button("Copy Process Name") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(node.process.name, forType: .string)
                                }
                                if let path = node.process.executablePath {
                                    Button("Copy Executable Path") {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(path, forType: .string)
                                    }
                                }
                                if !node.process.arguments.isEmpty {
                                    Button("Copy Command Line") {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(
                                            node.process.arguments.joined(separator: " "),
                                            forType: .string
                                        )
                                    }
                                }
                            }
                            .accessibilityLabel("\(node.enrichedLabel ?? node.process.name), PID \(node.process.pid)")
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .id(filteredTree.count)

                // Status bar
                HStack {
                    Text("\(metrics.processCount) processes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(.regularMaterial)
            }

            // Inspector panel
            if showInspector, let pid = selectedPID,
               let node = ProcessTreeBuilder.find(pid: pid, in: metrics.processTree) {
                ProcessInspectorView(node: node)
                    .frame(minWidth: 280, maxWidth: 350)
            }
        }
        .toolbar {
            ToolbarItem {
                Toggle(isOn: $showInspector) {
                    Image(systemName: "sidebar.right")
                }
                .help("Toggle Inspector")
            }
        }
        .navigationTitle("Processes")
    }

    private var filteredTree: [ProcessTreeNode] {
        guard !searchText.isEmpty else { return metrics.processTree }
        let flat = ProcessTreeBuilder.flatten(metrics.processTree)
        return flat.filter {
            $0.process.name.localizedCaseInsensitiveContains(searchText) ||
            ($0.enrichedLabel?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            String($0.process.pid).contains(searchText)
        }
    }
}

// MARK: - Tree node children helper

extension ProcessTreeNode {
    var optionalChildren: [ProcessTreeNode]? {
        children.isEmpty ? nil : children
    }
}
