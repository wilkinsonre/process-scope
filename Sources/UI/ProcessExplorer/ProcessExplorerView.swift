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

                // Process list
                List(selection: $selectedPID) {
                    OutlineGroup(filteredTree, id: \.process.pid, children: \.optionalChildren) { node in
                        ProcessRowView(node: node)
                            .tag(node.process.pid)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))

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
