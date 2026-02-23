import SwiftUI
import Charts

/// Detail view for the Power & Thermal module.
/// Shows total power sparkline, per-component breakdown, battery card,
/// thermal status with temperatures, and CPU frequency/throttle detection.
struct PowerDetailView: View {
    @EnvironmentObject var metrics: MetricsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                powerSparklineSection
                componentBreakdownSection
                thermalSection
                frequencySection
                batterySection
            }
            .padding()
        }
        .navigationTitle("Power & Thermal")
    }

    // MARK: - Power Sparkline

    @ViewBuilder
    private var powerSparklineSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Total Power", systemImage: "bolt.fill")
                        .font(.headline)
                    Spacer()
                    if let watts = metrics.powerSnapshot?.totalWatts {
                        Text("\(watts, specifier: "%.1f") W")
                            .font(.title2.monospacedDigit().bold())
                            .foregroundStyle(.orange)
                    } else {
                        Text("--")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }

                if !metrics.powerHistory.isEmpty {
                    SparklineView(data: metrics.powerHistory, color: .orange)
                        .frame(height: 60)
                        .drawingGroup()
                } else {
                    Text("Power data collecting...")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(height: 60)
                        .frame(maxWidth: .infinity)
                }

                Text("60-second history")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Component Breakdown

    @ViewBuilder
    private var componentBreakdownSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("Component Breakdown", systemImage: "chart.bar.fill")
                    .font(.headline)

                if let power = metrics.componentPower {
                    let breakdown = power.breakdown
                    let total = power.totalWatts

                    if !breakdown.isEmpty && total > 0 {
                        // Stacked bar
                        SegmentedBar(segments: breakdown.map { item in
                            SegmentedBar.Segment(
                                value: item.watts / total,
                                color: componentColor(item.name),
                                label: "\(item.name): \(String(format: "%.1f", item.watts)) W"
                            )
                        })
                        .frame(height: 16)

                        // Component table
                        ForEach(breakdown, id: \.name) { item in
                            HStack {
                                Circle()
                                    .fill(componentColor(item.name))
                                    .frame(width: 10, height: 10)
                                Text(item.name)
                                    .font(.subheadline)
                                Spacer()
                                Text("\(item.watts, specifier: "%.2f") W")
                                    .font(.subheadline.monospacedDigit())
                                Text("(\(total > 0 ? item.watts / total * 100 : 0, specifier: "%.0f")%)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 40, alignment: .trailing)
                            }
                        }
                    } else {
                        unavailableRow("No component data available")
                    }
                } else {
                    unavailableRow("IOReport not available on this hardware")
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Thermal Section

    @ViewBuilder
    private var thermalSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Thermal Status", systemImage: "thermometer.medium")
                        .font(.headline)
                    Spacer()
                    ThermalPill(state: metrics.thermalState)
                }

                if metrics.isThrottled {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("System is throttling performance")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                }

                HStack {
                    temperatureCard(
                        label: "CPU",
                        symbol: "cpu",
                        temperature: metrics.cpuTemp
                    )
                    temperatureCard(
                        label: "GPU",
                        symbol: "gpu",
                        temperature: metrics.gpuTemp
                    )
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Frequency Section

    @ViewBuilder
    private var frequencySection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("CPU Frequency", systemImage: "waveform.path")
                    .font(.headline)

                if let freq = metrics.cpuFrequency {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Current")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(Int(freq.currentMHz)) MHz")
                                .font(.title3.monospacedDigit())
                        }

                        Divider()
                            .frame(height: 40)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Maximum")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(Int(freq.maxMHz)) MHz")
                                .font(.title3.monospacedDigit())
                        }

                        Spacer()

                        // Frequency ratio gauge
                        VStack(spacing: 4) {
                            RingGauge(
                                value: freq.frequencyRatio,
                                color: freq.isThrottled ? .orange : .green,
                                lineWidth: 6
                            )
                            .frame(width: 50, height: 50)
                            Text(freq.isThrottled ? "Throttled" : "Normal")
                                .font(.caption2)
                                .foregroundStyle(freq.isThrottled ? .orange : .green)
                        }
                    }
                } else {
                    unavailableRow("CPU frequency data unavailable")
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Battery Section

    @ViewBuilder
    private var batterySection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("Battery", systemImage: "battery.100percent")
                    .font(.headline)

                if let battery = metrics.batteryInfo {
                    HStack(alignment: .top, spacing: 16) {
                        // Charge ring gauge
                        VStack(spacing: 4) {
                            RingGauge(
                                value: Double(battery.chargePercent) / 100.0,
                                color: batteryColor(battery),
                                lineWidth: 8
                            )
                            .frame(width: 80, height: 80)
                            Text(batteryStatusText(battery))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(battery.chargePercent)%")
                                .font(.title.monospacedDigit())

                            Divider()

                            batteryDetailRow(
                                symbol: "heart",
                                label: "Health",
                                value: String(format: "%.1f%%", battery.healthPercent)
                            )
                            batteryDetailRow(
                                symbol: "arrow.triangle.2.circlepath",
                                label: "Cycles",
                                value: "\(battery.cycleCount)"
                            )
                            batteryDetailRow(
                                symbol: "thermometer",
                                label: "Temperature",
                                value: String(format: "%.1f C", battery.temperature)
                            )

                            if let rate = battery.chargeRateWatts {
                                batteryDetailRow(
                                    symbol: "bolt",
                                    label: rate >= 0 ? "Charge Rate" : "Drain Rate",
                                    value: String(format: "%.1f W", abs(rate))
                                )
                            }

                            if let remaining = battery.timeRemainingMinutes {
                                let hours = remaining / 60
                                let mins = remaining % 60
                                batteryDetailRow(
                                    symbol: "clock",
                                    label: battery.isCharging ? "Until Full" : "Remaining",
                                    value: "\(hours)h \(mins)m"
                                )
                            }

                            if battery.optimizedChargingEnabled {
                                HStack(spacing: 4) {
                                    Image(systemName: "leaf")
                                        .foregroundStyle(.green)
                                    Text("Optimized Charging")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                }
                            }
                        }

                        Spacer()
                    }
                } else {
                    HStack {
                        Image(systemName: "desktopcomputer")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Text("No battery detected (desktop Mac)")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Helper Views

    private func temperatureCard(label: String, symbol: String, temperature: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(label)
                    .font(.subheadline)
            }
            if let temp = temperature {
                Text(String(format: "%.1f C", temp))
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(temperatureColor(temp))
            } else {
                Text("--")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }

    private func batteryDetailRow(symbol: String, label: String, value: String) -> some View {
        HStack {
            Label(label, systemImage: symbol)
                .font(.caption)
            Spacer()
            Text(value)
                .font(.caption.monospacedDigit())
        }
    }

    private func unavailableRow(_ text: String) -> some View {
        HStack {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Color Helpers

    private func componentColor(_ name: String) -> Color {
        switch name {
        case "CPU": return .blue
        case "GPU": return .green
        case "ANE": return .purple
        case "DRAM": return .orange
        default: return .secondary
        }
    }

    private func temperatureColor(_ temp: Double) -> Color {
        if temp > 95 { return .red }
        if temp > 80 { return .orange }
        if temp > 60 { return .yellow }
        return .primary
    }

    private func batteryColor(_ battery: IOKitWrapper.BatteryInfo) -> Color {
        if battery.isCharging { return .green }
        if battery.chargePercent <= 10 { return .red }
        if battery.chargePercent <= 20 { return .orange }
        return .blue
    }

    private func batteryStatusText(_ battery: IOKitWrapper.BatteryInfo) -> String {
        if battery.isCharging { return "Charging" }
        if battery.isPluggedIn { return "Plugged In" }
        return "On Battery"
    }
}
