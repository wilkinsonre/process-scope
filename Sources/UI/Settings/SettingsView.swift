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

// MARK: - Actions

/// Settings tab for configuring which actions are enabled and reviewing the audit trail.
///
/// Actions are grouped by category: process control, storage, and clipboard.
/// Destructive actions that require the privileged helper display a badge when
/// the helper is not installed.
struct ActionsSettingsTab: View {
    @EnvironmentObject var actionVM: ActionViewModel
    @State private var showingAuditTrail = false

    var body: some View {
        Form {
            // MARK: Process Actions

            Section("Process Actions") {
                Toggle(isOn: Binding(
                    get: { actionVM.configuration.processKillEnabled },
                    set: { actionVM.configuration.processKillEnabled = $0 }
                )) {
                    HStack {
                        Label("Kill / Force Kill", systemImage: "xmark.circle")
                        Spacer()
                        helperBadge
                    }
                }
                .accessibilityLabel("Toggle kill and force kill actions")

                Toggle(isOn: Binding(
                    get: { actionVM.configuration.processSuspendEnabled },
                    set: { actionVM.configuration.processSuspendEnabled = $0 }
                )) {
                    Label("Suspend / Resume", systemImage: "pause.circle")
                }
                .accessibilityLabel("Toggle suspend and resume actions")

                Toggle(isOn: Binding(
                    get: { actionVM.configuration.processReniceEnabled },
                    set: { actionVM.configuration.processReniceEnabled = $0 }
                )) {
                    HStack {
                        Label("Renice (Priority)", systemImage: "slider.horizontal.3")
                        Spacer()
                        helperBadge
                    }
                }
                .accessibilityLabel("Toggle renice priority actions")
            }

            // MARK: Storage Actions

            Section("Storage Actions") {
                Toggle(isOn: Binding(
                    get: { actionVM.configuration.ejectEnabled },
                    set: { actionVM.configuration.ejectEnabled = $0 }
                )) {
                    Label("Eject", systemImage: "eject")
                }
                .accessibilityLabel("Toggle eject action")

                Toggle(isOn: Binding(
                    get: { actionVM.configuration.forceEjectEnabled },
                    set: { actionVM.configuration.forceEjectEnabled = $0 }
                )) {
                    HStack {
                        Label("Force Eject", systemImage: "eject.fill")
                        Spacer()
                        helperBadge
                    }
                }
                .accessibilityLabel("Toggle force eject action")
            }

            // MARK: Clipboard

            Section("Clipboard") {
                Toggle(isOn: Binding(
                    get: { actionVM.configuration.copyEnabled },
                    set: { actionVM.configuration.copyEnabled = $0 }
                )) {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .accessibilityLabel("Toggle clipboard copy actions")
            }

            // MARK: Audit Trail

            Section("Audit Trail") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Action Log")
                        Text("All executed actions are recorded for review.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("View Action Log\u{2026}") {
                        showingAuditTrail = true
                    }
                    .accessibilityLabel("View action audit log")
                }
            }

            // MARK: Footer Note

            HStack {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text("All actions require confirmation before execution.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .sheet(isPresented: $showingAuditTrail) {
            VStack(spacing: 0) {
                AuditTrailView()
                HStack {
                    Spacer()
                    Button("Done") {
                        showingAuditTrail = false
                    }
                    .keyboardShortcut(.cancelAction)
                }
                .padding()
            }
            .frame(minWidth: 650, minHeight: 450)
        }
    }

    // MARK: - Helper Badge

    @ViewBuilder
    private var helperBadge: some View {
        if !actionVM.isHelperInstalled {
            Text("Requires Helper")
                .font(.caption2)
                .foregroundStyle(.orange)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.orange.opacity(0.12), in: Capsule())
        }
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
