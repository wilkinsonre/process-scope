import SwiftUI

/// Dynamic sidebar driven by ModuleRegistry
struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var registry: ModuleRegistry

    var body: some View {
        List(selection: $appState.selectedModuleID) {
            // Overview always first
            Label("Overview", systemImage: "gauge.with.dots.needle.33percent")
                .tag("overview" as String?)

            // Dynamic modules grouped by category
            ForEach(ModuleCategory.allCases, id: \.self) { category in
                let modulesInCategory = registry.enabledModules.filter { $0.category == category }
                if !modulesInCategory.isEmpty {
                    Section(category.rawValue) {
                        ForEach(modulesInCategory, id: \.id) { module in
                            Label(module.displayName, systemImage: module.symbolName)
                                .tag(module.id as String?)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("ProcessScope")
    }
}
