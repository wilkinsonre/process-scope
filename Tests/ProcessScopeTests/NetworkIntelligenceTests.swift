import XCTest
@testable import ProcessScope

final class NetworkIntelligenceTests: XCTestCase {

    // MARK: - SSH Argument Parsing Tests

    func testSSHParseUserAtHost() {
        let args = ["user@example.com"]
        let parsed = SSHSessionCollector.parseSSHArgs(args)

        XCTAssertEqual(parsed.user, "user")
        XCTAssertEqual(parsed.host, "example.com")
        XCTAssertEqual(parsed.port, 22)
        XCTAssertTrue(parsed.tunnels.isEmpty)
        XCTAssertNil(parsed.identityFile)
    }

    func testSSHParseHostOnly() {
        let args = ["example.com"]
        let parsed = SSHSessionCollector.parseSSHArgs(args)

        XCTAssertNil(parsed.user)
        XCTAssertEqual(parsed.host, "example.com")
        XCTAssertEqual(parsed.port, 22)
    }

    func testSSHParseWithPort() {
        let args = ["-p", "2222", "user@example.com"]
        let parsed = SSHSessionCollector.parseSSHArgs(args)

        XCTAssertEqual(parsed.user, "user")
        XCTAssertEqual(parsed.host, "example.com")
        XCTAssertEqual(parsed.port, 2222)
    }

    func testSSHParseWithIdentityFile() {
        let args = ["-i", "/Users/dev/.ssh/id_ed25519", "admin@server.local"]
        let parsed = SSHSessionCollector.parseSSHArgs(args)

        XCTAssertEqual(parsed.user, "admin")
        XCTAssertEqual(parsed.host, "server.local")
        XCTAssertEqual(parsed.identityFile, "/Users/dev/.ssh/id_ed25519")
    }

    func testSSHParseWithTunnels() {
        let args = [
            "-L", "8080:localhost:80",
            "-R", "9090:localhost:9090",
            "-D", "1080",
            "user@jumpbox.example.com"
        ]
        let parsed = SSHSessionCollector.parseSSHArgs(args)

        XCTAssertEqual(parsed.user, "user")
        XCTAssertEqual(parsed.host, "jumpbox.example.com")
        XCTAssertEqual(parsed.tunnels.count, 3)
        XCTAssertEqual(parsed.tunnels[0], .local("8080:localhost:80"))
        XCTAssertEqual(parsed.tunnels[1], .remote("9090:localhost:9090"))
        XCTAssertEqual(parsed.tunnels[2], .dynamic("1080"))
    }

    func testSSHParseWithUserFlag() {
        let args = ["-l", "admin", "server.example.com"]
        let parsed = SSHSessionCollector.parseSSHArgs(args)

        XCTAssertEqual(parsed.user, "admin")
        XCTAssertEqual(parsed.host, "server.example.com")
    }

    func testSSHParseComplexArgs() {
        let args = [
            "-o", "StrictHostKeyChecking=no",
            "-p", "2222",
            "-i", "/Users/dev/.ssh/key",
            "-L", "3306:db.internal:3306",
            "deploy@prod-bastion.example.com"
        ]
        let parsed = SSHSessionCollector.parseSSHArgs(args)

        XCTAssertEqual(parsed.user, "deploy")
        XCTAssertEqual(parsed.host, "prod-bastion.example.com")
        XCTAssertEqual(parsed.port, 2222)
        XCTAssertEqual(parsed.identityFile, "/Users/dev/.ssh/key")
        XCTAssertEqual(parsed.tunnels.count, 1)
        XCTAssertEqual(parsed.tunnels[0], .local("3306:db.internal:3306"))
    }

    func testSSHParseEmptyArgs() {
        let args: [String] = []
        let parsed = SSHSessionCollector.parseSSHArgs(args)

        XCTAssertNil(parsed.user)
        XCTAssertNil(parsed.host)
        XCTAssertEqual(parsed.port, 22)
        XCTAssertTrue(parsed.tunnels.isEmpty)
    }

    func testSSHSessionConnectionString() {
        let session = SSHSession(pid: 100, user: "admin", host: "server.com", port: 22)
        XCTAssertEqual(session.connectionString, "admin@server.com")

        let sessionWithPort = SSHSession(pid: 101, user: "root", host: "10.0.0.1", port: 2222)
        XCTAssertEqual(sessionWithPort.connectionString, "root@10.0.0.1:2222")

        let sessionNoUser = SSHSession(pid: 102, user: nil, host: "gateway.local", port: 22)
        XCTAssertEqual(sessionNoUser.connectionString, "gateway.local")
    }

    func testSSHTunnelDisplayString() {
        XCTAssertEqual(SSHTunnel.local("8080:localhost:80").displayString, "L:8080:localhost:80")
        XCTAssertEqual(SSHTunnel.remote("9090:localhost:9090").displayString, "R:9090:localhost:9090")
        XCTAssertEqual(SSHTunnel.dynamic("1080").displayString, "D:1080")
    }

    // MARK: - Tailscale JSON Decoding Tests

    func testTailscaleStatusDecoding() throws {
        let json = """
        {
            "Self": {
                "HostName": "my-mac",
                "DNSName": "my-mac.tail12345.ts.net.",
                "TailscaleIPs": ["100.100.1.1", "fd7a:115c:a1e0::1"],
                "OS": "macOS",
                "Online": true
            },
            "Peer": {
                "nodekey:abc123": {
                    "HostName": "linux-server",
                    "DNSName": "linux-server.tail12345.ts.net.",
                    "TailscaleIPs": ["100.100.1.2"],
                    "OS": "linux",
                    "Online": true,
                    "CurAddr": "192.168.1.50:41641",
                    "Relay": null,
                    "ExitNode": false
                },
                "nodekey:def456": {
                    "HostName": "iphone",
                    "DNSName": "iphone.tail12345.ts.net.",
                    "TailscaleIPs": ["100.100.1.3"],
                    "OS": "iOS",
                    "Online": false,
                    "LastSeen": "2026-02-22T10:00:00Z",
                    "CurAddr": null,
                    "Relay": "nyc",
                    "ExitNode": false
                }
            },
            "CurrentTailnet": {
                "Name": "user@example.com",
                "MagicDNSSuffix": "tail12345.ts.net"
            }
        }
        """
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let status = try decoder.decode(TailscaleStatus.self, from: data)

        XCTAssertEqual(status.selfNode.hostName, "my-mac")
        XCTAssertEqual(status.selfNode.tailscaleIPs.count, 2)
        XCTAssertTrue(status.selfNode.online)
        XCTAssertEqual(status.selfNode.os, "macOS")

        XCTAssertEqual(status.peers.count, 2)

        let linuxPeer = status.peers["nodekey:abc123"]
        XCTAssertNotNil(linuxPeer)
        XCTAssertEqual(linuxPeer?.hostName, "linux-server")
        XCTAssertTrue(linuxPeer?.online ?? false)
        XCTAssertTrue(linuxPeer?.isDirect ?? false)
        XCTAssertEqual(linuxPeer?.osIcon, "server.rack")

        let iphonePeer = status.peers["nodekey:def456"]
        XCTAssertNotNil(iphonePeer)
        XCTAssertEqual(iphonePeer?.hostName, "iphone")
        XCTAssertFalse(iphonePeer?.online ?? true)
        XCTAssertEqual(iphonePeer?.osIcon, "iphone")

        XCTAssertNotNil(status.currentTailnet)
        XCTAssertEqual(status.currentTailnet?.name, "user@example.com")
        XCTAssertEqual(status.currentTailnet?.magicDNSSuffix, "tail12345.ts.net")
    }

    func testTailscaleSortedPeers() throws {
        let json = """
        {
            "Self": {
                "HostName": "my-mac",
                "DNSName": "my-mac.ts.net.",
                "TailscaleIPs": ["100.100.1.1"],
                "OS": "macOS",
                "Online": true
            },
            "Peer": {
                "nodekey:1": {
                    "HostName": "zzz-offline",
                    "DNSName": "zzz.ts.net.",
                    "TailscaleIPs": ["100.100.1.4"],
                    "OS": "linux",
                    "Online": false,
                    "ExitNode": false
                },
                "nodekey:2": {
                    "HostName": "aaa-online",
                    "DNSName": "aaa.ts.net.",
                    "TailscaleIPs": ["100.100.1.2"],
                    "OS": "macOS",
                    "Online": true,
                    "ExitNode": false
                },
                "nodekey:3": {
                    "HostName": "bbb-online",
                    "DNSName": "bbb.ts.net.",
                    "TailscaleIPs": ["100.100.1.3"],
                    "OS": "windows",
                    "Online": true,
                    "ExitNode": false
                }
            }
        }
        """
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let status = try decoder.decode(TailscaleStatus.self, from: data)

        let sorted = status.sortedPeers
        XCTAssertEqual(sorted.count, 3)
        // Online peers first, sorted by hostname
        XCTAssertEqual(sorted[0].hostName, "aaa-online")
        XCTAssertEqual(sorted[1].hostName, "bbb-online")
        // Offline last
        XCTAssertEqual(sorted[2].hostName, "zzz-offline")
    }

    func testTailscalePeerOSIcons() {
        let icons: [(String, String)] = [
            ("macOS", "desktopcomputer"),
            ("darwin", "desktopcomputer"),
            ("iOS", "iphone"),
            ("android", "apps.iphone"),
            ("windows", "pc"),
            ("linux", "server.rack"),
            ("freebsd", "network"),
        ]

        for (os, expectedIcon) in icons {
            let peer = TailscalePeer(
                hostName: "test", dnsName: "test.ts.net.",
                tailscaleIPs: ["100.100.1.1"], os: os,
                online: true
            )
            XCTAssertEqual(peer.osIcon, expectedIcon, "OS '\(os)' should have icon '\(expectedIcon)'")
        }
    }

    // MARK: - WiFi Snapshot Tests

    func testWiFiSignalQuality() {
        // SNR of 25 dB -> 50% quality
        let snapshot = WiFiSnapshot(
            ssid: "TestNet", bssid: "AA:BB:CC:DD:EE:FF",
            channel: 36, band: "5 GHz",
            rssi: -55, noiseMeasurement: -80,
            snr: 25, txRate: 866.0,
            security: "WPA2 Personal",
            countryCode: "US", interfaceName: "en0"
        )
        XCTAssertEqual(snapshot.signalQuality, 50)
    }

    func testWiFiSignalQualityExtremes() {
        // Very high SNR (capped at 40)
        let excellent = WiFiSnapshot(
            ssid: "Strong", bssid: "00:00:00:00:00:00",
            channel: 1, band: "2.4 GHz",
            rssi: -30, noiseMeasurement: -90,
            snr: 60, txRate: 100.0,
            security: "WPA3", countryCode: "US", interfaceName: "en0"
        )
        XCTAssertEqual(excellent.signalQuality, 100)

        // Very low SNR (capped at 10)
        let terrible = WiFiSnapshot(
            ssid: "Weak", bssid: "00:00:00:00:00:00",
            channel: 11, band: "2.4 GHz",
            rssi: -90, noiseMeasurement: -92,
            snr: 2, txRate: 6.0,
            security: "Open", countryCode: "US", interfaceName: "en0"
        )
        XCTAssertEqual(terrible.signalQuality, 0)
    }

    func testWiFiSignalBars() {
        // RSSI thresholds: -50..0 = 4 bars, -60..-50 = 3, -70..-60 = 2, -80..-70 = 1, else = 0
        let makeSnapshot: (Int) -> WiFiSnapshot = { rssi in
            WiFiSnapshot(
                ssid: "Test", bssid: "", channel: 1, band: "2.4 GHz",
                rssi: rssi, noiseMeasurement: -90, snr: rssi + 90,
                txRate: 100, security: "WPA2", countryCode: nil, interfaceName: "en0"
            )
        }

        XCTAssertEqual(makeSnapshot(-45).signalBars, 4)
        XCTAssertEqual(makeSnapshot(-50).signalBars, 4)
        XCTAssertEqual(makeSnapshot(-55).signalBars, 3)
        XCTAssertEqual(makeSnapshot(-65).signalBars, 2)
        XCTAssertEqual(makeSnapshot(-75).signalBars, 1)
        XCTAssertEqual(makeSnapshot(-85).signalBars, 0)
    }

    // MARK: - Speed Test Output Parsing Tests

    func testSpeedTestOutputParsing() throws {
        let json = """
        {
            "dl_throughput": 250000000,
            "ul_throughput": 50000000,
            "responsiveness": 850,
            "dl_flows": 16,
            "ul_flows": 16,
            "base_rtt": 12
        }
        """
        let data = json.data(using: .utf8)!
        let result = try SpeedTestRunner.parseOutput(data)

        XCTAssertEqual(result.downloadMbps, 250.0, accuracy: 0.01)
        XCTAssertEqual(result.uploadMbps, 50.0, accuracy: 0.01)
        XCTAssertEqual(result.rpm, 850)
    }

    func testSpeedTestOutputMinimalJSON() throws {
        let json = """
        {
            "dl_throughput": 100000000,
            "ul_throughput": 20000000,
            "responsiveness": 400
        }
        """
        let data = json.data(using: .utf8)!
        let result = try SpeedTestRunner.parseOutput(data)

        XCTAssertEqual(result.downloadMbps, 100.0, accuracy: 0.01)
        XCTAssertEqual(result.uploadMbps, 20.0, accuracy: 0.01)
        XCTAssertEqual(result.rpm, 400)
    }

    func testSpeedTestOutputEmptyData() {
        let data = Data()
        XCTAssertThrowsError(try SpeedTestRunner.parseOutput(data)) { error in
            XCTAssertTrue(error is SpeedTestError)
            if case SpeedTestError.emptyOutput = error {
                // Expected
            } else {
                XCTFail("Expected SpeedTestError.emptyOutput")
            }
        }
    }

    func testSpeedTestOutputInvalidJSON() {
        let data = "not json".data(using: .utf8)!
        XCTAssertThrowsError(try SpeedTestRunner.parseOutput(data))
    }

    func testSpeedTestResponsivenessQuality() {
        let low = SpeedTestResult(downloadMbps: 10, uploadMbps: 5, rpm: 100, timestamp: Date())
        XCTAssertEqual(low.responsivenessQuality, "Low")

        let moderate = SpeedTestResult(downloadMbps: 50, uploadMbps: 25, rpm: 350, timestamp: Date())
        XCTAssertEqual(moderate.responsivenessQuality, "Moderate")

        let good = SpeedTestResult(downloadMbps: 100, uploadMbps: 50, rpm: 650, timestamp: Date())
        XCTAssertEqual(good.responsivenessQuality, "Good")

        let high = SpeedTestResult(downloadMbps: 500, uploadMbps: 200, rpm: 1000, timestamp: Date())
        XCTAssertEqual(high.responsivenessQuality, "High")

        let excellent = SpeedTestResult(downloadMbps: 1000, uploadMbps: 500, rpm: 1500, timestamp: Date())
        XCTAssertEqual(excellent.responsivenessQuality, "Excellent")
    }

    // MARK: - Listening Port Tests

    func testListeningPortServiceNames() {
        let httpPort = ListeningPort(port: 80, protocolName: "TCP", pid: 1, processName: "httpd",
                                     address: "0.0.0.0", isExposed: true)
        XCTAssertEqual(httpPort.serviceName, "HTTP")

        let sshPort = ListeningPort(port: 22, protocolName: "TCP", pid: 2, processName: "sshd",
                                    address: "0.0.0.0", isExposed: true)
        XCTAssertEqual(sshPort.serviceName, "SSH")

        let postgresPort = ListeningPort(port: 5432, protocolName: "TCP", pid: 3, processName: "postgres",
                                         address: "127.0.0.1", isExposed: false)
        XCTAssertEqual(postgresPort.serviceName, "PostgreSQL")

        let unknownPort = ListeningPort(port: 12345, protocolName: "TCP", pid: 4, processName: "myapp",
                                        address: "127.0.0.1", isExposed: false)
        XCTAssertNil(unknownPort.serviceName)
    }

    func testListeningPortExposureFlag() {
        let exposed = ListeningPort(port: 3000, protocolName: "TCP", pid: 1, processName: "node",
                                    address: "0.0.0.0", isExposed: true)
        XCTAssertTrue(exposed.isExposed)

        let local = ListeningPort(port: 3000, protocolName: "TCP", pid: 1, processName: "node",
                                  address: "127.0.0.1", isExposed: false)
        XCTAssertFalse(local.isExposed)
    }

    func testListeningPortIdentity() {
        let port1 = ListeningPort(port: 8080, protocolName: "TCP", pid: 100, processName: "node",
                                  address: "0.0.0.0", isExposed: true)
        let port2 = ListeningPort(port: 8080, protocolName: "UDP", pid: 100, processName: "node",
                                  address: "0.0.0.0", isExposed: true)
        // Different protocols should produce different IDs
        XCTAssertNotEqual(port1.id, port2.id)
    }

    // MARK: - Mock Collector Tests

    func testMockSSHCollector() async {
        let mock = MockSSHSessionCollector()
        mock.mockSessions = [
            SSHSession(pid: 100, user: "admin", host: "server.com"),
            SSHSession(pid: 101, user: "root", host: "db.internal", port: 2222)
        ]

        await mock.activate()
        let sessions = await mock.collectSessions()
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[0].host, "server.com")
        XCTAssertEqual(sessions[1].port, 2222)
        XCTAssertEqual(mock.activateCount, 1)
    }

    func testMockTailscaleCollector() async {
        let mock = MockTailscaleCollector()

        // No status set -- should return nil
        let nilStatus = await mock.collectStatus()
        XCTAssertNil(nilStatus)

        // Set mock status
        mock.mockStatus = TailscaleStatus(
            selfNode: TailscaleSelf(
                hostName: "test-mac", dnsName: "test-mac.ts.net.",
                tailscaleIPs: ["100.100.1.1"], os: "macOS", online: true
            ),
            peers: [:]
        )

        await mock.activate()
        let status = await mock.collectStatus()
        XCTAssertNotNil(status)
        XCTAssertEqual(status?.selfNode.hostName, "test-mac")
        XCTAssertEqual(mock.activateCount, 1)
    }

    func testMockWiFiCollector() async {
        let mock = MockWiFiCollector()
        mock.mockSnapshot = WiFiSnapshot(
            ssid: "TestNet", bssid: "AA:BB:CC:DD:EE:FF",
            channel: 36, band: "5 GHz",
            rssi: -55, noiseMeasurement: -80,
            snr: 25, txRate: 866.0,
            security: "WPA2 Personal",
            countryCode: "US", interfaceName: "en0"
        )

        await mock.activate()
        let snapshot = await mock.collectSnapshot()
        XCTAssertNotNil(snapshot)
        XCTAssertEqual(snapshot?.ssid, "TestNet")
        XCTAssertEqual(snapshot?.signalBars, 3)
    }

    func testMockSpeedTestRunner() async throws {
        let mock = MockSpeedTestRunner()
        mock.mockResult = SpeedTestResult(
            downloadMbps: 500.0, uploadMbps: 100.0, rpm: 1200, timestamp: Date()
        )

        let result = try await mock.run()
        XCTAssertEqual(result.downloadMbps, 500.0)
        XCTAssertEqual(result.uploadMbps, 100.0)
        XCTAssertEqual(result.rpm, 1200)
        XCTAssertEqual(mock.runCount, 1)
    }

    func testMockSpeedTestRunnerError() async {
        let mock = MockSpeedTestRunner()
        mock.mockError = SpeedTestError.timeout

        do {
            _ = try await mock.run()
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(error is SpeedTestError)
        }
    }

    func testMockListeningPortsCollector() async {
        let mock = MockListeningPortsCollector()
        mock.mockPorts = [
            ListeningPort(port: 8080, protocolName: "TCP", pid: 100,
                         processName: "node", address: "0.0.0.0", isExposed: true),
            ListeningPort(port: 5432, protocolName: "TCP", pid: 200,
                         processName: "postgres", address: "127.0.0.1", isExposed: false),
        ]

        await mock.activate()
        let ports = await mock.collectListeningPorts()
        XCTAssertEqual(ports.count, 2)
        XCTAssertTrue(ports[0].isExposed)
        XCTAssertFalse(ports[1].isExposed)
        XCTAssertEqual(mock.activateCount, 1)
    }
}
