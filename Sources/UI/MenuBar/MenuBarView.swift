import SwiftUI

/// Menu bar popover content with three display modes
struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var metrics: MetricsViewModel
    @AppStorage("menuBarMode") private var menuBarMode = "compact"

    var body: some View {
        switch menuBarMode {
        case "mini":
            miniMode
        case "sparkline":
            sparklineMode
        default:
            compactMode
        }
    }

    // MARK: - Mini Mode

    /// Minimal view — key stats only, no charts
    private var miniMode: some View {
        VStack(spacing: 8) {
            header

            Divider()

            HStack(spacing: 16) {
                miniStat(symbol: "cpu", label: "CPU", value: String(format: "%.0f%%", metrics.cpuTotalUsage))
                miniStat(symbol: "memorychip", label: "Mem", value: String(format: "%.0f%%", metrics.memoryPressure))
                if let gpu = metrics.gpuUtilization {
                    miniStat(symbol: "gpu", label: "GPU", value: String(format: "%.0f%%", gpu))
                }
            }

            Divider()

            HStack {
                Text("\(metrics.processCount) processes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                ThermalPill(state: metrics.thermalState)
            }

            Divider()
            footerButtons
        }
        .padding()
        .frame(width: 240)
    }

    // MARK: - Compact Mode

    /// Full stats with sparkline and process count
    private var compactMode: some View {
        VStack(spacing: 12) {
            header

            Divider()

            HStack(spacing: 16) {
                miniStat(symbol: "cpu", label: "CPU", value: String(format: "%.0f%%", metrics.cpuTotalUsage))
                miniStat(symbol: "memorychip", label: "Mem", value: String(format: "%.0f%%", metrics.memoryPressure))
                if let gpu = metrics.gpuUtilization {
                    miniStat(symbol: "gpu", label: "GPU", value: String(format: "%.0f%%", gpu))
                }
            }

            SparklineView(data: metrics.cpuHistory, color: .blue, maxValue: 100)
                .frame(height: 24)

            Divider()

            HStack {
                Text("\(metrics.processCount) processes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                ThermalPill(state: metrics.thermalState)
            }

            Divider()
            footerButtons
        }
        .padding()
        .frame(width: 280)
    }

    // MARK: - Sparkline Mode

    /// Multi-metric sparkline view with charts for all key metrics
    private var sparklineMode: some View {
        VStack(spacing: 10) {
            header

            Divider()

            // CPU sparkline with label
            sparklineRow(
                label: "CPU",
                value: String(format: "%.0f%%", metrics.cpuTotalUsage),
                data: metrics.cpuHistory,
                color: .blue
            )

            // Memory sparkline
            sparklineRow(
                label: "Mem",
                value: String(format: "%.0f%%", metrics.memoryPressure),
                data: [metrics.memoryPressure],
                color: .orange
            )

            // GPU sparkline (if available)
            if let gpu = metrics.gpuUtilization {
                sparklineRow(
                    label: "GPU",
                    value: String(format: "%.0f%%", gpu),
                    data: metrics.gpuHistory,
                    color: .green
                )
            }

            Divider()

            HStack {
                Text("\(metrics.processCount) processes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                ThermalPill(state: metrics.thermalState)
            }

            Divider()
            footerButtons
        }
        .padding()
        .frame(width: 300)
    }

    // MARK: - Shared Components

    private var header: some View {
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
    }

    private var footerButtons: some View {
        HStack {
            Button("Settings...") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .buttonStyle(.borderless)

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
        }
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

    private func sparklineRow(label: String, value: String, data: [Double], color: Color) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .leading)

            SparklineView(data: data, color: color, maxValue: 100)
                .frame(height: 20)

            Text(value)
                .font(.system(.caption, design: .rounded).monospacedDigit())
                .frame(width: 36, alignment: .trailing)
        }
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title.contains("ProcessScope") || $0.isKeyWindow }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
}
