import Foundation
import os

// MARK: - Tailscale Data Types

/// Status of the local Tailscale node and its peer network
public struct TailscaleStatus: Codable, Sendable {
    /// The local node
    public let selfNode: TailscaleSelf
    /// Peer map keyed by peer public key
    public let peers: [String: TailscalePeer]
    /// Current tailnet info (nil if not connected)
    public let currentTailnet: TailnetInfo?

    enum CodingKeys: String, CodingKey {
        case selfNode = "Self"
        case peers = "Peer"
        case currentTailnet = "CurrentTailnet"
    }

    public init(selfNode: TailscaleSelf, peers: [String: TailscalePeer],
                currentTailnet: TailnetInfo? = nil) {
        self.selfNode = selfNode
        self.peers = peers
        self.currentTailnet = currentTailnet
    }

    /// Returns all peers sorted by online status then hostname
    public var sortedPeers: [TailscalePeer] {
        peers.values.sorted { lhs, rhs in
            if lhs.online != rhs.online { return lhs.online && !rhs.online }
            return lhs.hostName.localizedCaseInsensitiveCompare(rhs.hostName) == .orderedAscending
        }
    }
}

/// The local Tailscale node information
public struct TailscaleSelf: Codable, Sendable {
    public let hostName: String
    public let dnsName: String
    public let tailscaleIPs: [String]
    public let os: String
    public let online: Bool

    enum CodingKeys: String, CodingKey {
        case hostName = "HostName"
        case dnsName = "DNSName"
        case tailscaleIPs = "TailscaleIPs"
        case os = "OS"
        case online = "Online"
    }

    public init(hostName: String, dnsName: String, tailscaleIPs: [String],
                os: String, online: Bool) {
        self.hostName = hostName
        self.dnsName = dnsName
        self.tailscaleIPs = tailscaleIPs
        self.os = os
        self.online = online
    }
}

/// A peer device on the Tailscale network
public struct TailscalePeer: Codable, Sendable, Identifiable {
    public var id: String { dnsName }
    public let hostName: String
    public let dnsName: String
    public let tailscaleIPs: [String]
    public let os: String
    public let online: Bool
    public let lastSeen: Date?
    public let curAddr: String?
    public let relay: String?
    public let exitNode: Bool

    enum CodingKeys: String, CodingKey {
        case hostName = "HostName"
        case dnsName = "DNSName"
        case tailscaleIPs = "TailscaleIPs"
        case os = "OS"
        case online = "Online"
        case lastSeen = "LastSeen"
        case curAddr = "CurAddr"
        case relay = "Relay"
        case exitNode = "ExitNode"
    }

    public init(hostName: String, dnsName: String, tailscaleIPs: [String],
                os: String, online: Bool, lastSeen: Date? = nil,
                curAddr: String? = nil, relay: String? = nil, exitNode: Bool = false) {
        self.hostName = hostName
        self.dnsName = dnsName
        self.tailscaleIPs = tailscaleIPs
        self.os = os
        self.online = online
        self.lastSeen = lastSeen
        self.curAddr = curAddr
        self.relay = relay
        self.exitNode = exitNode
    }

    /// SF Symbol name for the peer's operating system
    public var osIcon: String {
        switch os.lowercased() {
        case "macos", "darwin": return "desktopcomputer"
        case "ios": return "iphone"
        case "android": return "apps.iphone"
        case "windows": return "pc"
        case "linux": return "server.rack"
        default: return "network"
        }
    }

    /// Whether this peer is connected directly (not via DERP relay)
    public var isDirect: Bool { curAddr != nil && relay == nil }
}

/// Information about the current tailnet
public struct TailnetInfo: Codable, Sendable {
    public let name: String
    public let magicDNSSuffix: String

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case magicDNSSuffix = "MagicDNSSuffix"
    }

    public init(name: String, magicDNSSuffix: String) {
        self.name = name
        self.magicDNSSuffix = magicDNSSuffix
    }
}

// MARK: - Tailscale Collector Protocol

/// Protocol for Tailscale data collection, enabling mock injection for tests
public protocol TailscaleCollecting: AnyObject, Sendable {
    func collectStatus() async -> TailscaleStatus?
}

// MARK: - Tailscale Collector

/// Queries the Tailscale local API to retrieve VPN status and peer information.
///
/// Before making API calls, verifies that:
/// 1. The `tailscaled` process is running
/// 2. The 100.100.100.100 Tailscale service IP is reachable
///
/// Subscribes to the Extended polling tier (3s). Returns nil if Tailscale
/// is not installed or not running.
public actor TailscaleCollector: SystemCollector, TailscaleCollecting {
    public nonisolated let id = "tailscale"
    public nonisolated let displayName = "Tailscale"
    public nonisolated let requiresHelper = false
    public nonisolated var isAvailable: Bool { true }

    private let logger = Logger(subsystem: "com.processscope", category: "TailscaleCollector")
    private var _isActive = false
    private var urlSession: URLSession?

    /// The Tailscale local API base URL
    private static let baseURL = URL(string: "http://100.100.100.100/localapi/v0/")!

    public init() {}

    public func activate() {
        _isActive = true
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2
        config.timeoutIntervalForResource = 5
        config.waitsForConnectivity = false
        urlSession = URLSession(configuration: config)
        logger.info("TailscaleCollector activated")
    }

    public func deactivate() {
        _isActive = false
        urlSession?.invalidateAndCancel()
        urlSession = nil
        logger.info("TailscaleCollector deactivated")
    }

    // MARK: - Collection

    /// Collects the current Tailscale status, or nil if Tailscale is unavailable
    public func collectStatus() async -> TailscaleStatus? {
        guard _isActive else { return nil }
        guard isTailscaleDaemonRunning() else {
            logger.debug("tailscaled not running, skipping Tailscale collection")
            return nil
        }

        guard let session = urlSession else { return nil }

        let url = Self.baseURL.appendingPathComponent("status")
        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                logger.warning("Tailscale API returned non-200 status")
                return nil
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(TailscaleStatus.self, from: data)
        } catch is CancellationError {
            return nil
        } catch {
            logger.debug("Tailscale API call failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Daemon Detection

    /// Checks whether the tailscaled process is currently running
    private func isTailscaleDaemonRunning() -> Bool {
        let allProcs = SysctlWrapper.allProcesses()
        for kinfo in allProcs {
            let pid = kinfo.kp_proc.p_pid
            guard pid > 0 else { continue }
            if let name = LibProcWrapper.processName(for: pid),
               name == "tailscaled" {
                return true
            }
        }
        return false
    }
}

// MARK: - Mock Tailscale Collector

/// Mock collector for testing Tailscale UI without a running Tailscale instance
public final class MockTailscaleCollector: TailscaleCollecting, SystemCollector, @unchecked Sendable {
    public let id = "tailscale-mock"
    public let displayName = "Tailscale (Mock)"
    public let requiresHelper = false
    public var isAvailable: Bool = true

    public var mockStatus: TailscaleStatus?
    public private(set) var activateCount = 0
    public private(set) var deactivateCount = 0

    public init() {}

    public func activate() async { activateCount += 1 }
    public func deactivate() async { deactivateCount += 1 }

    public func collectStatus() async -> TailscaleStatus? { mockStatus }
}
