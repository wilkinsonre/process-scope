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
            DisplayDetailView()
        case "security":
            SecurityDetailView()
        case "developer":
            DeveloperDetailView()
        default:
            OverviewPanel()
        }
    }
}

