import SwiftUI
import os

/// First-launch onboarding sheet explaining the privileged helper daemon.
///
/// Presented once on first launch via `@AppStorage("hasShownOnboarding")`.
/// Users can install the helper immediately or skip and install later from
/// Settings > General.
struct HelperOnboardingView: View {
    @AppStorage("hasShownOnboarding") private var hasShownOnboarding = false
    @StateObject private var helperInstaller = HelperInstaller()
    @Environment(\.dismiss) private var dismiss

    @State private var installError: String?
    @State private var isInstalling = false

    private static let logger = Logger(
        subsystem: "com.processscope",
        category: "HelperOnboarding"
    )

    var body: some View {
        VStack(spacing: 24) {
            // MARK: - Header

            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(.system(size: 64))
                .foregroundStyle(.blue)
                .accessibilityHidden(true)
                .padding(.top, 8)

            Text("Welcome to ProcessScope")
                .font(.title.bold())

            Text("ProcessScope can optionally install a helper daemon for advanced features like force-quitting processes, ejecting volumes, and system actions.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal)

            // MARK: - Benefits

            VStack(alignment: .leading, spacing: 12) {
                benefitRow(
                    symbol: "bolt.circle.fill",
                    title: "Advanced Process Control",
                    description: "Force-kill, suspend, and adjust priority of any process"
                )
                benefitRow(
                    symbol: "externaldrive.fill",
                    title: "Volume Management",
                    description: "Safely eject and force-unmount external drives"
                )
                benefitRow(
                    symbol: "lock.shield.fill",
                    title: "System-Level Actions",
                    description: "Flush DNS cache, purge memory, and more"
                )
            }
            .padding(.horizontal, 24)

            // MARK: - Error Display

            if let installError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(installError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
            }

            // MARK: - Action Buttons

            VStack(spacing: 10) {
                Button(action: installHelper) {
                    if isInstalling {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Install Helper")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                .disabled(isInstalling)
                .accessibilityLabel("Install privileged helper daemon")

                Button("Skip for Now") {
                    hasShownOnboarding = true
                    dismiss()
                }
                .controlSize(.large)
                .buttonStyle(.borderless)
                .accessibilityLabel("Skip helper installation for now")
            }
            .padding(.horizontal, 24)

            // MARK: - Footer Note

            Text("You can always install it later from Settings \u{2192} General.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 8)
        }
        .padding(24)
        .frame(width: 440)
    }

    // MARK: - Benefit Row

    private func benefitRow(symbol: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 28, alignment: .center)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Install Action

    private func installHelper() {
        isInstalling = true
        installError = nil

        do {
            try helperInstaller.install()
            Self.logger.info("Helper installed from onboarding")
            hasShownOnboarding = true
            dismiss()
        } catch {
            Self.logger.error("Helper install failed from onboarding: \(error.localizedDescription)")
            installError = error.localizedDescription
        }

        isInstalling = false
    }
}
