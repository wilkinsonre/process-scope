import SwiftUI

struct NetworkDetailView: View {
    @EnvironmentObject var metrics: MetricsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox("Active Connections") {
                    if metrics.networkConnections.isEmpty {
                        Text("No active connections detected")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(metrics.networkConnections) { conn in
                            HStack {
                                Text("\(conn.localAddress):\(conn.localPort)")
                                    .font(.caption.monospaced())
                                Image(systemName: "arrow.right")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text("\(conn.remoteAddress):\(conn.remotePort)")
                                    .font(.caption.monospaced())
                                Spacer()
                                Text(conn.state)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Network")
    }
}
