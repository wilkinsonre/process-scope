import SwiftUI

/// Menu bar popover content
struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var metrics: MetricsViewModel

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Text("ProcessScope")
                    .font(.headline)
                Spacer()
                Button(action: openMainWindow) {
                    Image(systemName: "macwindow")
                }
                .buttonStyle(.borderless)
                .help("Open Dashboard")
            }

            Divider()

            // Quick stats
            HStack(spacing: 16) {
                miniStat(symbol: "cpu", label: "CPU", value: String(format: "%.0f%%", metrics.cpuTotalUsage))
                miniStat(symbol: "memorychip", label: "Mem", value: String(format: "%.0f%%", metrics.memoryPressure))
                if let gpu = metrics.gpuUtilization {
                    miniStat(symbol: "gpu", label: "GPU", value: String(format: "%.0f%%", gpu))
                }
            }

            // Mini sparkline
            SparklineView(data: metrics.cpuHistory, color: .blue, maxValue: 100)
                .frame(height: 24)

            Divider()

            // Process count
            HStack {
                Text("\(metrics.processCount) processes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                ThermalPill(state: metrics.thermalState)
            }

            Divider()

            // Quick actions
            Button("Settings...") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .buttonStyle(.borderless)

            Button("Quit ProcessScope") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
        }
        .padding()
        .frame(width: 280)
    }

    private func miniStat(symbol: String, label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.caption, design: .rounded).monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title.contains("ProcessScope") || $0.isKeyWindow }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
}
