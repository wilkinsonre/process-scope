import SwiftUI

/// Detailed developer view showing running IDEs, active builds, and Docker status.
struct DeveloperDetailView: View {
    @EnvironmentObject var metrics: MetricsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                runningIDEsSection
                activeBuildsSection
                dockerStatusSection
            }
            .padding()
        }
        .navigationTitle("Developer")
    }

    // MARK: - Running IDEs Section

    private var runningIDEsSection: some View {
        GroupBox {
            if metrics.developerSnapshot.runningIDEs.isEmpty {
                HStack {
                    Image(systemName: "app.dashed")
                        .foregroundStyle(.secondary)
                    Text("No IDEs or editors running")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(metrics.developerSnapshot.runningIDEs) { ide in
                        IDERow(ide: ide)
                        if ide.id != metrics.developerSnapshot.runningIDEs.last?.id {
                            Divider().padding(.leading, 36)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        } label: {
            Label("Running IDEs & Editors", systemImage: "chevron.left.forwardslash.chevron.right")
        }
    }

    // MARK: - Active Builds Section

    private var activeBuildsSection: some View {
        GroupBox {
            if metrics.developerSnapshot.activeBuilds.isEmpty {
                HStack {
                    Image(systemName: "hammer")
                        .foregroundStyle(.secondary)
                    Text("No active builds")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(metrics.developerSnapshot.activeBuilds) { build in
                        BuildRow(build: build)
                        if build.id != metrics.developerSnapshot.activeBuilds.last?.id {
                            Divider().padding(.leading, 36)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        } label: {
            HStack {
                Label("Active Builds", systemImage: "hammer.fill")
                if metrics.developerSnapshot.hasActiveBuilds {
                    Text("\(metrics.developerSnapshot.activeBuilds.count)")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.orange.opacity(0.15), in: Capsule())
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    // MARK: - Docker Status Section

    private var dockerStatusSection: some View {
        GroupBox {
            HStack(spacing: 12) {
                Image(systemName: metrics.developerSnapshot.dockerAvailable
                      ? "shippingbox.fill"
                      : "shippingbox.slash")
                    .font(.title2)
                    .foregroundStyle(metrics.developerSnapshot.dockerAvailable ? .blue : .secondary)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(metrics.developerSnapshot.dockerAvailable
                         ? "Docker Available"
                         : "Docker Not Available")
                        .font(.headline)

                    if metrics.developerSnapshot.dockerAvailable {
                        Text("Docker socket detected. Use the Docker module for container management.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No Docker socket found. Start Docker Desktop, Colima, or OrbStack.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if metrics.developerSnapshot.dockerAvailable {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                        Text("Active")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        } label: {
            Label("Docker", systemImage: "shippingbox")
        }
    }
}

// MARK: - IDE Row

/// A single row showing a running IDE or editor
struct IDERow: View {
    let ide: RunningIDE

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: ide.symbolName)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(ide.name)
                    .font(.body)
                Text(ide.bundleID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text("PID \(ide.pid)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(ide.name), process ID \(ide.pid)")
    }
}

// MARK: - Build Row

/// A single row showing an active build process
struct BuildRow: View {
    let build: ActiveBuild

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: build.symbolName)
                .font(.title3)
                .foregroundStyle(.orange)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(build.tool)
                    .font(.body)

                if let projectPath = build.projectPath {
                    Text(abbreviatePath(projectPath))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("PID \(build.pid)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                if let startTime = build.startTime {
                    Text(elapsedString(since: startTime))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(build.tool) build, process ID \(build.pid)")
    }

    /// Abbreviate a file path for display (show last 2 components)
    private func abbreviatePath(_ path: String) -> String {
        let components = path.split(separator: "/")
        if components.count <= 3 {
            return path
        }
        let last = components.suffix(2).joined(separator: "/")
        return ".../" + last
    }

    /// Human-readable elapsed time since a build started
    private func elapsedString(since date: Date) -> String {
        let elapsed = Date().timeIntervalSince(date)
        if elapsed < 60 {
            return "\(Int(elapsed))s"
        } else if elapsed < 3600 {
            let minutes = Int(elapsed) / 60
            let seconds = Int(elapsed) % 60
            return "\(minutes)m \(seconds)s"
        } else {
            let hours = Int(elapsed) / 3600
            let minutes = (Int(elapsed) % 3600) / 60
            return "\(hours)h \(minutes)m"
        }
    }
}
