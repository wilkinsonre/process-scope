import SwiftUI

/// Comprehensive network intelligence view with tabbed sub-panels for
/// interfaces, SSH sessions, VPN/Tailscale, WiFi, listening ports, and speed test.
struct NetworkDetailView: View {
    @EnvironmentObject var metrics: MetricsViewModel

    @State private var selectedTab: NetworkTab = .interfaces
    @State private var showSSH = true
    @State private var showTailscale = true
    @State private var showWiFi = true
    @State private var showListeningPorts = true
    @State private var showSpeedTest = true

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            NetworkTabBar(selectedTab: $selectedTab)
                .padding(.horizontal)
                .padding(.top, 8)

            Divider()
                .padding(.top, 4)

            // Tab content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch selectedTab {
                    case .interfaces:
                        InterfacesSection()
                    case .ssh:
                        SSHSessionsSection(sessions: metrics.sshSessions)
                    case .tailscale:
                        TailscaleSection(status: metrics.tailscaleStatus)
                    case .wifi:
                        WiFiSection(snapshot: metrics.wifiSnapshot)
                    case .listeningPorts:
                        ListeningPortsSection(ports: metrics.listeningPorts)
                    case .speedTest:
                        SpeedTestSection()
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Network")
    }
}

// MARK: - Network Tab

enum NetworkTab: String, CaseIterable, Identifiable {
    case interfaces = "Interfaces"
    case ssh = "SSH Sessions"
    case tailscale = "VPN / Tailscale"
    case wifi = "WiFi"
    case listeningPorts = "Listening Ports"
    case speedTest = "Speed Test"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .interfaces: return "network"
        case .ssh: return "terminal"
        case .tailscale: return "shield.lefthalf.filled"
        case .wifi: return "wifi"
        case .listeningPorts: return "door.left.hand.open"
        case .speedTest: return "speedometer"
        }
    }
}

// MARK: - Tab Bar

struct NetworkTabBar: View {
    @Binding var selectedTab: NetworkTab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(NetworkTab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: tab.symbol)
                            .font(.caption)
                        Text(tab.rawValue)
                            .font(.caption)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        selectedTab == tab
                            ? Color.accentColor.opacity(0.15)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                    .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Interfaces Section

struct InterfacesSection: View {
    @EnvironmentObject var metrics: MetricsViewModel

    var body: some View {
        GroupBox {
            if metrics.networkConnections.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "network.slash")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No active connections detected")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Text("Local")
                            .frame(width: 180, alignment: .leading)
                        Text("Remote")
                            .frame(width: 180, alignment: .leading)
                        Text("Protocol")
                            .frame(width: 60, alignment: .leading)
                        Text("State")
                            .frame(width: 100, alignment: .leading)
                        Spacer()
                    }
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)

                    Divider()

                    ForEach(metrics.networkConnections) { conn in
                        HStack {
                            Text("\(conn.localAddress):\(conn.localPort)")
                                .frame(width: 180, alignment: .leading)
                            Text("\(conn.remoteAddress):\(conn.remotePort)")
                                .frame(width: 180, alignment: .leading)
                            Text(conn.protocolType)
                                .frame(width: 60, alignment: .leading)
                            Text(conn.state)
                                .frame(width: 100, alignment: .leading)
                            Spacer()
                        }
                        .font(.caption.monospaced())
                        .padding(.vertical, 3)
                    }
                }
            }
        } label: {
            Label("Active Connections", systemImage: "arrow.left.arrow.right")
        }
    }
}

// MARK: - SSH Sessions Section

struct SSHSessionsSection: View {
    let sessions: [SSHSession]

    var body: some View {
        GroupBox {
            if sessions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "terminal")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No active SSH sessions")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                VStack(spacing: 8) {
                    ForEach(sessions) { session in
                        SSHSessionRow(session: session)
                    }
                }
            }
        } label: {
            Label("SSH Sessions (\(sessions.count))", systemImage: "terminal")
        }
    }
}

struct SSHSessionRow: View {
    let session: SSHSession

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "terminal.fill")
                .foregroundStyle(.green)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.connectionString)
                    .font(.body.monospaced())
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    Text("PID \(session.pid)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let startTime = session.startTime {
                        Text("connected \(startTime, style: .relative) ago")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let identity = session.identityFile {
                        Label(URL(fileURLWithPath: identity).lastPathComponent, systemImage: "key")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if !session.tunnels.isEmpty {
                VStack(alignment: .trailing, spacing: 2) {
                    ForEach(session.tunnels.indices, id: \.self) { i in
                        Text(session.tunnels[i].displayString)
                            .font(.caption.monospaced())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Tailscale Section

struct TailscaleSection: View {
    let status: TailscaleStatus?

    var body: some View {
        GroupBox {
            if let status {
                VStack(alignment: .leading, spacing: 12) {
                    // Self node info
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundStyle(.green)
                            .font(.title2)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(status.selfNode.hostName)
                                .font(.headline)
                            HStack(spacing: 6) {
                                ForEach(status.selfNode.tailscaleIPs, id: \.self) { ip in
                                    Text(ip)
                                        .font(.caption.monospaced())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                                }
                            }
                        }

                        Spacer()

                        if let tailnet = status.currentTailnet {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(tailnet.name)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Text(tailnet.magicDNSSuffix)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Divider()

                    // Peers
                    let peers = status.sortedPeers
                    if peers.isEmpty {
                        Text("No peers found")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 0) {
                            // Header
                            HStack {
                                Text("Hostname")
                                    .frame(width: 160, alignment: .leading)
                                Text("IP")
                                    .frame(width: 140, alignment: .leading)
                                Text("OS")
                                    .frame(width: 80, alignment: .leading)
                                Text("Connection")
                                    .frame(width: 100, alignment: .leading)
                                Spacer()
                            }
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 4)

                            ForEach(peers) { peer in
                                TailscalePeerRow(peer: peer)
                            }
                        }
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "shield.slash")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Tailscale not running")
                        .foregroundStyle(.secondary)
                    Text("Install Tailscale or start the daemon to see VPN status")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
        } label: {
            Label("Tailscale VPN", systemImage: "shield.lefthalf.filled")
        }
    }
}

struct TailscalePeerRow: View {
    let peer: TailscalePeer

    var body: some View {
        HStack {
            // Online indicator
            Circle()
                .fill(peer.online ? .green : .secondary.opacity(0.3))
                .frame(width: 6, height: 6)

            Text(peer.hostName)
                .frame(width: 152, alignment: .leading)
                .lineLimit(1)

            Text(peer.tailscaleIPs.first ?? "")
                .font(.caption.monospaced())
                .frame(width: 140, alignment: .leading)

            HStack(spacing: 4) {
                Image(systemName: peer.osIcon)
                    .font(.caption2)
                Text(peer.os)
                    .font(.caption)
            }
            .frame(width: 80, alignment: .leading)

            if peer.online {
                if peer.isDirect {
                    Label("Direct", systemImage: "arrow.left.arrow.right")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .frame(width: 100, alignment: .leading)
                } else if let relay = peer.relay {
                    Label(relay, systemImage: "antenna.radiowaves.left.and.right")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .frame(width: 100, alignment: .leading)
                }
            } else {
                if let lastSeen = peer.lastSeen {
                    Text(lastSeen, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 100, alignment: .leading)
                }
            }

            Spacer()

            if peer.exitNode {
                Text("Exit Node")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.purple.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .font(.caption)
        .padding(.vertical, 3)
    }
}

// MARK: - WiFi Section

struct WiFiSection: View {
    let snapshot: WiFiSnapshot?

    var body: some View {
        GroupBox {
            if let snapshot {
                VStack(alignment: .leading, spacing: 16) {
                    // WiFi card
                    HStack(spacing: 16) {
                        WiFiSignalBars(bars: snapshot.signalBars)
                            .frame(width: 32, height: 32)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(snapshot.ssid ?? "Unknown Network")
                                .font(.headline)
                            Text(snapshot.band)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Signal Quality: \(snapshot.signalQuality)%")
                                .font(.caption)
                            Text("Channel \(snapshot.channel ?? 0)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    // Details grid
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                    ], spacing: 12) {
                        WiFiMetricCell(label: "RSSI", value: "\(snapshot.rssi) dBm")
                        WiFiMetricCell(label: "Noise", value: "\(snapshot.noiseMeasurement) dBm")
                        WiFiMetricCell(label: "SNR", value: "\(snapshot.snr) dB")
                        WiFiMetricCell(label: "Tx Rate", value: String(format: "%.0f Mbps", snapshot.txRate))
                        WiFiMetricCell(label: "Security", value: snapshot.security)
                        WiFiMetricCell(label: "BSSID", value: snapshot.bssid ?? "N/A")
                        WiFiMetricCell(label: "Country", value: snapshot.countryCode ?? "N/A")
                        WiFiMetricCell(label: "Interface", value: snapshot.interfaceName)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "wifi.slash")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("WiFi not connected")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
        } label: {
            Label("WiFi", systemImage: "wifi")
        }
    }
}

struct WiFiSignalBars: View {
    let bars: Int

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i < bars ? Color.accentColor : Color.secondary.opacity(0.2))
                    .frame(width: 5, height: CGFloat(8 + i * 6))
            }
        }
    }
}

struct WiFiMetricCell: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospaced())
                .lineLimit(1)
        }
    }
}

// MARK: - Listening Ports Section

struct ListeningPortsSection: View {
    let ports: [ListeningPort]

    var body: some View {
        GroupBox {
            if ports.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "door.left.hand.closed")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No listening ports detected")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Text("Port")
                            .frame(width: 70, alignment: .leading)
                        Text("Protocol")
                            .frame(width: 60, alignment: .leading)
                        Text("Process")
                            .frame(width: 150, alignment: .leading)
                        Text("Address")
                            .frame(width: 120, alignment: .leading)
                        Text("Status")
                            .frame(width: 100, alignment: .leading)
                        Spacer()
                    }
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)

                    Divider()

                    ForEach(ports) { port in
                        ListeningPortRow(port: port)
                    }
                }
            }
        } label: {
            HStack {
                Label("Listening Ports (\(ports.count))", systemImage: "door.left.hand.open")
                Spacer()
                let exposedCount = ports.filter(\.isExposed).count
                if exposedCount > 0 {
                    Label("\(exposedCount) exposed", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}

struct ListeningPortRow: View {
    let port: ListeningPort

    var body: some View {
        HStack {
            Text("\(port.port)")
                .font(.caption.monospaced())
                .fontWeight(.medium)
                .frame(width: 70, alignment: .leading)

            Text(port.protocolName)
                .font(.caption)
                .frame(width: 60, alignment: .leading)

            HStack(spacing: 4) {
                Text(port.processName)
                    .lineLimit(1)
                if let service = port.serviceName {
                    Text("(\(service))")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .frame(width: 150, alignment: .leading)

            Text(port.address)
                .font(.caption.monospaced())
                .frame(width: 120, alignment: .leading)

            if port.isExposed {
                Label("Exposed", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(width: 100, alignment: .leading)
            } else {
                Label("Local", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .frame(width: 100, alignment: .leading)
            }

            Spacer()

            Text("PID \(port.pid)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Speed Test Section

struct SpeedTestSection: View {
    @EnvironmentObject var metrics: MetricsViewModel

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                // Result display
                if let result = metrics.speedTestResult {
                    HStack(spacing: 24) {
                        SpeedTestGauge(
                            label: "Download",
                            value: result.downloadMbps,
                            unit: "Mbps",
                            color: .blue,
                            symbol: "arrow.down.circle.fill"
                        )

                        SpeedTestGauge(
                            label: "Upload",
                            value: result.uploadMbps,
                            unit: "Mbps",
                            color: .green,
                            symbol: "arrow.up.circle.fill"
                        )

                        VStack(spacing: 8) {
                            Image(systemName: "gauge.with.dots.needle.33percent")
                                .font(.title2)
                                .foregroundStyle(.orange)
                            Text("\(result.rpm)")
                                .font(.title3.monospacedDigit())
                                .fontWeight(.semibold)
                            Text("RPM")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(result.responsivenessQuality)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                        }
                        .frame(maxWidth: .infinity)
                    }

                    Text("Last tested: \(result.timestamp, style: .relative) ago")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "speedometer")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No speed test results yet")
                            .foregroundStyle(.secondary)
                        Text("Uses Apple's built-in networkQuality tool")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }

                // Run button
                HStack {
                    Spacer()
                    Button {
                        Task {
                            await metrics.runSpeedTest()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if metrics.isRunningSpeedTest {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 14, height: 14)
                                Text("Testing...")
                            } else {
                                Image(systemName: "play.fill")
                                Text("Run Speed Test")
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(metrics.isRunningSpeedTest)
                    Spacer()
                }

                // Error display
                if case .failed(let message) = metrics.speedTestState {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
        } label: {
            Label("Speed Test", systemImage: "speedometer")
        }
    }
}

struct SpeedTestGauge: View {
    let label: String
    let value: Double
    let unit: String
    let color: Color
    let symbol: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(color)
            Text(String(format: "%.1f", value))
                .font(.title3.monospacedDigit())
                .fontWeight(.semibold)
            Text(unit)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
