import SwiftUI

struct PowerDetailView: View {
    @EnvironmentObject var metrics: MetricsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox("Thermal State") {
                    HStack {
                        ThermalPill(state: metrics.thermalState)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("Battery") {
                    if let battery = IOKitWrapper.shared.batteryInfo() {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                RingGauge(
                                    value: Double(battery.currentCapacity) / Double(max(battery.maxCapacity, 1)),
                                    color: battery.isCharging ? .green : .blue,
                                    lineWidth: 8
                                )
                                .frame(width: 80, height: 80)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(Int(Double(battery.currentCapacity) / Double(max(battery.maxCapacity, 1)) * 100))%")
                                        .font(.title.monospacedDigit())
                                    Text(battery.isCharging ? "Charging" : (battery.isPluggedIn ? "Plugged In" : "On Battery"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }

                            Divider()

                            HStack {
                                Label("Cycles", systemImage: "arrow.triangle.2.circlepath")
                                Spacer()
                                Text("\(battery.cycleCount)")
                                    .monospacedDigit()
                            }
                            .font(.caption)

                            HStack {
                                Label("Health", systemImage: "heart")
                                Spacer()
                                let health = Double(battery.maxCapacity) / Double(max(battery.designCapacity, 1)) * 100
                                Text("\(health, specifier: "%.1f")%")
                                    .monospacedDigit()
                            }
                            .font(.caption)

                            HStack {
                                Label("Temperature", systemImage: "thermometer")
                                Spacer()
                                Text("\(battery.temperature, specifier: "%.1f")°C")
                                    .monospacedDigit()
                            }
                            .font(.caption)
                        }
                        .padding(.vertical, 4)
                    } else {
                        Text("No battery detected (desktop Mac)")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Power & Thermal")
    }
}
