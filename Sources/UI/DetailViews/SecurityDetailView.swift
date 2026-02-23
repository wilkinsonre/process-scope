import SwiftUI

/// Detailed security view showing system security posture with
/// SIP, FileVault, Firewall, and Gatekeeper status indicators.
struct SecurityDetailView: View {
    @EnvironmentObject var metrics: MetricsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                overallRatingSection
                securityItemsSection
                accessServicesSection
            }
            .padding()
        }
        .navigationTitle("Security")
    }

    // MARK: - Overall Rating

    private var overallRatingSection: some View {
        GroupBox("Security Posture") {
            HStack(spacing: 16) {
                Image(systemName: ratingSymbol)
                    .font(.system(size: 32))
                    .foregroundStyle(ratingColor)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(metrics.securitySnapshot.overallRating.rawValue)
                        .font(.title2.bold())
                        .foregroundStyle(ratingColor)

                    Text(ratingDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.vertical, 8)
        }
    }

    private var ratingSymbol: String {
        switch metrics.securitySnapshot.overallRating {
        case .good: return "checkmark.shield.fill"
        case .partial: return "shield.lefthalf.filled"
        case .reviewNeeded: return "exclamationmark.shield.fill"
        }
    }

    private var ratingColor: Color {
        switch metrics.securitySnapshot.overallRating {
        case .good: return .green
        case .partial: return .yellow
        case .reviewNeeded: return .orange
        }
    }

    private var ratingDescription: String {
        switch metrics.securitySnapshot.overallRating {
        case .good:
            return "All key security features are enabled. Your system is well protected."
        case .partial:
            return "Some security features could not be verified. Review the items below."
        case .reviewNeeded:
            return "One or more security features are disabled. Consider enabling them."
        }
    }

    // MARK: - Security Items

    private var securityItemsSection: some View {
        GroupBox("System Protection") {
            VStack(spacing: 0) {
                SecurityItemRow(
                    name: "System Integrity Protection",
                    detail: "Protects system files and directories from modification",
                    status: metrics.securitySnapshot.sipStatus,
                    symbolName: "lock.shield"
                )

                Divider().padding(.leading, 36)

                SecurityItemRow(
                    name: "FileVault",
                    detail: "Full-disk encryption for the startup volume",
                    status: metrics.securitySnapshot.fileVaultStatus,
                    symbolName: "lock.doc"
                )

                Divider().padding(.leading, 36)

                SecurityItemRow(
                    name: "Application Firewall",
                    detail: "Controls incoming network connections per application",
                    status: metrics.securitySnapshot.firewallStatus,
                    symbolName: "flame"
                )

                Divider().padding(.leading, 36)

                SecurityItemRow(
                    name: "Gatekeeper",
                    detail: "Enforces app notarization and developer signing",
                    status: metrics.securitySnapshot.gatekeeperStatus,
                    symbolName: "checkmark.seal"
                )
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Access Services

    private var accessServicesSection: some View {
        GroupBox("Remote Access") {
            VStack(spacing: 0) {
                SecurityItemRow(
                    name: "Remote Login (SSH)",
                    detail: "Allows SSH connections to this Mac",
                    status: metrics.securitySnapshot.remoteLoginEnabled,
                    symbolName: "terminal",
                    invertedMeaning: true
                )

                Divider().padding(.leading, 36)

                SecurityItemRow(
                    name: "Screen Sharing",
                    detail: "Allows remote screen sharing via VNC",
                    status: metrics.securitySnapshot.screenSharingEnabled,
                    symbolName: "rectangle.on.rectangle",
                    invertedMeaning: true
                )
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Security Item Row

/// A single row showing the status of a security feature
struct SecurityItemRow: View {
    let name: String
    let detail: String
    let status: SecurityItemStatus
    let symbolName: String

    /// When true, "enabled" is shown in orange (a service being on is a potential exposure)
    var invertedMeaning: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbolName)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: statusSymbol)
                    .foregroundStyle(statusColor)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(statusText)")
    }

    private var statusSymbol: String {
        switch status {
        case .enabled:
            return invertedMeaning ? "exclamationmark.circle.fill" : "checkmark.circle.fill"
        case .disabled:
            return invertedMeaning ? "checkmark.circle.fill" : "xmark.circle.fill"
        case .unknown:
            return "questionmark.circle"
        }
    }

    private var statusColor: Color {
        switch status {
        case .enabled:
            return invertedMeaning ? .orange : .green
        case .disabled:
            return invertedMeaning ? .green : .red
        case .unknown:
            return .secondary
        }
    }

    private var iconColor: Color {
        switch status {
        case .enabled:
            return invertedMeaning ? .orange : .blue
        case .disabled:
            return invertedMeaning ? .secondary : .red
        case .unknown:
            return .secondary
        }
    }

    private var statusText: String {
        switch status {
        case .enabled: return "Enabled"
        case .disabled: return "Disabled"
        case .unknown: return "Unknown"
        }
    }
}
