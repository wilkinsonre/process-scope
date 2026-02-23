import Foundation
import os

// MARK: - Docker Container Model

/// Represents a Docker container with its current state and metadata
///
/// Decoded from the Docker Engine API `/containers/json` endpoint.
/// Contains the fields needed for display and lifecycle management.
public struct DockerContainer: Identifiable, Sendable, Equatable {
    /// Short container ID (first 12 characters)
    public let id: String

    /// Full container ID (64-character hex string)
    public let fullID: String

    /// Container name (without leading slash)
    public let name: String

    /// Image name the container was created from
    public let image: String

    /// Current container state
    public let state: DockerContainerState

    /// Human-readable status string from Docker (e.g., "Up 2 hours", "Exited (0) 5 minutes ago")
    public let status: String

    /// Port mappings for this container
    public let ports: [DockerPort]

    /// Unix timestamp when the container was created
    public let created: Date
}

// MARK: - Docker Container State

/// Possible states of a Docker container
public enum DockerContainerState: String, Sendable, Codable, Equatable {
    case running
    case paused
    case exited
    case created
    case restarting
    case removing
    case dead
    case unknown

    /// Initializes from a raw Docker API state string
    /// - Parameter rawState: The state string from the Docker Engine API
    public init(rawState: String) {
        self = DockerContainerState(rawValue: rawState.lowercased()) ?? .unknown
    }

    /// SF Symbol name for this state
    public var symbolName: String {
        switch self {
        case .running: "circle.fill"
        case .paused: "pause.circle.fill"
        case .exited: "stop.circle.fill"
        case .created: "circle.dashed"
        case .restarting: "arrow.clockwise.circle.fill"
        case .removing: "trash.circle.fill"
        case .dead: "xmark.circle.fill"
        case .unknown: "questionmark.circle"
        }
    }

    /// Display color for the state indicator
    public var colorName: String {
        switch self {
        case .running: "green"
        case .paused: "yellow"
        case .exited, .dead: "gray"
        case .created: "blue"
        case .restarting: "orange"
        case .removing: "red"
        case .unknown: "gray"
        }
    }

    /// Human-readable label
    public var displayName: String {
        rawValue.capitalized
    }
}

// MARK: - Docker Port

/// A port mapping for a Docker container
public struct DockerPort: Sendable, Equatable {
    /// Private (container) port
    public let privatePort: UInt16

    /// Public (host) port, if mapped
    public let publicPort: UInt16?

    /// Protocol type (tcp/udp)
    public let type: String

    /// Host IP the port is bound to
    public let ip: String?

    /// Formatted display string (e.g., "0.0.0.0:8080->80/tcp")
    public var displayString: String {
        if let publicPort, let ip {
            return "\(ip):\(publicPort)->\(privatePort)/\(type)"
        } else if let publicPort {
            return "\(publicPort)->\(privatePort)/\(type)"
        } else {
            return "\(privatePort)/\(type)"
        }
    }
}

// MARK: - Docker Error

/// Errors that can occur during Docker API communication
public enum DockerError: LocalizedError, Sendable {
    case socketNotFound
    case requestFailed(path: String, statusCode: Int, body: String)
    case invalidResponse
    case parseError(String)
    case processSpawnFailed(String)
    case notAvailable

    public var errorDescription: String? {
        switch self {
        case .socketNotFound:
            "No Docker socket found. Is Docker Desktop, Colima, or OrbStack running?"
        case .requestFailed(let path, let statusCode, let body):
            "Docker API request failed: \(path) (HTTP \(statusCode)): \(body)"
        case .invalidResponse:
            "Invalid response from Docker API"
        case .parseError(let detail):
            "Failed to parse Docker API response: \(detail)"
        case .processSpawnFailed(let reason):
            "Failed to communicate with Docker: \(reason)"
        case .notAvailable:
            "Docker is not available on this system"
        }
    }
}

// MARK: - Docker Service Protocol

/// Protocol for Docker container operations, enabling testability via mocks
public protocol DockerServiceProtocol: Sendable {
    /// Whether any Docker socket is available on the system
    var isDockerAvailable: Bool { get async }

    /// The path to the detected Docker socket, if any
    var socketPath: String? { get async }

    /// Lists all containers (running and stopped)
    /// - Returns: Array of Docker containers
    func listContainers() async throws -> [DockerContainer]

    /// Starts a stopped container
    /// - Parameter id: Container ID
    func startContainer(id: String) async throws

    /// Stops a running container
    /// - Parameter id: Container ID
    func stopContainer(id: String) async throws

    /// Restarts a container
    /// - Parameter id: Container ID
    func restartContainer(id: String) async throws

    /// Removes a container
    /// - Parameters:
    ///   - id: Container ID
    ///   - force: If true, forces removal even if the container is running
    func removeContainer(id: String, force: Bool) async throws

    /// Pauses a running container
    /// - Parameter id: Container ID
    func pauseContainer(id: String) async throws

    /// Unpauses a paused container
    /// - Parameter id: Container ID
    func unpauseContainer(id: String) async throws

    /// Retrieves recent log output from a container
    /// - Parameters:
    ///   - id: Container ID
    ///   - tail: Number of lines from the end to retrieve
    /// - Returns: Log output as a string
    func containerLogs(id: String, tail: Int) async throws -> String
}

// MARK: - Docker Service

/// Communicates with the Docker Engine API via Unix domain socket
///
/// Discovers Docker sockets in the following order:
/// 1. `/var/run/docker.sock` (Docker Desktop)
/// 2. `~/.colima/default/docker.sock` (Colima)
/// 3. `~/.orbstack/run/docker.sock` (OrbStack)
///
/// Communication is done via `curl --unix-socket` to avoid the complexity
/// of implementing Unix domain socket HTTP in pure Swift with URLSession.
/// The Docker Engine API version used is v1.43.
public actor DockerService: DockerServiceProtocol {
    private static let logger = Logger(subsystem: "com.processscope", category: "DockerService")

    /// Docker Engine API version
    private static let apiVersion = "v1.43"

    /// Ordered list of socket paths to check
    private static let socketSearchPaths: [String] = {
        let home = NSHomeDirectory()
        return [
            "/var/run/docker.sock",
            home + "/.colima/default/docker.sock",
            home + "/.orbstack/run/docker.sock",
        ]
    }()

    /// Cached detected socket path
    private var detectedSocketPath: String?
    private var hasSearched = false

    public init() {}

    /// Creates a service with a specific socket path (for testing or explicit configuration)
    /// - Parameter socketPath: Absolute path to the Docker socket
    public init(socketPath: String) {
        self.detectedSocketPath = socketPath
        self.hasSearched = true
    }

    // MARK: - Socket Discovery

    /// Whether any Docker socket is available on the system
    public var isDockerAvailable: Bool {
        get async {
            return await resolveSocketPath() != nil
        }
    }

    /// The path to the detected Docker socket, if any
    public var socketPath: String? {
        get async {
            return await resolveSocketPath()
        }
    }

    /// Resolves the Docker socket path, caching the result
    private func resolveSocketPath() -> String? {
        if hasSearched { return detectedSocketPath }

        hasSearched = true
        let fm = FileManager.default
        for path in Self.socketSearchPaths {
            if fm.fileExists(atPath: path) {
                Self.logger.info("Docker socket found at: \(path)")
                detectedSocketPath = path
                return path
            }
        }

        Self.logger.info("No Docker socket found")
        return nil
    }

    // MARK: - Container List

    /// Lists all containers (running and stopped)
    /// - Returns: Array of Docker containers sorted by name
    public func listContainers() async throws -> [DockerContainer] {
        let json = try await get("/containers/json?all=true")

        guard let containers = json as? [[String: Any]] else {
            throw DockerError.parseError("Expected array of container objects")
        }

        return containers.compactMap { Self.parseContainer($0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Container Lifecycle

    /// Starts a stopped container
    /// - Parameter id: Container ID
    public func startContainer(id: String) async throws {
        Self.logger.info("Starting container: \(id)")
        try await post("/containers/\(id)/start")
    }

    /// Stops a running container
    /// - Parameter id: Container ID
    public func stopContainer(id: String) async throws {
        Self.logger.info("Stopping container: \(id)")
        try await post("/containers/\(id)/stop")
    }

    /// Restarts a container
    /// - Parameter id: Container ID
    public func restartContainer(id: String) async throws {
        Self.logger.info("Restarting container: \(id)")
        try await post("/containers/\(id)/restart")
    }

    /// Removes a container
    /// - Parameters:
    ///   - id: Container ID
    ///   - force: If true, forces removal even if the container is running
    public func removeContainer(id: String, force: Bool) async throws {
        Self.logger.info("Removing container: \(id) (force: \(force))")
        try await delete("/containers/\(id)?force=\(force)")
    }

    /// Pauses a running container
    /// - Parameter id: Container ID
    public func pauseContainer(id: String) async throws {
        Self.logger.info("Pausing container: \(id)")
        try await post("/containers/\(id)/pause")
    }

    /// Unpauses a paused container
    /// - Parameter id: Container ID
    public func unpauseContainer(id: String) async throws {
        Self.logger.info("Unpausing container: \(id)")
        try await post("/containers/\(id)/unpause")
    }

    // MARK: - Container Logs

    /// Retrieves recent log output from a container
    /// - Parameters:
    ///   - id: Container ID
    ///   - tail: Number of lines from the end to retrieve
    /// - Returns: Log output as a string with Docker stream headers stripped
    public func containerLogs(id: String, tail: Int) async throws -> String {
        guard let socket = resolveSocketPath() else {
            throw DockerError.socketNotFound
        }

        let url = "http://localhost/\(Self.apiVersion)/containers/\(id)/logs?stdout=1&stderr=1&tail=\(tail)"
        let output = try await runCurl(socket: socket, method: "GET", url: url)
        return Self.stripDockerLogHeaders(output)
    }

    // MARK: - HTTP Methods

    private func get(_ path: String) async throws -> Any {
        guard let socket = resolveSocketPath() else {
            throw DockerError.socketNotFound
        }

        let url = "http://localhost/\(Self.apiVersion)\(path)"
        let output = try await runCurl(socket: socket, method: "GET", url: url)

        guard let data = output.data(using: .utf8) else {
            throw DockerError.invalidResponse
        }

        return try JSONSerialization.jsonObject(with: data)
    }

    private func post(_ path: String) async throws {
        guard let socket = resolveSocketPath() else {
            throw DockerError.socketNotFound
        }

        let url = "http://localhost/\(Self.apiVersion)\(path)"
        let output = try await runCurl(socket: socket, method: "POST", url: url, expectEmpty: true)

        // Docker returns empty body or error JSON for lifecycle commands
        if !output.isEmpty, let data = output.data(using: .utf8) {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = json["message"] as? String {
                // Some "errors" are benign (e.g., starting an already running container)
                if message.contains("is already") || message.contains("not running") {
                    Self.logger.info("Docker API note: \(message)")
                    return
                }
                throw DockerError.requestFailed(path: path, statusCode: 409, body: message)
            }
        }
    }

    private func delete(_ path: String) async throws {
        guard let socket = resolveSocketPath() else {
            throw DockerError.socketNotFound
        }

        let url = "http://localhost/\(Self.apiVersion)\(path)"
        let output = try await runCurl(socket: socket, method: "DELETE", url: url, expectEmpty: true)

        if !output.isEmpty, let data = output.data(using: .utf8) {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = json["message"] as? String {
                throw DockerError.requestFailed(path: path, statusCode: 409, body: message)
            }
        }
    }

    // MARK: - Process Execution

    /// Executes a curl command against the Docker Unix socket
    private func runCurl(
        socket: String,
        method: String,
        url: String,
        expectEmpty: Bool = false
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            process.arguments = [
                "--unix-socket", socket,
                "-s",           // silent
                "-X", method,
                url,
            ]

            let pipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = pipe
            process.standardError = errorPipe

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: DockerError.processSpawnFailed(error.localizedDescription))
                return
            }

            process.waitUntilExit()

            let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? ""

            if process.terminationStatus != 0 {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
                continuation.resume(throwing: DockerError.processSpawnFailed(
                    "curl exited with status \(process.terminationStatus): \(errorOutput)"
                ))
                return
            }

            continuation.resume(returning: output)
        }
    }

    // MARK: - Parsing

    /// Parses a single container JSON object into a DockerContainer
    static func parseContainer(_ json: [String: Any]) -> DockerContainer? {
        guard let fullID = json["Id"] as? String else { return nil }

        let shortID = String(fullID.prefix(12))

        // Names come as ["/name"] — strip the leading slash
        let names = json["Names"] as? [String] ?? []
        let name = names.first.map { $0.hasPrefix("/") ? String($0.dropFirst()) : $0 } ?? shortID

        let image = json["Image"] as? String ?? "unknown"
        let stateStr = json["State"] as? String ?? "unknown"
        let state = DockerContainerState(rawState: stateStr)
        let status = json["Status"] as? String ?? ""

        // Parse creation timestamp (Unix seconds)
        let createdTS = json["Created"] as? TimeInterval ?? 0
        let created = Date(timeIntervalSince1970: createdTS)

        // Parse ports
        let portsJSON = json["Ports"] as? [[String: Any]] ?? []
        let ports = portsJSON.compactMap { parsePort($0) }

        return DockerContainer(
            id: shortID,
            fullID: fullID,
            name: name,
            image: image,
            state: state,
            status: status,
            ports: ports,
            created: created
        )
    }

    /// Parses a single port mapping JSON object
    static func parsePort(_ json: [String: Any]) -> DockerPort? {
        guard let privatePort = json["PrivatePort"] as? Int else { return nil }

        let publicPort = json["PublicPort"] as? Int
        let type = json["Type"] as? String ?? "tcp"
        let ip = json["IP"] as? String

        return DockerPort(
            privatePort: UInt16(privatePort),
            publicPort: publicPort.map { UInt16($0) },
            type: type,
            ip: ip
        )
    }

    /// Strips Docker multiplexed stream headers from log output
    ///
    /// Docker log output uses an 8-byte header per frame when not using TTY.
    /// This function strips those headers and returns clean text.
    static func stripDockerLogHeaders(_ raw: String) -> String {
        // Docker log frames have an 8-byte binary header before each line
        // when multiplexed (non-tty). The header bytes are often non-printable
        // characters. We strip anything that looks like a header prefix.
        var cleaned = raw

        // Remove common binary header patterns (first byte is stream type, bytes 5-8 are length)
        // In practice, stripping non-printable characters at line starts works well.
        let lines = cleaned.components(separatedBy: "\n")
        cleaned = lines.map { line in
            // Strip leading non-printable characters (Docker stream headers)
            var startIndex = line.startIndex
            for char in line {
                if char.asciiValue ?? 0 >= 32 || char == "\t" {
                    break
                }
                startIndex = line.index(after: startIndex)
            }
            return String(line[startIndex...])
        }.joined(separator: "\n")

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
