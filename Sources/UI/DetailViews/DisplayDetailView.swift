import SwiftUI

/// Detailed display view showing connected displays with resolution, refresh rate,
/// HDR support, and color profile information.
struct DisplayDetailView: View {
    @EnvironmentObject var metrics: MetricsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Summary header
                displaySummarySection

                // Individual display sections
                if metrics.displaySnapshot.displays.isEmpty {
                    GroupBox("Displays") {
                        Text("No displays detected")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    }
                } else {
                    ForEach(metrics.displaySnapshot.displays) { display in
                        DisplayCardView(display: display)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Display")
    }

    // MARK: - Summary Section

    private var displaySummarySection: some View {
        GroupBox("Overview") {
            HStack(spacing: 16) {
                Image(systemName: displayCountSymbol)
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayCountText)
                        .font(.headline)
                    Text(displaySummaryDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.vertical, 4)
        }
    }

    private var displayCountSymbol: String {
        let count = metrics.displaySnapshot.displayCount
        switch count {
        case 0: return "display.trianglebadge.exclamationmark"
        case 1: return metrics.displaySnapshot.displays.first?.isBuiltIn == true ? "macbook" : "display"
        default: return "display.2"
        }
    }

    private var displayCountText: String {
        let count = metrics.displaySnapshot.displayCount
        switch count {
        case 0: return "No displays detected"
        case 1: return "1 Display Connected"
        default: return "\(count) Displays Connected"
        }
    }

    private var displaySummaryDetail: String {
        let displays = metrics.displaySnapshot.displays
        let builtIn = displays.filter(\.isBuiltIn).count
        let external = displays.filter { !$0.isBuiltIn }.count
        var parts: [String] = []
        if builtIn > 0 { parts.append("\(builtIn) built-in") }
        if external > 0 { parts.append("\(external) external") }
        let hdr = displays.filter(\.isHDR).count
        if hdr > 0 { parts.append("\(hdr) HDR") }
        return parts.joined(separator: " / ")
    }
}

// MARK: - Display Card

/// Card showing detailed properties of a single display
struct DisplayCardView: View {
    let display: DisplayInfo

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                // Display header
                HStack {
                    Image(systemName: display.isBuiltIn ? "macbook" : "display")
                        .font(.title2)
                        .foregroundStyle(.blue)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(display.name)
                                .font(.headline)

                            if display.isMain {
                                Text("Main")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.blue.opacity(0.15), in: Capsule())
                                    .foregroundStyle(.blue)
                            }

                            if display.isHDR {
                                Text("HDR")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.purple.opacity(0.15), in: Capsule())
                                    .foregroundStyle(.purple)
                            }
                        }

                        Text(display.isBuiltIn ? "Built-in Display" : "External Display")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }

                Divider()

                // Resolution
                HStack {
                    Label("Logical Resolution", systemImage: "rectangle.dashed")
                    Spacer()
                    Text(display.resolutionString)
                        .font(.caption.monospacedDigit())
                }
                .font(.caption)

                HStack {
                    Label("Pixel Resolution", systemImage: "rectangle")
                    Spacer()
                    Text(display.pixelResolutionString)
                        .font(.caption.monospacedDigit())
                }
                .font(.caption)

                // Scale factor
                HStack {
                    Label("Scale Factor", systemImage: "arrow.up.left.and.arrow.down.right")
                    Spacer()
                    Text(String(format: "%.0fx", display.scaleFactor))
                        .font(.caption.monospacedDigit())
                }
                .font(.caption)

                // Refresh rate
                HStack {
                    Label("Refresh Rate", systemImage: "bolt")
                    Spacer()
                    Text(display.refreshRateString)
                        .font(.caption.monospacedDigit())
                }
                .font(.caption)

                // Color profile
                if let colorProfile = display.colorProfileName {
                    HStack {
                        Label("Color Profile", systemImage: "paintpalette")
                        Spacer()
                        Text(colorProfile)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .font(.caption)
                }

                // HDR capabilities
                HStack {
                    Label("HDR Support", systemImage: "sun.max")
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: display.isHDR ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(display.isHDR ? .green : .secondary)
                        Text(display.isHDR ? "Supported" : "Not Supported")
                            .font(.caption)
                    }
                }
                .font(.caption)
            }
            .padding(.vertical, 4)
        } label: {
            Label(display.name, systemImage: display.isBuiltIn ? "macbook" : "display")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(display.name), \(display.resolutionString), \(display.refreshRateString)")
    }
}
