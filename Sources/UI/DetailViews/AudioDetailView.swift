import SwiftUI

/// Detailed Audio view showing devices, volume, sample rate, and privacy indicators
struct AudioDetailView: View {
    @EnvironmentObject var metrics: MetricsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Privacy indicators (mic/camera)
                if metrics.audioSnapshot.micInUse || metrics.audioSnapshot.cameraInUse {
                    privacyIndicatorsSection
                }

                // Output device
                GroupBox("Output") {
                    if let output = metrics.audioSnapshot.defaultOutput {
                        AudioDeviceDetailCard(device: output, isDefault: true)

                        Divider()

                        // Volume display
                        HStack {
                            Image(systemName: metrics.audioSnapshot.isMuted
                                  ? "speaker.slash.fill"
                                  : volumeSymbol(for: metrics.audioSnapshot.volume))
                                .foregroundStyle(metrics.audioSnapshot.isMuted ? .red : .blue)
                                .frame(width: 24)
                            ProgressView(value: metrics.audioSnapshot.isMuted
                                         ? 0 : Double(metrics.audioSnapshot.volume))
                                .tint(metrics.audioSnapshot.isMuted ? .secondary : .blue)
                            Text(metrics.audioSnapshot.isMuted
                                 ? "Muted"
                                 : "\(Int(metrics.audioSnapshot.volume * 100))%")
                                .font(.caption.monospacedDigit())
                                .frame(width: 48, alignment: .trailing)
                        }
                        .padding(.vertical, 4)
                    } else {
                        Text("No output device detected")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    }
                }

                // Input device
                GroupBox("Input") {
                    if let input = metrics.audioSnapshot.defaultInput {
                        AudioDeviceDetailCard(device: input, isDefault: true)
                    } else {
                        Text("No input device detected")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    }
                }

                // All devices
                GroupBox("All Audio Devices") {
                    if metrics.audioSnapshot.allDevices.isEmpty {
                        Text("No audio devices detected")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(metrics.audioSnapshot.allDevices) { device in
                                AudioDeviceRow(
                                    device: device,
                                    isDefaultInput: device.uid == metrics.audioSnapshot.defaultInput?.uid,
                                    isDefaultOutput: device.uid == metrics.audioSnapshot.defaultOutput?.uid
                                )
                                if device.id != metrics.audioSnapshot.allDevices.last?.id {
                                    Divider()
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Audio")
    }

    // MARK: - Privacy Indicators Section

    private var privacyIndicatorsSection: some View {
        GroupBox("Privacy Indicators") {
            VStack(alignment: .leading, spacing: 8) {
                if metrics.audioSnapshot.micInUse {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(.orange)
                            .frame(width: 10, height: 10)
                        Image(systemName: "mic.fill")
                            .foregroundStyle(.orange)
                        Text("Microphone in use")
                            .font(.body)
                        Spacer()
                        if !metrics.audioSnapshot.micInUseBy.isEmpty {
                            Text("Used by: \(metrics.audioSnapshot.micInUseBy.joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.vertical, 2)
                }

                if metrics.audioSnapshot.cameraInUse {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(.green)
                            .frame(width: 10, height: 10)
                        Image(systemName: "camera.fill")
                            .foregroundStyle(.green)
                        Text("Camera in use")
                            .font(.body)
                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Helpers

    private func volumeSymbol(for volume: Float) -> String {
        switch volume {
        case 0.67...1.0: "speaker.wave.3.fill"
        case 0.34..<0.67: "speaker.wave.2.fill"
        case 0.01..<0.34: "speaker.wave.1.fill"
        default: "speaker.fill"
        }
    }
}

// MARK: - Audio Device Detail Card

/// Card showing detailed properties of a default audio device
struct AudioDeviceDetailCard: View {
    let device: AudioDevice
    let isDefault: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: device.isOutput ? "speaker.wave.2" : "mic")
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(device.name)
                            .font(.headline)
                        if isDefault {
                            Text("Default")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.blue.opacity(0.15), in: Capsule())
                                .foregroundStyle(.blue)
                        }
                    }
                    Text(deviceCapabilities)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Divider()

            // Technical properties
            HStack {
                Label("Sample Rate", systemImage: "waveform")
                Spacer()
                Text(formattedSampleRate)
                    .font(.caption.monospacedDigit())
            }
            .font(.caption)

            HStack {
                Label("Buffer Size", systemImage: "square.grid.3x3")
                Spacer()
                Text("\(device.bufferSize) frames")
                    .font(.caption.monospacedDigit())
            }
            .font(.caption)

            if device.bitDepth > 0 {
                HStack {
                    Label("Bit Depth", systemImage: "number")
                    Spacer()
                    Text("\(device.bitDepth)-bit")
                        .font(.caption.monospacedDigit())
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(device.name), \(deviceCapabilities)")
    }

    private var deviceCapabilities: String {
        switch (device.isInput, device.isOutput) {
        case (true, true): "Input & Output"
        case (true, false): "Input"
        case (false, true): "Output"
        case (false, false): "Unknown"
        }
    }

    private var formattedSampleRate: String {
        if device.sampleRate >= 1000 {
            return String(format: "%.1f kHz", device.sampleRate / 1000)
        }
        return String(format: "%.0f Hz", device.sampleRate)
    }
}

// MARK: - Audio Device Row

/// Compact row for the all-devices list
struct AudioDeviceRow: View {
    let device: AudioDevice
    let isDefaultInput: Bool
    let isDefaultOutput: Bool

    var body: some View {
        HStack {
            Image(systemName: deviceSymbol)
                .foregroundStyle(isDefault ? .blue : .secondary)
                .frame(width: 24)

            Text(device.name)
                .font(.body)

            if isDefaultInput {
                Text("Default Input")
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.orange.opacity(0.15), in: Capsule())
                    .foregroundStyle(.orange)
            }

            if isDefaultOutput {
                Text("Default Output")
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.blue.opacity(0.15), in: Capsule())
                    .foregroundStyle(.blue)
            }

            Spacer()

            Text(formattedSampleRate)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(device.name), \(isDefault ? "default" : "") \(capabilities)")
    }

    private var isDefault: Bool { isDefaultInput || isDefaultOutput }

    private var deviceSymbol: String {
        switch (device.isInput, device.isOutput) {
        case (true, true): "speaker.wave.2.bubble"
        case (true, false): "mic"
        case (false, true): "speaker.wave.2"
        default: "questionmark.circle"
        }
    }

    private var capabilities: String {
        switch (device.isInput, device.isOutput) {
        case (true, true): "Input and Output"
        case (true, false): "Input"
        case (false, true): "Output"
        default: "Unknown"
        }
    }

    private var formattedSampleRate: String {
        if device.sampleRate >= 1000 {
            return String(format: "%.1f kHz", device.sampleRate / 1000)
        }
        return String(format: "%.0f Hz", device.sampleRate)
    }
}
