import SwiftUI

/// Seven-tab settings view
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gear") }

            ModulesSettingsTab()
                .tabItem { Label("Modules", systemImage: "square.grid.2x2") }

            ActionsSettingsTab()
                .tabItem { Label("Actions", systemImage: "bolt") }

            AlertsSettingsTab()
                .tabItem { Label("Alerts", systemImage: "bell") }

            MenuBarSettingsTab()
                .tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }

            AdvancedSettingsTab()
                .tabItem { Label("Advanced", systemImage: "gearshape.2") }

            AboutSettingsTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 550, height: 400)
    }
}

// MARK: - General

struct GeneralSettingsTab: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showInDock") private var showInDock = true
    @StateObject private var helperInstaller = HelperInstaller()

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                Toggle("Show in Dock", isOn: $showInDock)
            }

            Section("Helper Daemon") {
                HStack {
                    Text("Status:")
                    Text(helperInstaller.status.rawValue)
                        .foregroundStyle(helperInstaller.status == .installed ? .green : .secondary)
                    Spacer()
                    if helperInstaller.status != .installed {
                        Button("Install") { try? helperInstaller.install() }
                    } else {
                        Button("Uninstall") { try? helperInstaller.uninstall() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Modules

struct ModulesSettingsTab: View {
    @EnvironmentObject var registry: ModuleRegistry

    var body: some View {
        Form {
            Section("Enabled Modules") {
                List {
                    ForEach(registry.orderedModules, id: \.id) { module in
                        Toggle(isOn: Binding(
                            get: { registry.isEnabled(module.id) },
                            set: { enabled in
                                Task { await registry.setEnabled(module.id, enabled: enabled) }
                            }
                        )) {
                            Label(module.displayName, systemImage: module.symbolName)
                        }
                    }
                    .onMove { registry.moveModule(from: $0, to: $1) }
                }
            }

            Text("Drag to reorder. Disabled modules have zero overhead.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Stub tabs

struct ActionsSettingsTab: View {
    var body: some View {
        Form {
            Text("Action settings will be configured in M5")
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct AlertsSettingsTab: View {
    var body: some View {
        Form {
            Text("Alert rules will be configured in M13")
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct MenuBarSettingsTab: View {
    @AppStorage("menuBarMode") private var menuBarMode = "compact"

    var body: some View {
        Form {
            Section("Menu Bar Style") {
                Picker("Display Mode", selection: $menuBarMode) {
                    Text("Mini").tag("mini")
                    Text("Compact").tag("compact")
                    Text("Sparkline").tag("sparkline")
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct AdvancedSettingsTab: View {
    var body: some View {
        Form {
            Text("Advanced polling and enrichment settings")
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct AboutSettingsTab: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
            Text("ProcessScope")
                .font(.title)
            Text("Version 0.1.0")
                .foregroundStyle(.secondary)
            Text("Native macOS System Monitor")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
