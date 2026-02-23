import XCTest
@testable import ProcessScope

// MARK: - SSH Command Construction Tests

final class SSHCommandTests: XCTestCase {

    func testBasicSSHCommand() {
        let service = NetworkActionService()
        let cmd = service.buildSSHCommand(host: "example.com", user: nil, port: nil)
        XCTAssertEqual(cmd, "ssh example.com")
    }

    func testSSHCommandWithUser() {
        let service = NetworkActionService()
        let cmd = service.buildSSHCommand(host: "example.com", user: "admin", port: nil)
        XCTAssertEqual(cmd, "ssh admin@example.com")
    }

    func testSSHCommandWithPort() {
        let service = NetworkActionService()
        let cmd = service.buildSSHCommand(host: "example.com", user: nil, port: 2222)
        XCTAssertEqual(cmd, "ssh example.com -p 2222")
    }

    func testSSHCommandWithUserAndPort() {
        let service = NetworkActionService()
        let cmd = service.buildSSHCommand(host: "example.com", user: "root", port: 8022)
        XCTAssertEqual(cmd, "ssh root@example.com -p 8022")
    }

    func testSSHCommandWithDefaultPort() {
        let service = NetworkActionService()
        let cmd = service.buildSSHCommand(host: "example.com", user: "deploy", port: 22)
        // Port 22 is the default and should not be included
        XCTAssertEqual(cmd, "ssh deploy@example.com")
    }

    func testSSHCommandWithIPAddress() {
        let service = NetworkActionService()
        let cmd = service.buildSSHCommand(host: "192.168.1.100", user: "pi", port: nil)
        XCTAssertEqual(cmd, "ssh pi@192.168.1.100")
    }
}

// MARK: - Ping Output Parsing Tests

final class PingOutputParsingTests: XCTestCase {

    func testParsePingOutputBasic() throws {
        let output = """
        PING example.com (93.184.216.34): 56 data bytes
        64 bytes from 93.184.216.34: icmp_seq=0 ttl=56 time=12.345 ms
        64 bytes from 93.184.216.34: icmp_seq=1 ttl=56 time=13.456 ms
        64 bytes from 93.184.216.34: icmp_seq=2 ttl=56 time=11.234 ms

        --- example.com ping statistics ---
        3 packets transmitted, 3 packets received, 0.0% packet loss
        round-trip min/avg/max/stddev = 11.234/12.345/13.456/0.907 ms
        """

        let result = try NetworkActionService.parsePingOutput(output)
        XCTAssertEqual(result.transmitted, 3)
        XCTAssertEqual(result.received, 3)
        XCTAssertEqual(result.lossPercent, 0.0, accuracy: 0.01)
        XCTAssertEqual(result.minMs, 11.234, accuracy: 0.001)
        XCTAssertEqual(result.avgMs, 12.345, accuracy: 0.001)
        XCTAssertEqual(result.maxMs, 13.456, accuracy: 0.001)
    }

    func testParsePingOutputWithPacketLoss() throws {
        let output = """
        PING 10.0.0.1 (10.0.0.1): 56 data bytes
        64 bytes from 10.0.0.1: icmp_seq=0 ttl=64 time=1.234 ms
        Request timeout for icmp_seq 1
        64 bytes from 10.0.0.1: icmp_seq=2 ttl=64 time=2.345 ms

        --- 10.0.0.1 ping statistics ---
        3 packets transmitted, 2 packets received, 33.3% packet loss
        round-trip min/avg/max/stddev = 1.234/1.790/2.345/0.555 ms
        """

        let result = try NetworkActionService.parsePingOutput(output)
        XCTAssertEqual(result.transmitted, 3)
        XCTAssertEqual(result.received, 2)
        XCTAssertEqual(result.lossPercent, 33.3, accuracy: 0.1)
        XCTAssertEqual(result.minMs, 1.234, accuracy: 0.001)
        XCTAssertEqual(result.avgMs, 1.790, accuracy: 0.001)
        XCTAssertEqual(result.maxMs, 2.345, accuracy: 0.001)
    }

    func testParsePingOutputAllLost() throws {
        let output = """
        PING 10.255.255.1 (10.255.255.1): 56 data bytes
        Request timeout for icmp_seq 0
        Request timeout for icmp_seq 1
        Request timeout for icmp_seq 2

        --- 10.255.255.1 ping statistics ---
        3 packets transmitted, 0 packets received, 100.0% packet loss
        """

        let result = try NetworkActionService.parsePingOutput(output)
        XCTAssertEqual(result.transmitted, 3)
        XCTAssertEqual(result.received, 0)
        XCTAssertEqual(result.lossPercent, 100.0, accuracy: 0.01)
        XCTAssertEqual(result.minMs, 0.0)
        XCTAssertEqual(result.avgMs, 0.0)
        XCTAssertEqual(result.maxMs, 0.0)
    }

    func testParsePingOutputInvalidThrows() {
        let output = "This is not valid ping output"
        XCTAssertThrowsError(try NetworkActionService.parsePingOutput(output)) { error in
            XCTAssertTrue(error is NetworkActionError)
        }
    }

    func testParsePingOutputSinglePacket() throws {
        let output = """
        PING localhost (127.0.0.1): 56 data bytes
        64 bytes from 127.0.0.1: icmp_seq=0 ttl=64 time=0.045 ms

        --- localhost ping statistics ---
        1 packets transmitted, 1 packets received, 0.0% packet loss
        round-trip min/avg/max/stddev = 0.045/0.045/0.045/0.000 ms
        """

        let result = try NetworkActionService.parsePingOutput(output)
        XCTAssertEqual(result.transmitted, 1)
        XCTAssertEqual(result.received, 1)
        XCTAssertEqual(result.lossPercent, 0.0)
        XCTAssertEqual(result.minMs, 0.045, accuracy: 0.001)
    }
}

// MARK: - Traceroute Output Parsing Tests

final class TracerouteOutputParsingTests: XCTestCase {

    func testParseTracerouteBasic() {
        let output = """
        traceroute to example.com (93.184.216.34), 30 hops max, 60 byte packets
         1  gateway (192.168.1.1)  1.234 ms  1.567 ms  1.890 ms
         2  10.0.0.1 (10.0.0.1)  5.432 ms  5.678 ms  5.901 ms
         3  example.com (93.184.216.34)  12.345 ms  12.456 ms  12.567 ms
        """

        let hops = NetworkActionService.parseTracerouteOutput(output)
        XCTAssertEqual(hops.count, 3)

        XCTAssertEqual(hops[0].hopNumber, 1)
        XCTAssertEqual(hops[0].host, "gateway")
        XCTAssertEqual(hops[0].ip, "192.168.1.1")
        XCTAssertEqual(hops[0].rttMs.count, 3)
        XCTAssertEqual(hops[0].rttMs[0], 1.234, accuracy: 0.001)

        XCTAssertEqual(hops[1].hopNumber, 2)
        XCTAssertEqual(hops[1].ip, "10.0.0.1")

        XCTAssertEqual(hops[2].hopNumber, 3)
        XCTAssertEqual(hops[2].host, "example.com")
    }

    func testParseTracerouteWithTimeoutHops() {
        let output = """
        traceroute to example.com (93.184.216.34), 30 hops max, 60 byte packets
         1  gateway (192.168.1.1)  1.234 ms  1.567 ms  1.890 ms
         2  * * *
         3  example.com (93.184.216.34)  12.345 ms  12.456 ms  12.567 ms
        """

        let hops = NetworkActionService.parseTracerouteOutput(output)
        XCTAssertEqual(hops.count, 3)

        XCTAssertEqual(hops[1].hopNumber, 2)
        XCTAssertEqual(hops[1].host, "*")
        XCTAssertEqual(hops[1].ip, "*")
        XCTAssertTrue(hops[1].rttMs.isEmpty)
    }

    func testParseTracerouteEmptyOutput() {
        let output = ""
        let hops = NetworkActionService.parseTracerouteOutput(output)
        XCTAssertTrue(hops.isEmpty)
    }

    func testParseTracerouteHeaderOnly() {
        let output = "traceroute to example.com (93.184.216.34), 30 hops max, 60 byte packets"
        let hops = NetworkActionService.parseTracerouteOutput(output)
        XCTAssertTrue(hops.isEmpty)
    }
}

// MARK: - DNS Lookup Output Parsing Tests

final class DNSLookupParsingTests: XCTestCase {

    func testParseNslookupBasic() throws {
        let output = """
        Server:		8.8.8.8
        Address:	8.8.8.8#53

        Non-authoritative answer:
        Name:	example.com
        Address: 93.184.216.34
        """

        let result = try NetworkActionService.parseNslookupOutput(output, hostname: "example.com")
        XCTAssertEqual(result.hostname, "example.com")
        XCTAssertEqual(result.server, "8.8.8.8")
        XCTAssertEqual(result.addresses.count, 1)
        XCTAssertEqual(result.addresses.first, "93.184.216.34")
    }

    func testParseNslookupMultipleAddresses() throws {
        let output = """
        Server:		1.1.1.1
        Address:	1.1.1.1#53

        Non-authoritative answer:
        Name:	google.com
        Address: 142.250.80.46
        Name:	google.com
        Address: 142.250.80.78
        """

        let result = try NetworkActionService.parseNslookupOutput(output, hostname: "google.com")
        XCTAssertEqual(result.hostname, "google.com")
        XCTAssertEqual(result.server, "1.1.1.1")
        XCTAssertEqual(result.addresses.count, 2)
        XCTAssertTrue(result.addresses.contains("142.250.80.46"))
        XCTAssertTrue(result.addresses.contains("142.250.80.78"))
    }

    func testParseNslookupNoResults() throws {
        let output = """
        Server:		8.8.8.8
        Address:	8.8.8.8#53

        ** server can't find nonexistent.example: NXDOMAIN
        """

        let result = try NetworkActionService.parseNslookupOutput(output, hostname: "nonexistent.example")
        XCTAssertEqual(result.hostname, "nonexistent.example")
        XCTAssertEqual(result.server, "8.8.8.8")
        XCTAssertTrue(result.addresses.isEmpty)
    }

    func testParseNslookupPreservesHostname() throws {
        let output = """
        Server:		8.8.8.8
        Address:	8.8.8.8#53

        Non-authoritative answer:
        Name:	test.local
        Address: 127.0.0.1
        """

        let result = try NetworkActionService.parseNslookupOutput(output, hostname: "test.local")
        XCTAssertEqual(result.hostname, "test.local")
    }
}

// MARK: - System Info Collection Tests

final class SystemInfoTests: XCTestCase {

    func testSystemInfoContainsRequiredFields() {
        let info = SystemActionService.collectSystemInfo()
        XCTAssertTrue(info.contains("macOS:"), "Should contain macOS version")
        XCTAssertTrue(info.contains("Memory:"), "Should contain memory information")
        XCTAssertTrue(info.contains("CPUs:"), "Should contain CPU information")
        XCTAssertTrue(info.contains("Uptime:"), "Should contain uptime")
        XCTAssertTrue(info.contains("Thermal State:"), "Should contain thermal state")
        XCTAssertTrue(info.contains("Architecture:"), "Should contain architecture")
    }

    func testSystemInfoContainsHeader() {
        let info = SystemActionService.collectSystemInfo()
        XCTAssertTrue(info.hasPrefix("ProcessScope System Information"))
    }

    func testSystemInfoIsMultiLine() {
        let info = SystemActionService.collectSystemInfo()
        let lines = info.components(separatedBy: "\n")
        XCTAssertGreaterThanOrEqual(lines.count, 7, "System info should have at least 7 lines")
    }

    func testSystemInfoContainsHostname() {
        let info = SystemActionService.collectSystemInfo()
        XCTAssertTrue(info.contains("Host:"), "Should contain hostname")
    }
}

// MARK: - Mock Network Action Service Tests

final class MockNetworkActionServiceTests: XCTestCase {

    func testMockSSHTracking() async {
        let mock = MockNetworkActionService()
        await mock.openSSHTerminal(host: "server.local", user: "admin", port: 2222)
        let commands = await mock.sshCommandsOpened
        XCTAssertEqual(commands.count, 1)
        XCTAssertEqual(commands[0].host, "server.local")
        XCTAssertEqual(commands[0].user, "admin")
        XCTAssertEqual(commands[0].port, 2222)
    }

    func testMockDNSFlush() async throws {
        let mock = MockNetworkActionService()
        try await mock.flushDNSCache()
        let count = await mock.dnsFlushCallCount
        XCTAssertEqual(count, 1)
    }

    func testMockDNSFlushThrows() async {
        let mock = MockNetworkActionService()
        await mock.setShouldThrowOnFlush(true)
        do {
            try await mock.flushDNSCache()
            XCTFail("Should have thrown")
        } catch {
            XCTAssertTrue(error is NetworkActionError)
        }
    }

    func testMockPingReturnsDefault() async throws {
        let mock = MockNetworkActionService()
        let result = try await mock.pingHost("test.local", count: 3)
        XCTAssertEqual(result.transmitted, 3)
        XCTAssertEqual(result.received, 3)
    }

    func testMockPingReturnsCustomResult() async throws {
        let mock = MockNetworkActionService()
        let customResult = PingResult(
            transmitted: 10, received: 8, lossPercent: 20.0,
            minMs: 5.0, avgMs: 10.0, maxMs: 15.0
        )
        await mock.setPingResult(host: "slow.host", result: customResult)
        let result = try await mock.pingHost("slow.host", count: 10)
        XCTAssertEqual(result.transmitted, 10)
        XCTAssertEqual(result.received, 8)
        XCTAssertEqual(result.lossPercent, 20.0)
    }

    func testMockTracerouteReturnsCustom() async throws {
        let mock = MockNetworkActionService()
        let hops = [
            TraceHop(hopNumber: 1, host: "gateway", ip: "192.168.1.1", rttMs: [1.0, 2.0, 3.0]),
            TraceHop(hopNumber: 2, host: "next", ip: "10.0.0.1", rttMs: [5.0, 6.0, 7.0])
        ]
        await mock.setTraceRouteResult(host: "example.com", hops: hops)
        let result = try await mock.traceRoute(to: "example.com")
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].hopNumber, 1)
    }

    func testMockDNSLookupReturnsDefault() async throws {
        let mock = MockNetworkActionService()
        let result = try await mock.lookupDNS(hostname: "anything.com")
        XCTAssertEqual(result.hostname, "anything.com")
        XCTAssertEqual(result.addresses, ["127.0.0.1"])
    }
}

// MARK: - Mock System Action Service Tests

final class MockSystemActionServiceTests: XCTestCase {

    func testMockRevealInFinder() async {
        let mock = MockSystemActionService()
        await mock.revealInFinder(path: "/usr/bin/test")
        let paths = await mock.revealedPaths
        XCTAssertEqual(paths, ["/usr/bin/test"])
    }

    func testMockOpenActivityMonitor() async {
        let mock = MockSystemActionService()
        await mock.openActivityMonitor()
        let opened = await mock.activityMonitorOpened
        XCTAssertTrue(opened)
    }

    func testMockEmptyTrash() async throws {
        let mock = MockSystemActionService()
        try await mock.emptyTrash()
        let emptied = await mock.trashEmptied
        XCTAssertTrue(emptied)
    }

    func testMockEmptyTrashThrows() async {
        let mock = MockSystemActionService()
        await mock.setShouldThrowOnEmptyTrash(true)
        do {
            try await mock.emptyTrash()
            XCTFail("Should have thrown")
        } catch {
            XCTAssertTrue(error is SystemActionError)
        }
    }

    func testMockToggleDarkMode() async throws {
        let mock = MockSystemActionService()
        try await mock.toggleDarkMode()
        let toggled = await mock.darkModeToggled
        XCTAssertTrue(toggled)
    }

    func testMockLockScreen() async {
        let mock = MockSystemActionService()
        await mock.lockScreen()
        let locked = await mock.screenLocked
        XCTAssertTrue(locked)
    }

    func testMockCopySysInfo() async {
        let mock = MockSystemActionService()
        let info = await mock.copySysInfo()
        XCTAssertEqual(info, "Mock System Info")
        let collected = await mock.sysInfoCollected
        XCTAssertTrue(collected)
    }

    func testMockRestartFinder() async throws {
        let mock = MockSystemActionService()
        try await mock.restartFinder()
        let restarted = await mock.finderRestarted
        XCTAssertTrue(restarted)
    }

    func testMockRestartDock() async throws {
        let mock = MockSystemActionService()
        try await mock.restartDock()
        let restarted = await mock.dockRestarted
        XCTAssertTrue(restarted)
    }

    func testMockPurgeMemory() async throws {
        let mock = MockSystemActionService()
        try await mock.purgeMemory()
        let purged = await mock.memoryPurged
        XCTAssertTrue(purged)
    }

    func testMockPurgeMemoryThrows() async {
        let mock = MockSystemActionService()
        await mock.setShouldThrowOnPurge(true)
        do {
            try await mock.purgeMemory()
            XCTFail("Should have thrown")
        } catch {
            XCTAssertTrue(error is SystemActionError)
        }
    }
}

// MARK: - Audit Trail Integration Tests

final class NetworkSystemAuditTrailTests: XCTestCase {
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
        "action.network.sshTerminal",
        "action.network.pingTrace",
        "action.network.dnsFlush",
        "action.network.dnsLookup",
        "action.system.enabled",
        "action.system.purge",
        "action.system.restartServices",
        "action.system.power",
        "action.confirm.destructive",
        "action.confirm.skipReversible",
    ]

    override func setUp() async throws {
        for key in Self.appStorageKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        let baseTempDir = NSTemporaryDirectory()
        tempDir = baseTempDir + "processscope-m12-test-\(UUID().uuidString)"
    }

    override func tearDown() async throws {
        if let dir = tempDir {
            try? FileManager.default.removeItem(atPath: dir)
        }
        tempDir = nil
    }

    @MainActor
    func testNetworkActionBlockedWhenDisabled() async {
        let auditTrail = AuditTrail(directory: tempDir)
        let config = ActionConfiguration()
        // networkActionsEnabled defaults to false
        let vm = ActionViewModel(
            configuration: config,
            auditTrail: auditTrail,
            isHelperInstalled: false
        )

        let target = ActionTarget(name: "example.com", hostname: "example.com")
        await vm.requestAction(.pingHost, target: target)

        let entries = await auditTrail.recentEntries(limit: 10)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.result, .failure)
        XCTAssertEqual(entries.first?.actionType, .pingHost)
    }

    @MainActor
    func testSystemActionBlockedWhenDisabled() async {
        let auditTrail = AuditTrail(directory: tempDir)
        let config = ActionConfiguration()
        // systemActionsEnabled defaults to false
        let vm = ActionViewModel(
            configuration: config,
            auditTrail: auditTrail,
            isHelperInstalled: false
        )

        let target = ActionTarget(name: "Finder")
        await vm.requestAction(.restartFinder, target: target)

        let entries = await auditTrail.recentEntries(limit: 10)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.result, .failure)
        XCTAssertEqual(entries.first?.actionType, .restartFinder)
    }

    @MainActor
    func testFlushDNSBlockedWithoutHelper() async {
        let auditTrail = AuditTrail(directory: tempDir)
        let config = ActionConfiguration()
        config.networkActionsEnabled = true
        config.dnsFlushEnabled = true
        // Helper NOT installed
        let vm = ActionViewModel(
            configuration: config,
            auditTrail: auditTrail,
            isHelperInstalled: false
        )

        let target = ActionTarget(name: "system")
        await vm.requestAction(.flushDNS, target: target)

        let entries = await auditTrail.recentEntries(limit: 10)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.result, .failure)
        XCTAssertNotNil(vm.lastErrorMessage)
        XCTAssertTrue(vm.lastErrorMessage?.contains("helper") ?? false)
    }

    @MainActor
    func testPurgeMemoryBlockedWithoutHelper() async {
        let auditTrail = AuditTrail(directory: tempDir)
        let config = ActionConfiguration()
        config.systemActionsEnabled = true
        config.purgeEnabled = true
        // Helper NOT installed
        let vm = ActionViewModel(
            configuration: config,
            auditTrail: auditTrail,
            isHelperInstalled: false
        )

        let target = ActionTarget(name: "system")
        await vm.requestAction(.purgeMemory, target: target)

        let entries = await auditTrail.recentEntries(limit: 10)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.result, .failure)
    }

    @MainActor
    func testEmptyTrashShowsConfirmation() async {
        let auditTrail = AuditTrail(directory: tempDir)
        let config = ActionConfiguration()
        config.systemActionsEnabled = true
        config.alwaysConfirmDestructive = true
        let vm = ActionViewModel(
            configuration: config,
            auditTrail: auditTrail,
            isHelperInstalled: true
        )

        let target = ActionTarget(name: "Trash")
        await vm.requestAction(.emptyTrash, target: target)

        XCTAssertTrue(vm.showConfirmation)
        XCTAssertNotNil(vm.pendingAction)
        XCTAssertEqual(vm.pendingAction?.actionType, .emptyTrash)
    }

    @MainActor
    func testRestartFinderShowsConfirmation() async {
        let auditTrail = AuditTrail(directory: tempDir)
        let config = ActionConfiguration()
        config.systemActionsEnabled = true
        config.restartServicesEnabled = true
        config.alwaysConfirmDestructive = true
        let vm = ActionViewModel(
            configuration: config,
            auditTrail: auditTrail,
            isHelperInstalled: false
        )

        let target = ActionTarget(name: "Finder")
        await vm.requestAction(.restartFinder, target: target)

        XCTAssertTrue(vm.showConfirmation)
        XCTAssertNotNil(vm.pendingAction)
        XCTAssertEqual(vm.pendingAction?.actionType, .restartFinder)
    }

    @MainActor
    func testCopySysInfoSkipsConfirmationWhenReversibleSkipped() async {
        let auditTrail = AuditTrail(directory: tempDir)
        let config = ActionConfiguration()
        config.systemActionsEnabled = true
        config.alwaysConfirmDestructive = false
        config.skipConfirmReversible = true
        let mockSysActions = MockSystemActionService()
        let vm = ActionViewModel(
            configuration: config,
            auditTrail: auditTrail,
            systemActions: mockSysActions,
            isHelperInstalled: false
        )

        let target = ActionTarget(name: "System Info")
        await vm.requestAction(.copySysInfo, target: target)

        // copySysInfo is not destructive; with skipConfirmReversible it executes immediately
        XCTAssertFalse(vm.showConfirmation)
        XCTAssertNil(vm.pendingAction)

        let entries = await auditTrail.recentEntries(limit: 10)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.actionType, .copySysInfo)
        XCTAssertEqual(entries.first?.result, .success)
    }

    @MainActor
    func testCopySysInfoShowsConfirmationByDefault() async {
        let auditTrail = AuditTrail(directory: tempDir)
        let config = ActionConfiguration()
        config.systemActionsEnabled = true
        let mockSysActions = MockSystemActionService()
        let vm = ActionViewModel(
            configuration: config,
            auditTrail: auditTrail,
            systemActions: mockSysActions,
            isHelperInstalled: false
        )

        let target = ActionTarget(name: "System Info")
        await vm.requestAction(.copySysInfo, target: target)

        // By default, system actions show confirmation even for non-destructive
        XCTAssertTrue(vm.showConfirmation)
        XCTAssertNotNil(vm.pendingAction)
        XCTAssertEqual(vm.pendingAction?.actionType, .copySysInfo)
    }
}

// MARK: - ActionType Extended Tests for M12

final class ActionTypeM12Tests: XCTestCase {

    func testNewNetworkActionCategories() {
        XCTAssertEqual(ActionType.sshToTerminal.category, .network)
        XCTAssertEqual(ActionType.flushDNS.category, .network)
        XCTAssertEqual(ActionType.pingHost.category, .network)
        XCTAssertEqual(ActionType.traceRoute.category, .network)
        XCTAssertEqual(ActionType.dnsLookup.category, .network)
        XCTAssertEqual(ActionType.networkKillConnection.category, .network)
    }

    func testNewSystemActionCategories() {
        XCTAssertEqual(ActionType.purgeMemory.category, .system)
        XCTAssertEqual(ActionType.restartFinder.category, .system)
        XCTAssertEqual(ActionType.restartDock.category, .system)
        XCTAssertEqual(ActionType.openActivityMonitor.category, .system)
        XCTAssertEqual(ActionType.revealPathInFinder.category, .system)
        XCTAssertEqual(ActionType.emptyTrash.category, .system)
        XCTAssertEqual(ActionType.toggleDarkMode.category, .system)
        XCTAssertEqual(ActionType.lockScreen.category, .system)
        XCTAssertEqual(ActionType.copySysInfo.category, .system)
    }

    func testNewActionHelperRequirements() {
        XCTAssertTrue(ActionType.flushDNS.requiresHelper)
        XCTAssertTrue(ActionType.purgeMemory.requiresHelper)
        XCTAssertTrue(ActionType.networkKillConnection.requiresHelper)
        XCTAssertTrue(ActionType.emptyTrash.requiresHelper)

        XCTAssertFalse(ActionType.sshToTerminal.requiresHelper)
        XCTAssertFalse(ActionType.pingHost.requiresHelper)
        XCTAssertFalse(ActionType.traceRoute.requiresHelper)
        XCTAssertFalse(ActionType.dnsLookup.requiresHelper)
        XCTAssertFalse(ActionType.restartFinder.requiresHelper)
        XCTAssertFalse(ActionType.restartDock.requiresHelper)
        XCTAssertFalse(ActionType.openActivityMonitor.requiresHelper)
        XCTAssertFalse(ActionType.toggleDarkMode.requiresHelper)
        XCTAssertFalse(ActionType.lockScreen.requiresHelper)
        XCTAssertFalse(ActionType.copySysInfo.requiresHelper)
    }

    func testNewActionDestructiveness() {
        XCTAssertTrue(ActionType.emptyTrash.isDestructive)
        XCTAssertTrue(ActionType.networkKillConnection.isDestructive)
        XCTAssertTrue(ActionType.toggleDarkMode.isDestructive)
        XCTAssertTrue(ActionType.flushDNS.isDestructive)
        XCTAssertTrue(ActionType.purgeMemory.isDestructive)
        XCTAssertTrue(ActionType.restartFinder.isDestructive)
        XCTAssertTrue(ActionType.restartDock.isDestructive)

        XCTAssertFalse(ActionType.sshToTerminal.isDestructive)
        XCTAssertFalse(ActionType.pingHost.isDestructive)
        XCTAssertFalse(ActionType.traceRoute.isDestructive)
        XCTAssertFalse(ActionType.dnsLookup.isDestructive)
        XCTAssertFalse(ActionType.openActivityMonitor.isDestructive)
        XCTAssertFalse(ActionType.revealPathInFinder.isDestructive)
        XCTAssertFalse(ActionType.lockScreen.isDestructive)
        XCTAssertFalse(ActionType.copySysInfo.isDestructive)
    }

    func testToggleDarkModeIsOwnUndo() {
        XCTAssertEqual(ActionType.toggleDarkMode.undoAction, .toggleDarkMode)
    }

    func testAllNewActionsHaveDisplayNames() {
        let newActions: [ActionType] = [
            .sshToTerminal, .pingHost, .traceRoute, .dnsLookup,
            .openActivityMonitor, .revealPathInFinder, .emptyTrash,
            .toggleDarkMode, .lockScreen, .copySysInfo
        ]
        for action in newActions {
            XCTAssertFalse(action.displayName.isEmpty,
                           "\(action.rawValue) should have a non-empty displayName")
        }
    }

    func testAllNewActionsHaveSymbolNames() {
        let newActions: [ActionType] = [
            .sshToTerminal, .pingHost, .traceRoute, .dnsLookup,
            .openActivityMonitor, .revealPathInFinder, .emptyTrash,
            .toggleDarkMode, .lockScreen, .copySysInfo
        ]
        for action in newActions {
            XCTAssertFalse(action.symbolName.isEmpty,
                           "\(action.rawValue) should have a non-empty symbolName")
        }
    }
}

// MARK: - PingResult Tests

final class PingResultTests: XCTestCase {

    func testPingResultEquality() {
        let a = PingResult(transmitted: 5, received: 5, lossPercent: 0,
                           minMs: 10, avgMs: 15, maxMs: 20)
        let b = PingResult(transmitted: 5, received: 5, lossPercent: 0,
                           minMs: 10, avgMs: 15, maxMs: 20)
        XCTAssertEqual(a, b)
    }

    func testPingResultInequality() {
        let a = PingResult(transmitted: 5, received: 5, lossPercent: 0,
                           minMs: 10, avgMs: 15, maxMs: 20)
        let b = PingResult(transmitted: 5, received: 3, lossPercent: 40,
                           minMs: 10, avgMs: 15, maxMs: 20)
        XCTAssertNotEqual(a, b)
    }
}

// MARK: - TraceHop Tests

final class TraceHopTests: XCTestCase {

    func testTraceHopEquality() {
        let a = TraceHop(hopNumber: 1, host: "gw", ip: "192.168.1.1", rttMs: [1.0, 2.0, 3.0])
        let b = TraceHop(hopNumber: 1, host: "gw", ip: "192.168.1.1", rttMs: [1.0, 2.0, 3.0])
        XCTAssertEqual(a, b)
    }

    func testTraceHopTimeoutHop() {
        let hop = TraceHop(hopNumber: 3, host: "*", ip: "*", rttMs: [])
        XCTAssertEqual(hop.host, "*")
        XCTAssertTrue(hop.rttMs.isEmpty)
    }
}

// MARK: - DNSResult Tests

final class DNSResultTests: XCTestCase {

    func testDNSResultEquality() {
        let a = DNSResult(hostname: "example.com", addresses: ["1.2.3.4"],
                          server: "8.8.8.8", queryTimeMs: 5)
        let b = DNSResult(hostname: "example.com", addresses: ["1.2.3.4"],
                          server: "8.8.8.8", queryTimeMs: 5)
        XCTAssertEqual(a, b)
    }

    func testDNSResultMultipleAddresses() {
        let result = DNSResult(hostname: "multi.example.com",
                               addresses: ["1.2.3.4", "5.6.7.8"],
                               server: "1.1.1.1", queryTimeMs: 10)
        XCTAssertEqual(result.addresses.count, 2)
    }
}

// MARK: - NetworkActionError Tests

final class NetworkActionErrorTests: XCTestCase {

    func testCommandFailedDescription() {
        let error = NetworkActionError.commandFailed("ping", 2)
        XCTAssertTrue(error.localizedDescription.contains("ping"))
        XCTAssertTrue(error.localizedDescription.contains("2"))
    }

    func testParseErrorDescription() {
        let error = NetworkActionError.parseError("missing stats")
        XCTAssertTrue(error.localizedDescription.contains("missing stats"))
    }

    func testTimeoutDescription() {
        let error = NetworkActionError.timeout
        XCTAssertTrue(error.localizedDescription.contains("timed out"))
    }

    func testInvalidHostDescription() {
        let error = NetworkActionError.invalidHost("")
        XCTAssertTrue(error.localizedDescription.contains("Invalid host"))
    }
}

// MARK: - SystemActionError Tests

final class SystemActionErrorTests: XCTestCase {

    func testAppleScriptFailedDescription() {
        let error = SystemActionError.appleScriptFailed("Permission denied")
        XCTAssertTrue(error.localizedDescription.contains("Permission denied"))
    }

    func testCommandFailedDescription() {
        let error = SystemActionError.commandFailed("killall Dock", 1)
        XCTAssertTrue(error.localizedDescription.contains("killall Dock"))
    }

    func testHelperRequiredDescription() {
        let error = SystemActionError.helperRequired
        XCTAssertTrue(error.localizedDescription.contains("helper"))
    }
}

// MARK: - ActionTarget Hostname Tests

final class ActionTargetHostnameTests: XCTestCase {

    func testActionTargetWithHostname() {
        let target = ActionTarget(name: "example.com", hostname: "example.com")
        XCTAssertEqual(target.hostname, "example.com")
        let desc = target.auditDescription
        XCTAssertTrue(desc.contains("example.com"))
    }

    func testActionTargetHostnameNil() {
        let target = ActionTarget(name: "test")
        XCTAssertNil(target.hostname)
    }
}

// MARK: - Helper Methods for Mock Setters

extension MockNetworkActionService {
    func setShouldThrowOnFlush(_ value: Bool) {
        shouldThrowOnFlush = value
    }

    func setPingResult(host: String, result: PingResult) {
        pingResults[host] = result
    }

    func setTraceRouteResult(host: String, hops: [TraceHop]) {
        traceRouteResults[host] = hops
    }
}

extension MockSystemActionService {
    func setShouldThrowOnEmptyTrash(_ value: Bool) {
        shouldThrowOnEmptyTrash = value
    }

    func setShouldThrowOnPurge(_ value: Bool) {
        shouldThrowOnPurge = value
    }
}
