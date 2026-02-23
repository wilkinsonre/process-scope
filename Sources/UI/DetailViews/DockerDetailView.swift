import SwiftUI
import os

// MARK: - Docker Detail View

/// Detail view showing Docker container status and lifecycle controls
///
/// Displays a list of all Docker containers (running and stopped) with
/// context menu actions for start, stop, restart, pause, unpause, and remove.
/// All actions are gated behind ``ActionConfiguration`` and confirmation
/// dialogs for destructive operations.
struct DockerDetailView: View {
    @EnvironmentObject var actionVM: ActionViewModel
    @StateObject private var viewModel = DockerDetailViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            dockerHeaderBar

            Divider()

            // Content
            if viewModel.isLoading && viewModel.containers.isEmpty {
                loadingView
            } else if !viewModel.isAvailable {
                dockerUnavailableView
            } else if viewModel.containers.isEmpty {
                emptyContainersView
            } else {
                containerListView
            }
        }
        .navigationTitle("Docker")
        .task {
            await viewModel.checkAvailabilityAndLoad()
        }
        .sheet(isPresented: $viewModel.showLogSheet) {
            if let container = viewModel.logContainer {
                DockerLogSheet(
                    containerName: container.name,
                    containerID: container.id,
                    viewModel: viewModel
                )
            }
        }
    }

    // MARK: - Header Bar

    private var dockerHeaderBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.title2)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Docker Containers")
                    .font(.headline)

                if viewModel.isAvailable {
                    let running = viewModel.containers.filter { $0.state == .running }.count
                    let total = viewModel.containers.count
                    Text("\(running) running / \(total) total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Docker not available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let socketPath = viewModel.socketPath {
                Text(socketPath)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Button {
                Task { await viewModel.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.isLoading)
            .help("Refresh container list")
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    // MARK: - Container List

    private var containerListView: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Table header
                containerTableHeader

                Divider()

                // Container rows
                ForEach(viewModel.containers, id: \.id) { container in
                    DockerContainerRow(
                        container: container,
                        actionVM: actionVM,
                        viewModel: viewModel
                    )
                    Divider()
                        .padding(.horizontal)
                }
            }
            .padding(.bottom)
        }
    }

    private var containerTableHeader: some View {
        HStack(spacing: 0) {
            Text("State")
                .frame(width: 28)
            Text("Name")
                .frame(width: 160, alignment: .leading)
            Text("Image")
                .frame(width: 200, alignment: .leading)
            Text("Status")
                .frame(width: 180, alignment: .leading)
            Text("Ports")
                .frame(minWidth: 120, alignment: .leading)
            Spacer()
        }
        .font(.caption.bold())
        .foregroundStyle(.secondary)
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    // MARK: - Empty States

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Connecting to Docker...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dockerUnavailableView: some View {
        VStack(spacing: 16) {
            Image(systemName: "shippingbox.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Docker Not Available")
                .font(.title2)

            Text("ProcessScope checks for Docker sockets at:")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("/var/run/docker.sock")
                    .font(.caption.monospaced())
                Text("~/.colima/default/docker.sock")
                    .font(.caption.monospaced())
                Text("~/.orbstack/run/docker.sock")
                    .font(.caption.monospaced())
            }
            .foregroundStyle(.tertiary)

            Text("Start Docker Desktop, Colima, or OrbStack to manage containers.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Retry") {
                Task { await viewModel.checkAvailabilityAndLoad() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var emptyContainersView: some View {
        VStack(spacing: 16) {
            Image(systemName: "shippingbox")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Containers")
                .font(.title2)

            Text("Docker is running but no containers exist.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Container Row

/// A single row in the container list showing name, image, state, and ports
struct DockerContainerRow: View {
    let container: DockerContainer
    let actionVM: ActionViewModel
    @ObservedObject var viewModel: DockerDetailViewModel

    var body: some View {
        HStack(spacing: 0) {
            // State indicator
            Image(systemName: container.state.symbolName)
                .foregroundStyle(stateColor)
                .font(.caption)
                .frame(width: 28)
                .help(container.state.displayName)

            // Name
            Text(container.name)
                .font(.body.monospaced())
                .fontWeight(.medium)
                .lineLimit(1)
                .frame(width: 160, alignment: .leading)

            // Image
            Text(container.image)
                .font(.caption.monospaced())
                .lineLimit(1)
                .foregroundStyle(.secondary)
                .frame(width: 200, alignment: .leading)

            // Status
            Text(container.status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 180, alignment: .leading)

            // Ports
            if container.ports.isEmpty {
                Text("-")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(minWidth: 120, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(container.ports.indices, id: \.self) { i in
                        Text(container.ports[i].displayString)
                            .font(.caption2.monospaced())
                    }
                }
                .frame(minWidth: 120, alignment: .leading)
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .contextMenu {
            containerContextMenu
        }
    }

    private var stateColor: Color {
        switch container.state {
        case .running: .green
        case .paused: .yellow
        case .exited, .dead: .gray
        case .created: .blue
        case .restarting: .orange
        case .removing: .red
        case .unknown: .gray
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var containerContextMenu: some View {
        let target = ActionTarget(
            name: container.name,
            containerID: container.id
        )

        switch container.state {
        case .running:
            Button {
                Task { await actionVM.requestAction(.dockerStop, target: target) }
            } label: {
                Label("Stop", systemImage: ActionType.dockerStop.symbolName)
            }

            Button {
                Task { await actionVM.requestAction(.dockerRestart, target: target) }
            } label: {
                Label("Restart", systemImage: ActionType.dockerRestart.symbolName)
            }

            Button {
                Task { await actionVM.requestAction(.dockerPause, target: target) }
            } label: {
                Label("Pause", systemImage: ActionType.dockerPause.symbolName)
            }

        case .paused:
            Button {
                Task { await actionVM.requestAction(.dockerUnpause, target: target) }
            } label: {
                Label("Unpause", systemImage: ActionType.dockerUnpause.symbolName)
            }

        case .exited, .created, .dead:
            Button {
                Task { await actionVM.requestAction(.dockerStart, target: target) }
            } label: {
                Label("Start", systemImage: ActionType.dockerStart.symbolName)
            }

        default:
            EmptyView()
        }

        Divider()

        Button {
            viewModel.showLogs(for: container)
        } label: {
            Label("View Logs", systemImage: "doc.text")
        }

        Button {
            ClipboardService.copy(container.fullID)
        } label: {
            Label("Copy Container ID", systemImage: "doc.on.doc")
        }

        Button {
            ClipboardService.copy(container.name)
        } label: {
            Label("Copy Container Name", systemImage: "doc.on.doc")
        }

        Divider()

        Button(role: .destructive) {
            Task { await actionVM.requestAction(.dockerRemove, target: target) }
        } label: {
            Label("Remove", systemImage: ActionType.dockerRemove.symbolName)
        }
    }
}

// MARK: - Docker Log Sheet

/// Sheet view showing recent log output from a container
struct DockerLogSheet: View {
    let containerName: String
    let containerID: String
    @ObservedObject var viewModel: DockerDetailViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "doc.text")
                Text("Logs: \(containerName)")
                    .font(.headline)
                Spacer()

                Button {
                    Task { await viewModel.refreshLogs() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.isLoadingLogs)

                Button("Done") {
                    viewModel.showLogSheet = false
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            // Log content
            if viewModel.isLoadingLogs {
                VStack {
                    Spacer()
                    ProgressView("Loading logs...")
                    Spacer()
                }
            } else if viewModel.logContent.isEmpty {
                VStack {
                    Spacer()
                    Text("No log output")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    Text(viewModel.logContent)
                        .font(.caption.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .textSelection(.enabled)
                }
            }

            // Footer with copy button
            if !viewModel.logContent.isEmpty {
                Divider()
                HStack {
                    Text("\(viewModel.logContent.components(separatedBy: "\n").count) lines")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        ClipboardService.copy(viewModel.logContent)
                    } label: {
                        Label("Copy All", systemImage: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .task {
            await viewModel.loadLogs(containerID: containerID)
        }
    }
}

// MARK: - Docker Detail View Model

/// View model managing Docker container data and log display
@MainActor
final class DockerDetailViewModel: ObservableObject {
    private static let logger = Logger(subsystem: "com.processscope", category: "DockerDetailViewModel")

    // MARK: - Published State

    @Published var containers: [DockerContainer] = []
    @Published var isAvailable = false
    @Published var isLoading = false
    @Published var socketPath: String?
    @Published var errorMessage: String?

    @Published var showLogSheet = false
    @Published var logContainer: DockerContainer?
    @Published var logContent: String = ""
    @Published var isLoadingLogs = false

    // MARK: - Dependencies

    private let dockerService: any DockerServiceProtocol

    init(dockerService: any DockerServiceProtocol = DockerService()) {
        self.dockerService = dockerService
    }

    // MARK: - Data Loading

    /// Checks Docker availability and loads containers if available
    func checkAvailabilityAndLoad() async {
        isLoading = true
        defer { isLoading = false }

        isAvailable = await dockerService.isDockerAvailable
        socketPath = await dockerService.socketPath

        if isAvailable {
            await loadContainers()
        }
    }

    /// Refreshes the container list
    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        // Re-check availability in case Docker was started/stopped
        isAvailable = await dockerService.isDockerAvailable
        socketPath = await dockerService.socketPath

        if isAvailable {
            await loadContainers()
        }
    }

    private func loadContainers() async {
        do {
            containers = try await dockerService.listContainers()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            Self.logger.error("Failed to load containers: \(error.localizedDescription)")
        }
    }

    // MARK: - Logs

    /// Shows the log sheet for a container
    func showLogs(for container: DockerContainer) {
        logContainer = container
        logContent = ""
        showLogSheet = true
    }

    /// Loads logs for the current log container
    func loadLogs(containerID: String) async {
        isLoadingLogs = true
        defer { isLoadingLogs = false }

        do {
            logContent = try await dockerService.containerLogs(id: containerID, tail: 100)
        } catch {
            logContent = "Error loading logs: \(error.localizedDescription)"
            Self.logger.error("Failed to load logs for \(containerID): \(error.localizedDescription)")
        }
    }

    /// Refreshes logs for the current log container
    func refreshLogs() async {
        guard let container = logContainer else { return }
        await loadLogs(containerID: container.id)
    }
}
