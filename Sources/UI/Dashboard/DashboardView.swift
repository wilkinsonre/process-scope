import SwiftUI

/// Main dashboard with dynamic sidebar and content area
struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var registry: ModuleRegistry
    @StateObject private var actionVM = ActionViewModel()

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
        .environmentObject(actionVM)
        .confirmationDialog(
            actionVM.pendingAction?.title ?? "",
            isPresented: $actionVM.showConfirmation,
            presenting: actionVM.pendingAction
        ) { pending in
            Button(pending.confirmLabel, role: pending.isDestructive ? .destructive : nil) {
                Task { await actionVM.confirmAction() }
            }
            Button("Cancel", role: .cancel) {
                actionVM.cancelAction()
            }
        } message: { pending in
            Text(pending.detail)
        }
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
            StorageDetailView()
        case "power":
            PowerDetailView()
        case "bluetooth":
            BluetoothDetailView()
        case "audio":
            AudioDetailView()
        case "display":
            PlaceholderDetailView(title: "Display", symbol: "display")
        case "security":
            PlaceholderDetailView(title: "Security", symbol: "lock.shield")
        case "developer":
            DockerDetailView()
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
