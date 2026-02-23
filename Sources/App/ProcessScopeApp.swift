import SwiftUI

@main
struct ProcessScopeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environmentObject(appState)
                .environmentObject(appState.moduleRegistry)
                .environmentObject(appState.metricsViewModel)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1100, height: 750)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra("ProcessScope", systemImage: "gauge.with.dots.needle.33percent") {
            MenuBarView()
                .environmentObject(appState)
                .environmentObject(appState.metricsViewModel)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(appState.moduleRegistry)
        }
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure app doesn't show in dock if only menu bar mode
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false // Keep running for menu bar
    }
}
