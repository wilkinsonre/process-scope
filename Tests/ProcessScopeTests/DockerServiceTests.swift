import XCTest
@testable import ProcessScope

// MARK: - Mock Docker Service

/// Mock implementation of DockerServiceProtocol for testing
final class MockDockerService: DockerServiceProtocol, @unchecked Sendable {
    // Configurable state
    var mockAvailable: Bool = true
    var mockSocketPath: String? = "/var/run/docker.sock"
    var mockContainers: [DockerContainer] = []
    var mockLogs: String = "2024-01-01 test log line 1\n2024-01-01 test log line 2"
    var mockError: Error?

    // Call tracking
    var startedContainerIDs: [String] = []
    var stoppedContainerIDs: [String] = []
    var restartedContainerIDs: [String] = []
    var removedContainerIDs: [(id: String, force: Bool)] = []
    var pausedContainerIDs: [String] = []
    var unpausedContainerIDs: [String] = []
    var logRequestedContainerIDs: [(id: String, tail: Int)] = []
    var listContainersCalled = false

    var isDockerAvailable: Bool {
        get async { mockAvailable }
    }

    var socketPath: String? {
        get async { mockSocketPath }
    }

    func listContainers() async throws -> [DockerContainer] {
        listContainersCalled = true
        if let error = mockError { throw error }
        return mockContainers
    }

    func startContainer(id: String) async throws {
        if let error = mockError { throw error }
        startedContainerIDs.append(id)
    }

    func stopContainer(id: String) async throws {
        if let error = mockError { throw error }
        stoppedContainerIDs.append(id)
    }

    func restartContainer(id: String) async throws {
        if let error = mockError { throw error }
        restartedContainerIDs.append(id)
    }

    func removeContainer(id: String, force: Bool) async throws {
        if let error = mockError { throw error }
        removedContainerIDs.append((id: id, force: force))
    }

    func pauseContainer(id: String) async throws {
        if let error = mockError { throw error }
        pausedContainerIDs.append(id)
    }

    func unpauseContainer(id: String) async throws {
        if let error = mockError { throw error }
        unpausedContainerIDs.append(id)
    }

    func containerLogs(id: String, tail: Int) async throws -> String {
        if let error = mockError { throw error }
        logRequestedContainerIDs.append((id: id, tail: tail))
        return mockLogs
    }
}

// MARK: - Test Helpers

extension DockerContainer {
    /// Creates a test container with sensible defaults
    static func makeTest(
        id: String = "abc123def456",
        fullID: String = "abc123def456789012345678901234567890123456789012345678901234",
        name: String = "test-container",
        image: String = "nginx:latest",
        state: DockerContainerState = .running,
        status: String = "Up 2 hours",
        ports: [DockerPort] = [],
        created: Date = Date(timeIntervalSince1970: 1700000000)
    ) -> DockerContainer {
        DockerContainer(
            id: id,
            fullID: fullID,
            name: name,
            image: image,
            state: state,
            status: status,
            ports: ports,
            created: created
        )
    }
}

// MARK: - Docker Container State Tests

final class DockerContainerStateTests: XCTestCase {

    func testStateFromRawString() {
        XCTAssertEqual(DockerContainerState(rawState: "running"), .running)
        XCTAssertEqual(DockerContainerState(rawState: "paused"), .paused)
        XCTAssertEqual(DockerContainerState(rawState: "exited"), .exited)
        XCTAssertEqual(DockerContainerState(rawState: "created"), .created)
        XCTAssertEqual(DockerContainerState(rawState: "restarting"), .restarting)
        XCTAssertEqual(DockerContainerState(rawState: "removing"), .removing)
        XCTAssertEqual(DockerContainerState(rawState: "dead"), .dead)
    }

    func testStateCaseInsensitive() {
        XCTAssertEqual(DockerContainerState(rawState: "Running"), .running)
        XCTAssertEqual(DockerContainerState(rawState: "PAUSED"), .paused)
        XCTAssertEqual(DockerContainerState(rawState: "Exited"), .exited)
    }

    func testUnknownState() {
        XCTAssertEqual(DockerContainerState(rawState: "bogus"), .unknown)
        XCTAssertEqual(DockerContainerState(rawState: ""), .unknown)
    }

    func testStateSymbolNames() {
        for state in [DockerContainerState.running, .paused, .exited, .created,
                      .restarting, .removing, .dead, .unknown] {
            XCTAssertFalse(state.symbolName.isEmpty,
                           "\(state) should have a non-empty symbol name")
        }
    }

    func testStateColorNames() {
        for state in [DockerContainerState.running, .paused, .exited, .created,
                      .restarting, .removing, .dead, .unknown] {
            XCTAssertFalse(state.colorName.isEmpty,
                           "\(state) should have a non-empty color name")
        }
    }

    func testStateDisplayNames() {
        XCTAssertEqual(DockerContainerState.running.displayName, "Running")
        XCTAssertEqual(DockerContainerState.paused.displayName, "Paused")
        XCTAssertEqual(DockerContainerState.exited.displayName, "Exited")
    }
}

// MARK: - Docker Container Parsing Tests

final class DockerContainerParsingTests: XCTestCase {

    func testParseContainerJSON() {
        let json: [String: Any] = [
            "Id": "abc123def456789012345678901234567890123456789012345678901234",
            "Names": ["/my-web-app"],
            "Image": "nginx:latest",
            "State": "running",
            "Status": "Up 3 hours",
            "Created": 1700000000.0,
            "Ports": [
                [
                    "IP": "0.0.0.0",
                    "PrivatePort": 80,
                    "PublicPort": 8080,
                    "Type": "tcp",
                ] as [String: Any],
            ] as [[String: Any]],
        ]

        let container = DockerService.parseContainer(json)
        XCTAssertNotNil(container)
        XCTAssertEqual(container?.id, "abc123def456")
        XCTAssertEqual(container?.name, "my-web-app")
        XCTAssertEqual(container?.image, "nginx:latest")
        XCTAssertEqual(container?.state, .running)
        XCTAssertEqual(container?.status, "Up 3 hours")
        XCTAssertEqual(container?.ports.count, 1)
        XCTAssertEqual(container?.ports.first?.privatePort, 80)
        XCTAssertEqual(container?.ports.first?.publicPort, 8080)
        XCTAssertEqual(container?.ports.first?.type, "tcp")
        XCTAssertEqual(container?.ports.first?.ip, "0.0.0.0")
    }

    func testParseContainerNameStripsLeadingSlash() {
        let json: [String: Any] = [
            "Id": "abc123def456",
            "Names": ["/web-server"],
            "Image": "nginx",
            "State": "running",
            "Status": "Up",
            "Created": 1700000000.0,
            "Ports": [] as [[String: Any]],
        ]

        let container = DockerService.parseContainer(json)
        XCTAssertEqual(container?.name, "web-server",
                       "Leading slash should be stripped from container name")
    }

    func testParseContainerWithNoNames() {
        let json: [String: Any] = [
            "Id": "abc123def456aaaa",
            "Names": [] as [String],
            "Image": "alpine",
            "State": "exited",
            "Status": "Exited (0) 5 minutes ago",
            "Created": 1700000000.0,
            "Ports": [] as [[String: Any]],
        ]

        let container = DockerService.parseContainer(json)
        XCTAssertNotNil(container)
        // Falls back to short ID when no names
        XCTAssertEqual(container?.name, "abc123def456")
    }

    func testParseContainerMissingID() {
        let json: [String: Any] = [
            "Names": ["/test"],
            "Image": "alpine",
            "State": "running",
        ]

        let container = DockerService.parseContainer(json)
        XCTAssertNil(container, "Container without Id should return nil")
    }

    func testParseContainerExitedState() {
        let json: [String: Any] = [
            "Id": "def456789abc",
            "Names": ["/old-container"],
            "Image": "ubuntu:22.04",
            "State": "exited",
            "Status": "Exited (137) 2 days ago",
            "Created": 1699000000.0,
            "Ports": [] as [[String: Any]],
        ]

        let container = DockerService.parseContainer(json)
        XCTAssertNotNil(container)
        XCTAssertEqual(container?.state, .exited)
        XCTAssertEqual(container?.status, "Exited (137) 2 days ago")
    }

    func testParseContainerMultiplePorts() {
        let json: [String: Any] = [
            "Id": "multiport12345",
            "Names": ["/multi-port-app"],
            "Image": "myapp:latest",
            "State": "running",
            "Status": "Up 1 hour",
            "Created": 1700000000.0,
            "Ports": [
                [
                    "IP": "0.0.0.0",
                    "PrivatePort": 80,
                    "PublicPort": 8080,
                    "Type": "tcp",
                ] as [String: Any],
                [
                    "IP": "0.0.0.0",
                    "PrivatePort": 443,
                    "PublicPort": 8443,
                    "Type": "tcp",
                ] as [String: Any],
                [
                    "PrivatePort": 53,
                    "Type": "udp",
                ] as [String: Any],
            ] as [[String: Any]],
        ]

        let container = DockerService.parseContainer(json)
        XCTAssertEqual(container?.ports.count, 3)
        XCTAssertEqual(container?.ports[0].publicPort, 8080)
        XCTAssertEqual(container?.ports[1].publicPort, 8443)
        XCTAssertNil(container?.ports[2].publicPort, "Unbound port should have nil publicPort")
        XCTAssertEqual(container?.ports[2].type, "udp")
    }
}

// MARK: - Docker Port Tests

final class DockerPortTests: XCTestCase {

    func testPortDisplayStringWithMapping() {
        let port = DockerPort(privatePort: 80, publicPort: 8080, type: "tcp", ip: "0.0.0.0")
        XCTAssertEqual(port.displayString, "0.0.0.0:8080->80/tcp")
    }

    func testPortDisplayStringWithoutIP() {
        let port = DockerPort(privatePort: 80, publicPort: 8080, type: "tcp", ip: nil)
        XCTAssertEqual(port.displayString, "8080->80/tcp")
    }

    func testPortDisplayStringUnbound() {
        let port = DockerPort(privatePort: 53, publicPort: nil, type: "udp", ip: nil)
        XCTAssertEqual(port.displayString, "53/udp")
    }

    func testParsePort() {
        let json: [String: Any] = [
            "IP": "127.0.0.1",
            "PrivatePort": 3000,
            "PublicPort": 3000,
            "Type": "tcp",
        ]

        let port = DockerService.parsePort(json)
        XCTAssertNotNil(port)
        XCTAssertEqual(port?.privatePort, 3000)
        XCTAssertEqual(port?.publicPort, 3000)
        XCTAssertEqual(port?.type, "tcp")
        XCTAssertEqual(port?.ip, "127.0.0.1")
    }

    func testParsePortMissingPrivatePort() {
        let json: [String: Any] = [
            "Type": "tcp",
        ]

        let port = DockerService.parsePort(json)
        XCTAssertNil(port, "Port without PrivatePort should return nil")
    }

    func testParsePortDefaultType() {
        let json: [String: Any] = [
            "PrivatePort": 80,
        ]

        let port = DockerService.parsePort(json)
        XCTAssertEqual(port?.type, "tcp", "Default type should be tcp")
    }
}

// MARK: - Docker Error Tests

final class DockerErrorTests: XCTestCase {

    func testSocketNotFoundDescription() {
        let error = DockerError.socketNotFound
        XCTAssertTrue(error.localizedDescription.contains("Docker socket"),
                       "Error should mention Docker socket")
    }

    func testRequestFailedDescription() {
        let error = DockerError.requestFailed(path: "/containers/abc/stop", statusCode: 409, body: "conflict")
        let desc = error.localizedDescription
        XCTAssertTrue(desc.contains("/containers/abc/stop"))
        XCTAssertTrue(desc.contains("409"))
        XCTAssertTrue(desc.contains("conflict"))
    }

    func testNotAvailableDescription() {
        let error = DockerError.notAvailable
        XCTAssertTrue(error.localizedDescription.contains("not available"))
    }
}

// MARK: - Mock Docker Service Tests

/// Tests using the mock to verify the action flow without a real Docker daemon
final class MockDockerServiceTests: XCTestCase {

    func testListContainersReturnsMocked() async throws {
        let mock = MockDockerService()
        mock.mockContainers = [
            .makeTest(id: "aaa", name: "web"),
            .makeTest(id: "bbb", name: "db", state: .exited, status: "Exited (0)"),
        ]

        let containers = try await mock.listContainers()
        XCTAssertEqual(containers.count, 2)
        XCTAssertEqual(containers[0].name, "web")
        XCTAssertEqual(containers[1].name, "db")
        XCTAssertTrue(mock.listContainersCalled)
    }

    func testStartContainerTracked() async throws {
        let mock = MockDockerService()
        try await mock.startContainer(id: "abc123")
        XCTAssertEqual(mock.startedContainerIDs, ["abc123"])
    }

    func testStopContainerTracked() async throws {
        let mock = MockDockerService()
        try await mock.stopContainer(id: "def456")
        XCTAssertEqual(mock.stoppedContainerIDs, ["def456"])
    }

    func testRestartContainerTracked() async throws {
        let mock = MockDockerService()
        try await mock.restartContainer(id: "ghi789")
        XCTAssertEqual(mock.restartedContainerIDs, ["ghi789"])
    }

    func testPauseContainerTracked() async throws {
        let mock = MockDockerService()
        try await mock.pauseContainer(id: "pause1")
        XCTAssertEqual(mock.pausedContainerIDs, ["pause1"])
    }

    func testUnpauseContainerTracked() async throws {
        let mock = MockDockerService()
        try await mock.unpauseContainer(id: "unpause1")
        XCTAssertEqual(mock.unpausedContainerIDs, ["unpause1"])
    }

    func testRemoveContainerTracked() async throws {
        let mock = MockDockerService()
        try await mock.removeContainer(id: "remove1", force: true)
        XCTAssertEqual(mock.removedContainerIDs.count, 1)
        XCTAssertEqual(mock.removedContainerIDs[0].id, "remove1")
        XCTAssertTrue(mock.removedContainerIDs[0].force)
    }

    func testRemoveContainerNoForce() async throws {
        let mock = MockDockerService()
        try await mock.removeContainer(id: "remove2", force: false)
        XCTAssertFalse(mock.removedContainerIDs[0].force)
    }

    func testContainerLogsReturned() async throws {
        let mock = MockDockerService()
        mock.mockLogs = "line 1\nline 2\nline 3"
        let logs = try await mock.containerLogs(id: "log1", tail: 50)
        XCTAssertEqual(logs, "line 1\nline 2\nline 3")
        XCTAssertEqual(mock.logRequestedContainerIDs.count, 1)
        XCTAssertEqual(mock.logRequestedContainerIDs[0].id, "log1")
        XCTAssertEqual(mock.logRequestedContainerIDs[0].tail, 50)
    }

    func testUnavailableState() async {
        let mock = MockDockerService()
        mock.mockAvailable = false
        mock.mockSocketPath = nil
        let available = await mock.isDockerAvailable
        let socket = await mock.socketPath
        XCTAssertFalse(available)
        XCTAssertNil(socket)
    }

    func testAvailableState() async {
        let mock = MockDockerService()
        mock.mockAvailable = true
        mock.mockSocketPath = "/var/run/docker.sock"
        let available = await mock.isDockerAvailable
        let socket = await mock.socketPath
        XCTAssertTrue(available)
        XCTAssertEqual(socket, "/var/run/docker.sock")
    }

    func testErrorPropagation() async {
        let mock = MockDockerService()
        mock.mockError = DockerError.socketNotFound

        do {
            _ = try await mock.listContainers()
            XCTFail("Should have thrown")
        } catch {
            XCTAssertTrue(error is DockerError)
        }

        do {
            try await mock.startContainer(id: "x")
            XCTFail("Should have thrown")
        } catch {
            XCTAssertTrue(error is DockerError)
        }

        do {
            try await mock.stopContainer(id: "x")
            XCTFail("Should have thrown")
        } catch {
            XCTAssertTrue(error is DockerError)
        }
    }
}

// MARK: - Docker Log Header Stripping Tests

final class DockerLogHeaderTests: XCTestCase {

    func testStripCleanText() {
        let clean = "Hello, world!\nSecond line"
        let result = DockerService.stripDockerLogHeaders(clean)
        XCTAssertEqual(result, "Hello, world!\nSecond line")
    }

    func testStripEmptyString() {
        let result = DockerService.stripDockerLogHeaders("")
        XCTAssertEqual(result, "")
    }

    func testStripTrailingNewlines() {
        let result = DockerService.stripDockerLogHeaders("line1\nline2\n\n")
        XCTAssertEqual(result, "line1\nline2")
    }
}

// MARK: - Docker Action Integration Tests

/// Tests that Docker actions flow correctly through ActionViewModel
final class DockerActionIntegrationTests: XCTestCase {
    private var tempDir: String!

    private static let appStorageKeys = [
        "action.process.kill",
        "action.process.forceKill",
        "action.process.suspend",
        "action.process.renice",
        "action.storage.eject",
        "action.storage.forceEject",
        "action.clipboard.copy",
        "action.docker.lifecycle",
        "action.docker.remove",
        "action.network.enabled",
        "action.system.enabled",
        "action.confirm.destructive",
        "action.confirm.skipReversible",
    ]

    override func setUp() async throws {
        for key in Self.appStorageKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        let baseTempDir = NSTemporaryDirectory()
        tempDir = baseTempDir + "processscope-docker-test-\(UUID().uuidString)"
    }

    override func tearDown() async throws {
        if let dir = tempDir {
            try? FileManager.default.removeItem(atPath: dir)
        }
        tempDir = nil
    }

    @MainActor
    func testDockerActionBlockedWhenDisabled() async {
        let auditTrail = AuditTrail(directory: tempDir)
        let config = ActionConfiguration()
        // dockerLifecycleEnabled defaults to false
        let mock = MockDockerService()
        let vm = ActionViewModel(
            configuration: config,
            auditTrail: auditTrail,
            dockerService: mock
        )

        let target = ActionTarget(name: "web-app", containerID: "abc123")
        await vm.requestAction(.dockerStop, target: target)

        // Should be blocked — action not enabled
        XCTAssertNotNil(vm.lastErrorMessage)
        XCTAssertTrue(mock.stoppedContainerIDs.isEmpty, "Docker service should not be called when action is disabled")

        let entries = await auditTrail.recentEntries(limit: 10)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.result, .failure)
        XCTAssertEqual(entries.first?.actionType, .dockerStop)
    }

    @MainActor
    func testDockerStopActionExecutes() async {
        let auditTrail = AuditTrail(directory: tempDir)
        let config = ActionConfiguration()
        config.dockerLifecycleEnabled = true
        config.alwaysConfirmDestructive = false
        config.skipConfirmReversible = true
        let mock = MockDockerService()
        let vm = ActionViewModel(
            configuration: config,
            auditTrail: auditTrail,
            dockerService: mock
        )

        let target = ActionTarget(name: "web-app", containerID: "abc123")
        await vm.requestAction(.dockerStop, target: target)

        // dockerStop is not destructive, and with skipConfirmReversible it should execute directly
        XCTAssertEqual(mock.stoppedContainerIDs, ["abc123"])

        let entries = await auditTrail.recentEntries(limit: 10)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.result, .success)
        XCTAssertEqual(entries.first?.actionType, .dockerStop)
    }

    @MainActor
    func testDockerStartActionExecutes() async {
        let auditTrail = AuditTrail(directory: tempDir)
        let config = ActionConfiguration()
        config.dockerLifecycleEnabled = true
        config.alwaysConfirmDestructive = false
        config.skipConfirmReversible = true
        let mock = MockDockerService()
        let vm = ActionViewModel(
            configuration: config,
            auditTrail: auditTrail,
            dockerService: mock
        )

        let target = ActionTarget(name: "db", containerID: "def456")
        await vm.requestAction(.dockerStart, target: target)

        XCTAssertEqual(mock.startedContainerIDs, ["def456"])
    }

    @MainActor
    func testDockerRestartActionExecutes() async {
        let auditTrail = AuditTrail(directory: tempDir)
        let config = ActionConfiguration()
        config.dockerLifecycleEnabled = true
        config.alwaysConfirmDestructive = false
        config.skipConfirmReversible = true
        let mock = MockDockerService()
        let vm = ActionViewModel(
            configuration: config,
            auditTrail: auditTrail,
            dockerService: mock
        )

        let target = ActionTarget(name: "api", containerID: "ghi789")
        await vm.requestAction(.dockerRestart, target: target)

        XCTAssertEqual(mock.restartedContainerIDs, ["ghi789"])
    }

    @MainActor
    func testDockerPauseActionExecutes() async {
        let auditTrail = AuditTrail(directory: tempDir)
        let config = ActionConfiguration()
        config.dockerLifecycleEnabled = true
        config.alwaysConfirmDestructive = false
        config.skipConfirmReversible = true
        let mock = MockDockerService()
        let vm = ActionViewModel(
            configuration: config,
            auditTrail: auditTrail,
            dockerService: mock
        )

        let target = ActionTarget(name: "worker", containerID: "pause1")
        await vm.requestAction(.dockerPause, target: target)

        XCTAssertEqual(mock.pausedContainerIDs, ["pause1"])
    }

    @MainActor
    func testDockerUnpauseActionExecutes() async {
        let auditTrail = AuditTrail(directory: tempDir)
        let config = ActionConfiguration()
        config.dockerLifecycleEnabled = true
        config.alwaysConfirmDestructive = false
        config.skipConfirmReversible = true
        let mock = MockDockerService()
        let vm = ActionViewModel(
            configuration: config,
            auditTrail: auditTrail,
            dockerService: mock
        )

        let target = ActionTarget(name: "worker", containerID: "unpause1")
        await vm.requestAction(.dockerUnpause, target: target)

        XCTAssertEqual(mock.unpausedContainerIDs, ["unpause1"])
    }

    @MainActor
    func testDockerRemoveRequiresConfirmation() async {
        let auditTrail = AuditTrail(directory: tempDir)
        let config = ActionConfiguration()
        config.dockerLifecycleEnabled = true
        config.dockerRemoveEnabled = true
        config.alwaysConfirmDestructive = true
        let mock = MockDockerService()
        let vm = ActionViewModel(
            configuration: config,
            auditTrail: auditTrail,
            dockerService: mock
        )

        let target = ActionTarget(name: "old-container", containerID: "remove1")
        await vm.requestAction(.dockerRemove, target: target)

        // dockerRemove is destructive — should show confirmation
        XCTAssertTrue(vm.showConfirmation, "dockerRemove should show confirmation dialog")
        XCTAssertNotNil(vm.pendingAction)
        XCTAssertEqual(vm.pendingAction?.actionType, .dockerRemove)
        XCTAssertTrue(mock.removedContainerIDs.isEmpty, "Should not execute until confirmed")
    }

    @MainActor
    func testDockerRemoveBlockedWhenRemoveDisabled() async {
        let auditTrail = AuditTrail(directory: tempDir)
        let config = ActionConfiguration()
        config.dockerLifecycleEnabled = true
        config.dockerRemoveEnabled = false  // Remove is separately gated
        let mock = MockDockerService()
        let vm = ActionViewModel(
            configuration: config,
            auditTrail: auditTrail,
            dockerService: mock
        )

        let target = ActionTarget(name: "old-container", containerID: "remove1")
        await vm.requestAction(.dockerRemove, target: target)

        XCTAssertNotNil(vm.lastErrorMessage, "Should show error when remove is disabled")
        XCTAssertTrue(mock.removedContainerIDs.isEmpty)
    }

    @MainActor
    func testDockerRemoveConfirmAndExecute() async {
        let auditTrail = AuditTrail(directory: tempDir)
        let config = ActionConfiguration()
        config.dockerLifecycleEnabled = true
        config.dockerRemoveEnabled = true
        config.alwaysConfirmDestructive = true
        let mock = MockDockerService()
        let vm = ActionViewModel(
            configuration: config,
            auditTrail: auditTrail,
            dockerService: mock
        )

        let target = ActionTarget(name: "old-container", containerID: "remove1")
        await vm.requestAction(.dockerRemove, target: target)

        // Confirm the action
        XCTAssertTrue(vm.showConfirmation)
        await vm.confirmAction()

        XCTAssertEqual(mock.removedContainerIDs.count, 1)
        XCTAssertEqual(mock.removedContainerIDs[0].id, "remove1")
        XCTAssertFalse(mock.removedContainerIDs[0].force)

        let entries = await auditTrail.recentEntries(limit: 10)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.result, .success)
        XCTAssertEqual(entries.first?.actionType, .dockerRemove)
        XCTAssertTrue(entries.first?.wasConfirmed ?? false)
    }

    @MainActor
    func testDockerRemoveCancelledLogs() async {
        let auditTrail = AuditTrail(directory: tempDir)
        let config = ActionConfiguration()
        config.dockerLifecycleEnabled = true
        config.dockerRemoveEnabled = true
        config.alwaysConfirmDestructive = true
        let mock = MockDockerService()
        let vm = ActionViewModel(
            configuration: config,
            auditTrail: auditTrail,
            dockerService: mock
        )

        let target = ActionTarget(name: "old-container", containerID: "remove1")
        await vm.requestAction(.dockerRemove, target: target)

        // Cancel the action
        vm.cancelAction()

        XCTAssertTrue(mock.removedContainerIDs.isEmpty, "Container should not be removed after cancel")
        XCTAssertEqual(vm.lastResult, .cancelled)

        // Wait for the async audit task
        try? await Task.sleep(for: .milliseconds(100))

        let entries = await auditTrail.recentEntries(limit: 10)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.result, .cancelled)
    }

    @MainActor
    func testDockerActionWithMissingContainerID() async {
        let auditTrail = AuditTrail(directory: tempDir)
        let config = ActionConfiguration()
        config.dockerLifecycleEnabled = true
        config.alwaysConfirmDestructive = false
        config.skipConfirmReversible = true
        let mock = MockDockerService()
        let vm = ActionViewModel(
            configuration: config,
            auditTrail: auditTrail,
            dockerService: mock
        )

        // Target without containerID
        let target = ActionTarget(name: "orphan")
        await vm.requestAction(.dockerStop, target: target)

        XCTAssertEqual(vm.lastResult, .failure)
        XCTAssertTrue(vm.lastErrorMessage?.contains("No container ID") ?? false)
    }

    @MainActor
    func testDockerActionErrorPropagation() async {
        let auditTrail = AuditTrail(directory: tempDir)
        let config = ActionConfiguration()
        config.dockerLifecycleEnabled = true
        config.alwaysConfirmDestructive = false
        config.skipConfirmReversible = true
        let mock = MockDockerService()
        mock.mockError = DockerError.socketNotFound
        let vm = ActionViewModel(
            configuration: config,
            auditTrail: auditTrail,
            dockerService: mock
        )

        let target = ActionTarget(name: "web", containerID: "abc")
        await vm.requestAction(.dockerStop, target: target)

        XCTAssertEqual(vm.lastResult, .failure)
        XCTAssertNotNil(vm.lastErrorMessage)

        let entries = await auditTrail.recentEntries(limit: 10)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.result, .failure)
    }

    @MainActor
    func testDockerAuditTrailLogsTarget() async {
        let auditTrail = AuditTrail(directory: tempDir)
        let config = ActionConfiguration()
        config.dockerLifecycleEnabled = true
        config.alwaysConfirmDestructive = false
        config.skipConfirmReversible = true
        let mock = MockDockerService()
        let vm = ActionViewModel(
            configuration: config,
            auditTrail: auditTrail,
            dockerService: mock
        )

        let target = ActionTarget(name: "my-container", containerID: "xyz789")
        await vm.requestAction(.dockerStop, target: target)

        let entries = await auditTrail.recentEntries(limit: 10)
        XCTAssertEqual(entries.count, 1)
        XCTAssertTrue(entries.first?.targetDescription.contains("my-container") ?? false,
                       "Audit entry should contain the container name")
        XCTAssertTrue(entries.first?.targetDescription.contains("xyz789") ?? false,
                       "Audit entry should contain the container ID")
    }
}

// MARK: - Docker Configuration Tests

final class DockerConfigurationTests: XCTestCase {

    private static let appStorageKeys = [
        "action.docker.lifecycle",
        "action.docker.remove",
    ]

    override func setUp() {
        for key in Self.appStorageKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    @MainActor
    func testDockerLifecycleDisabledByDefault() {
        let config = ActionConfiguration()
        XCTAssertFalse(config.dockerLifecycleEnabled,
                       "dockerLifecycleEnabled should default to false")
    }

    @MainActor
    func testDockerRemoveDisabledByDefault() {
        let config = ActionConfiguration()
        XCTAssertFalse(config.dockerRemoveEnabled,
                       "dockerRemoveEnabled should default to false")
    }

    @MainActor
    func testDockerLifecycleActionsAllowedWhenEnabled() {
        let config = ActionConfiguration()
        config.dockerLifecycleEnabled = true

        XCTAssertTrue(config.isActionAllowed(.dockerStop))
        XCTAssertTrue(config.isActionAllowed(.dockerStart))
        XCTAssertTrue(config.isActionAllowed(.dockerRestart))
        XCTAssertTrue(config.isActionAllowed(.dockerPause))
        XCTAssertTrue(config.isActionAllowed(.dockerUnpause))
    }

    @MainActor
    func testDockerRemoveRequiresBothToggles() {
        let config = ActionConfiguration()

        // Neither enabled
        XCTAssertFalse(config.isActionAllowed(.dockerRemove))

        // Only lifecycle enabled
        config.dockerLifecycleEnabled = true
        XCTAssertFalse(config.isActionAllowed(.dockerRemove),
                       "dockerRemove should require BOTH lifecycle AND remove toggles")

        // Both enabled
        config.dockerRemoveEnabled = true
        XCTAssertTrue(config.isActionAllowed(.dockerRemove))

        // Only remove enabled (not lifecycle)
        config.dockerLifecycleEnabled = false
        XCTAssertFalse(config.isActionAllowed(.dockerRemove))
    }

    @MainActor
    func testDockerLifecycleActionsBlockedWhenDisabled() {
        let config = ActionConfiguration()
        // Defaults to false

        for actionType in [ActionType.dockerStop, .dockerStart, .dockerRestart,
                           .dockerPause, .dockerUnpause] {
            XCTAssertFalse(config.isActionAllowed(actionType),
                           "\(actionType.rawValue) should be blocked when dockerLifecycleEnabled is false")
        }
    }
}
