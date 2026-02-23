import SwiftUI

/// Comprehensive storage detail view showing local volumes, network mounts,
/// and Time Machine backup status.
struct StorageDetailView: View {
    @EnvironmentObject var metrics: MetricsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                localVolumesSection
                networkVolumesSection
                timeMachineSection
            }
            .padding()
        }
        .navigationTitle("Storage")
    }

    // MARK: - Local Volumes Section

    @ViewBuilder
    private var localVolumesSection: some View {
        GroupBox {
            if metrics.storageVolumes.isEmpty {
                Text("No volumes detected")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 16) {
                    ForEach(metrics.storageVolumes) { volume in
                        VolumeCardView(volume: volume)
                        if volume.id != metrics.storageVolumes.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        } label: {
            Label("Local Volumes", systemImage: "internaldrive.fill")
        }
    }

    // MARK: - Network Volumes Section

    @ViewBuilder
    private var networkVolumesSection: some View {
        GroupBox {
            if metrics.networkVolumes.isEmpty {
                Text("No network volumes mounted")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 12) {
                    ForEach(metrics.networkVolumes) { volume in
                        NetworkVolumeRow(volume: volume)
                        if volume.id != metrics.networkVolumes.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        } label: {
            Label("Network Volumes", systemImage: "externaldrive.connected.to.line.below")
        }
    }

    // MARK: - Time Machine Section

    @ViewBuilder
    private var timeMachineSection: some View {
        GroupBox {
            timeMachineContent
                .padding(.vertical, 4)
        } label: {
            Label("Time Machine", systemImage: "clock.arrow.circlepath")
        }
    }

    @ViewBuilder
    private var timeMachineContent: some View {
        switch metrics.timeMachineState {
        case .backingUp(let percent):
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.blue)
                        .symbolEffect(.rotate)
                    Text("Backup in progress")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(Int(percent * 100))%")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: percent)
                    .tint(.blue)
            }

        case .idle(let lastBackup):
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Backups up to date")
                        .font(.subheadline.weight(.medium))
                    if let lastBackup {
                        Text("Last backup: \(lastBackup, style: .relative) ago")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

        case .unavailable:
            HStack {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(.secondary)
                Text("Time Machine not configured")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }
}

// MARK: - Volume Card View

/// Card display for a single local volume with usage bar, connection type badge,
/// and eject button for removable volumes.
struct VolumeCardView: View {
    let volume: VolumeSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header row: icon, name, badges
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: volume.interfaceType.symbolName)
                    .font(.title2)
                    .foregroundStyle(volume.isBootVolume ? .blue : .secondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(volume.name)
                            .font(.headline)

                        if volume.isBootVolume {
                            bootBadge
                        }
                    }

                    Text(volume.mountPoint)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                // Badges
                HStack(spacing: 6) {
                    interfaceBadge
                    fileSystemBadge

                    if volume.isEncrypted {
                        encryptionBadge
                    }

                    smartBadge
                }
            }

            // Usage bar
            VStack(alignment: .leading, spacing: 4) {
                SegmentedBar(segments: [
                    .init(
                        value: volume.usageFraction,
                        color: usageColor,
                        label: "Used: \(formattedBytes(volume.usedBytes))"
                    ),
                    .init(
                        value: 1.0 - volume.usageFraction,
                        color: .secondary.opacity(0.2),
                        label: "Free: \(formattedBytes(volume.freeBytes))"
                    ),
                ])
                .frame(height: 10)

                HStack {
                    Text("\(formattedBytes(volume.freeBytes)) available of \(formattedBytes(volume.totalBytes))")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    if volume.isEjectable {
                        Button {
                            ejectVolume()
                        } label: {
                            Label("Eject", systemImage: "eject.fill")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    // MARK: - Badges

    private var bootBadge: some View {
        Text("Boot")
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.blue.opacity(0.15), in: Capsule())
            .foregroundStyle(.blue)
    }

    private var interfaceBadge: some View {
        Text(volume.interfaceType.rawValue)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.secondary.opacity(0.12), in: Capsule())
            .foregroundStyle(.secondary)
    }

    private var fileSystemBadge: some View {
        Text(volume.fileSystemType.uppercased())
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.secondary.opacity(0.12), in: Capsule())
            .foregroundStyle(.secondary)
    }

    private var encryptionBadge: some View {
        Image(systemName: "lock.fill")
            .font(.caption2)
            .padding(3)
            .background(.green.opacity(0.15), in: Circle())
            .foregroundStyle(.green)
            .help("Encrypted")
    }

    private var smartBadge: some View {
        Group {
            switch volume.smartStatus {
            case .healthy:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .help("SMART: Healthy")
            case .failing:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .help("SMART: Failing - Back up immediately!")
            case .unknown:
                EmptyView()
            }
        }
        .font(.caption)
    }

    // MARK: - Helpers

    private var usageColor: Color {
        if volume.usageFraction > 0.9 { return .red }
        if volume.usageFraction > 0.75 { return .orange }
        return .blue
    }

    private func formattedBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func ejectVolume() {
        // Eject is handled through the action layer with confirmation dialog
        // For now, use NSWorkspace's unmount API
        let url = URL(fileURLWithPath: volume.mountPoint)
        Task {
            do {
                try await NSWorkspace.shared.unmountAndEjectDevice(at: url)
            } catch {
                // Error will be handled by the UI through action audit log
                _ = error
            }
        }
    }
}

// MARK: - Network Volume Row

/// Row display for a network-mounted volume showing server, protocol, and status.
struct NetworkVolumeRow: View {
    let volume: NetworkVolumeSnapshot

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: volume.protocolType.symbolName)
                .font(.title3)
                .foregroundStyle(volume.isConnected ? .blue : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(volume.displayName)
                        .font(.subheadline.weight(.medium))

                    protocolBadge
                }

                Text("\(volume.server)/\(volume.shareName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Capacity info (if available)
            if volume.totalBytes > 0 {
                Text("\(formattedBytes(volume.freeBytes)) free")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Connection indicator
            connectionIndicator

            // Latency
            if let latencyMs = volume.latencyMs {
                Text("\(Int(latencyMs)) ms")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var protocolBadge: some View {
        Text(volume.protocolType.rawValue)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.secondary.opacity(0.12), in: Capsule())
            .foregroundStyle(.secondary)
    }

    private var connectionIndicator: some View {
        Circle()
            .fill(volume.isConnected ? .green : .red)
            .frame(width: 8, height: 8)
            .help(volume.isConnected ? "Connected" : "Disconnected")
    }

    private func formattedBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
