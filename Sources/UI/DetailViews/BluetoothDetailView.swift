import SwiftUI

/// Detailed Bluetooth view showing connected and paired devices with battery levels
struct BluetoothDetailView: View {
    @EnvironmentObject var metrics: MetricsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Bluetooth status header
                GroupBox("Bluetooth Status") {
                    HStack {
                        Image(systemName: metrics.bluetoothSnapshot.isBluetoothEnabled
                              ? "bluetooth"
                              : "bluetooth.slash")
                            .font(.title2)
                            .foregroundStyle(metrics.bluetoothSnapshot.isBluetoothEnabled
                                             ? .blue : .secondary)
                        Text(metrics.bluetoothSnapshot.isBluetoothEnabled
                             ? "Bluetooth is enabled"
                             : "Bluetooth is unavailable")
                            .font(.headline)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }

                // Connected devices
                GroupBox("Connected Devices") {
                    if metrics.bluetoothSnapshot.connectedDevices.isEmpty {
                        Text("No devices connected")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(metrics.bluetoothSnapshot.connectedDevices) { device in
                                BluetoothDeviceCard(device: device)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Paired but disconnected
                GroupBox("Paired Devices (Disconnected)") {
                    if metrics.bluetoothSnapshot.pairedDisconnectedDevices.isEmpty {
                        Text("No paired devices")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(metrics.bluetoothSnapshot.pairedDisconnectedDevices) { device in
                                BluetoothDeviceRow(device: device)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Bluetooth")
    }
}

// MARK: - Bluetooth Device Card

/// Detailed card for a connected Bluetooth device showing battery, RSSI, and AirPods detail
struct BluetoothDeviceCard: View {
    let device: BluetoothDevice

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Device header
            HStack {
                Image(systemName: device.deviceType.symbolName)
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.headline)
                    Text(device.deviceType.rawValue.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Connection indicator
                HStack(spacing: 4) {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                    Text("Connected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Battery information
            if let airPods = device.airPodsDetail {
                AirPodsBatteryView(detail: airPods)
            } else if let battery = device.batteryLevel {
                HStack {
                    Label("Battery", systemImage: batterySymbol(for: battery))
                    Spacer()
                    BatteryBar(level: battery)
                    Text("\(battery)%")
                        .font(.caption.monospacedDigit())
                }
                .font(.caption)
            }

            // RSSI
            if let rssi = device.rssi {
                HStack {
                    Label("Signal", systemImage: rssiSymbol(for: rssi))
                    Spacer()
                    Text("\(rssi) dBm")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(rssiColor(for: rssi))
                }
                .font(.caption)
            }

            // MAC address
            HStack {
                Label("Address", systemImage: "number")
                Spacer()
                Text(device.address)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(device.name), \(device.deviceType.rawValue), connected")
    }

    private func batterySymbol(for level: Int) -> String {
        switch level {
        case 76...100: "battery.100"
        case 51...75: "battery.75"
        case 26...50: "battery.50"
        case 1...25: "battery.25"
        default: "battery.0"
        }
    }

    private func rssiSymbol(for rssi: Int) -> String {
        switch rssi {
        case -50...0: "wifi"
        case -70 ..< -50: "wifi"
        case -90 ..< -70: "wifi"
        default: "wifi.slash"
        }
    }

    private func rssiColor(for rssi: Int) -> Color {
        switch rssi {
        case -50...0: .green
        case -70 ..< -50: .yellow
        case -90 ..< -70: .orange
        default: .red
        }
    }
}

// MARK: - AirPods Battery View

/// Battery display for AirPods showing left, right, and case levels
struct AirPodsBatteryView: View {
    let detail: AirPodsDetail

    var body: some View {
        HStack(spacing: 16) {
            if let left = detail.leftBattery {
                airPodComponent(label: "Left", level: left, symbol: "ear")
            }
            if let right = detail.rightBattery {
                airPodComponent(label: "Right", level: right, symbol: "ear")
            }
            if let caseBatt = detail.caseBattery {
                airPodComponent(label: "Case", level: caseBatt, symbol: "case")
            }

            if detail.leftBattery == nil && detail.rightBattery == nil && detail.caseBattery == nil {
                Text("Battery data unavailable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func airPodComponent(label: String, level: Int, symbol: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            BatteryBar(level: level)
            Text("\(level)%")
                .font(.caption2.monospacedDigit())
        }
        .frame(minWidth: 50)
    }
}

// MARK: - Battery Bar

/// Small horizontal battery indicator bar
struct BatteryBar: View {
    let level: Int

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.2))
                RoundedRectangle(cornerRadius: 2)
                    .fill(batteryColor)
                    .frame(width: geo.size.width * CGFloat(min(max(level, 0), 100)) / 100)
            }
        }
        .frame(width: 50, height: 8)
        .accessibilityLabel("Battery \(level) percent")
    }

    private var batteryColor: Color {
        switch level {
        case 51...100: .green
        case 21...50: .yellow
        default: .red
        }
    }
}

// MARK: - Bluetooth Device Row

/// Compact row for paired but disconnected devices
struct BluetoothDeviceRow: View {
    let device: BluetoothDevice

    var body: some View {
        HStack {
            Image(systemName: device.deviceType.symbolName)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            Text(device.name)
                .font(.body)
            Spacer()
            Text(device.deviceType.rawValue.capitalized)
                .font(.caption)
                .foregroundStyle(.secondary)
            Circle()
                .fill(.secondary.opacity(0.3))
                .frame(width: 8, height: 8)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(device.name), \(device.deviceType.rawValue), disconnected")
    }
}
