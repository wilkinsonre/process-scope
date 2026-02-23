import SwiftUI

/// Main dashboard with dynamic sidebar and content area
struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var registry: ModuleRegistry

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            if let selectedID = appState.selectedModuleID {
                moduleDetailView(for: selectedID)
            } else {
                OverviewPanel()
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private func moduleDetailView(for id: String) -> some View {
        switch id {
        case "overview":
            OverviewPanel()
        case "cpu":
            CPUDetailView()
        case "memory":
            MemoryDetailView()
        case "gpu":
            GPUDetailView()
        case "processes":
            ProcessExplorerView()
        case "network":
            NetworkDetailView()
        case "storage":
            DiskDetailView()
        case "power":
            PowerDetailView()
        case "bluetooth":
            PlaceholderDetailView(title: "Bluetooth", symbol: "bluetooth")
        case "audio":
            PlaceholderDetailView(title: "Audio", symbol: "speaker.wave.2")
        case "display":
            PlaceholderDetailView(title: "Display", symbol: "display")
        case "security":
            PlaceholderDetailView(title: "Security", symbol: "lock.shield")
        case "developer":
            PlaceholderDetailView(title: "Developer", symbol: "hammer")
        default:
            OverviewPanel()
        }
    }
}

// MARK: - Placeholder for unimplemented modules

struct PlaceholderDetailView: View {
    let title: String
    let symbol: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title)
            Text("Coming soon")
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(title)
    }
}
