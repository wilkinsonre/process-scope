import Foundation
import os

// MARK: - Network Volume Snapshot Types

/// Protocol type for network-mounted volumes
public enum NetworkVolumeProtocol: String, Codable, Sendable {
    case smb = "SMB"
    case nfs = "NFS"
    case afp = "AFP"
    case webdav = "WebDAV"
    case unknown = "Unknown"

    /// SF Symbol representing this protocol type
    public var symbolName: String {
        switch self {
        case .smb: return "server.rack"
        case .nfs: return "externaldrive.connected.to.line.below"
        case .afp: return "apple.logo"
        case .webdav: return "globe"
        case .unknown: return "questionmark.circle"
        }
    }
}

/// Snapshot of a single network-mounted volume
public struct NetworkVolumeSnapshot: Codable, Sendable, Identifiable {
    public var id: String { mountPoint }

    /// Server hostname or IP address
    public let server: String

    /// Share or export name
    public let shareName: String

    /// Network file system protocol
    public let protocolType: NetworkVolumeProtocol

    /// Local mount point
    public let mountPoint: String

    /// Whether the volume is currently accessible
    public let isConnected: Bool

    /// Display name of the volume
    public let displayName: String

    /// Connection latency in milliseconds, if measured
    public let latencyMs: Double?

    /// Total capacity in bytes (may be zero if server does not report)
    public let totalBytes: UInt64

    /// Free capacity in bytes
    public let freeBytes: UInt64

    /// Used capacity in bytes
    public var usedBytes: UInt64 { totalBytes > freeBytes ? totalBytes - freeBytes : 0 }
}

/// Complete network volume collection snapshot
public struct NetworkVolumeCollectionSnapshot: Codable, Sendable {
    /// All discovered network volumes
    public let volumes: [NetworkVolumeSnapshot]

    /// Collection timestamp
    public let timestamp: Date
}

// MARK: - Network Volume Collector Protocol

/// Protocol for network volume data collection (enables mocking)
public protocol NetworkVolumeCollecting: SystemCollector {
    /// Collects network-mounted volume information
    func collect() async -> NetworkVolumeCollectionSnapshot
}

// MARK: - Network Volume Collector

/// Collects information about network-mounted volumes (SMB, NFS, AFP, WebDAV).
///
/// Uses `FileManager` and `statfs` to discover network mounts,
/// parses mount-from paths to extract server and share details,
/// and optionally measures connection latency.
public actor NetworkVolumeCollector: NetworkVolumeCollecting {
    public nonisolated let id = "network-volumes"
    public nonisolated let displayName = "Network Volumes"
    public nonisolated let requiresHelper = false
    public nonisolated var isAvailable: Bool { true }

    private let logger = Logger(subsystem: "com.processscope", category: "NetworkVolumeCollector")
    private var _isActive = false

    public init() {}

    public func activate() {
        _isActive = true
        logger.info("NetworkVolumeCollector activated")
    }

    public func deactivate() {
        _isActive = false
        logger.info("NetworkVolumeCollector deactivated")
    }

    // MARK: - Collection

    /// Collects all network-mounted volumes
    public func collect() async -> NetworkVolumeCollectionSnapshot {
        guard _isActive else {
            return NetworkVolumeCollectionSnapshot(volumes: [], timestamp: Date())
        }

        let volumes = collectNetworkVolumes()
        return NetworkVolumeCollectionSnapshot(volumes: volumes, timestamp: Date())
    }

    // MARK: - Network Volume Discovery

    private func collectNetworkVolumes() -> [NetworkVolumeSnapshot] {
        let keys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeIsLocalKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
        ]

        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(keys),
            options: []
        ) else {
            return []
        }

        var snapshots: [NetworkVolumeSnapshot] = []

        for url in urls {
            guard let values = try? url.resourceValues(forKeys: keys) else { continue }
            let isLocal = values.volumeIsLocal ?? true
            guard !isLocal else { continue }

            let mountPoint = url.path
            let displayName = values.volumeName ?? url.lastPathComponent

            // Parse mount source to extract server and share
            let mountInfo = parseMountSource(for: mountPoint)
            guard let info = mountInfo else { continue }

            let total = UInt64(values.volumeTotalCapacity ?? 0)
            let free = UInt64(values.volumeAvailableCapacity ?? 0)

            // Measure connection status by checking accessibility
            let isConnected = FileManager.default.isReadableFile(atPath: mountPoint)

            snapshots.append(NetworkVolumeSnapshot(
                server: info.server,
                shareName: info.share,
                protocolType: info.protocolType,
                mountPoint: mountPoint,
                isConnected: isConnected,
                displayName: displayName,
                latencyMs: nil, // Latency measurement deferred to avoid blocking
                totalBytes: total,
                freeBytes: free
            ))
        }

        return snapshots
    }

    // MARK: - Mount Source Parsing

    /// Parsed mount source info
    private struct MountSourceInfo {
        let server: String
        let share: String
        let protocolType: NetworkVolumeProtocol
    }

    /// Parses the f_mntfromname field to extract server, share, and protocol.
    ///
    /// Common formats:
    /// - SMB: `//user@server/share` or `//server/share`
    /// - NFS: `server:/export/path`
    /// - AFP: `afp_server:share`
    private func parseMountSource(for mountPoint: String) -> MountSourceInfo? {
        var stat = statfs()
        guard statfs(mountPoint, &stat) == 0 else { return nil }

        let mntFrom = withUnsafePointer(to: &stat.f_mntfromname) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { cStr in
                String(cString: cStr)
            }
        }

        let fsType = withUnsafePointer(to: &stat.f_fstypename) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: 16) { cStr in
                String(cString: cStr)
            }
        }

        let protocolType = detectProtocol(fsType: fsType)

        switch protocolType {
        case .smb:
            return parseSMBSource(mntFrom)
        case .nfs:
            return parseNFSSource(mntFrom)
        case .afp:
            return parseAFPSource(mntFrom)
        case .webdav:
            return parseWebDAVSource(mntFrom)
        case .unknown:
            return MountSourceInfo(server: mntFrom, share: "", protocolType: .unknown)
        }
    }

    private func detectProtocol(fsType: String) -> NetworkVolumeProtocol {
        switch fsType.lowercased() {
        case "smbfs": return .smb
        case "nfs": return .nfs
        case "afpfs": return .afp
        case "webdav": return .webdav
        default: return .unknown
        }
    }

    /// Parses SMB mount source: `//user@server/share` or `//server/share`
    private func parseSMBSource(_ source: String) -> MountSourceInfo {
        var cleaned = source
        if cleaned.hasPrefix("//") {
            cleaned = String(cleaned.dropFirst(2))
        }

        // Strip user@ prefix if present
        if let atIndex = cleaned.firstIndex(of: "@") {
            cleaned = String(cleaned[cleaned.index(after: atIndex)...])
        }

        // Split on first slash: server/share
        let components = cleaned.split(separator: "/", maxSplits: 1)
        let server = components.first.map(String.init) ?? cleaned
        let share = components.count > 1 ? String(components[1]) : ""

        return MountSourceInfo(server: server, share: share, protocolType: .smb)
    }

    /// Parses NFS mount source: `server:/export/path`
    private func parseNFSSource(_ source: String) -> MountSourceInfo {
        let components = source.split(separator: ":", maxSplits: 1)
        let server = components.first.map(String.init) ?? source
        let share = components.count > 1 ? String(components[1]) : ""

        return MountSourceInfo(server: server, share: share, protocolType: .nfs)
    }

    /// Parses AFP mount source
    private func parseAFPSource(_ source: String) -> MountSourceInfo {
        var cleaned = source
        if cleaned.hasPrefix("afp://") {
            cleaned = String(cleaned.dropFirst(6))
        }

        // Strip user@ prefix if present
        if let atIndex = cleaned.firstIndex(of: "@") {
            cleaned = String(cleaned[cleaned.index(after: atIndex)...])
        }

        let components = cleaned.split(separator: "/", maxSplits: 1)
        let server = components.first.map(String.init) ?? cleaned
        let share = components.count > 1 ? String(components[1]) : ""

        return MountSourceInfo(server: server, share: share, protocolType: .afp)
    }

    /// Parses WebDAV mount source
    private func parseWebDAVSource(_ source: String) -> MountSourceInfo {
        // WebDAV URLs: http(s)://server/path
        var cleaned = source
        for prefix in ["https://", "http://"] {
            if cleaned.hasPrefix(prefix) {
                cleaned = String(cleaned.dropFirst(prefix.count))
                break
            }
        }

        let components = cleaned.split(separator: "/", maxSplits: 1)
        let server = components.first.map(String.init) ?? cleaned
        let share = components.count > 1 ? String(components[1]) : ""

        return MountSourceInfo(server: server, share: share, protocolType: .webdav)
    }
}

// MARK: - Mock Network Volume Collector

/// Mock implementation for testing
public actor MockNetworkVolumeCollector: NetworkVolumeCollecting {
    public nonisolated let id = "network-volumes-mock"
    public nonisolated let displayName = "Network Volumes (Mock)"
    public nonisolated let requiresHelper = false
    public nonisolated var isAvailable: Bool { true }

    private var _isActive = false

    /// Configurable snapshot for testing
    public var mockSnapshot: NetworkVolumeCollectionSnapshot

    public init(snapshot: NetworkVolumeCollectionSnapshot? = nil) {
        self.mockSnapshot = snapshot ?? NetworkVolumeCollectionSnapshot(
            volumes: [],
            timestamp: Date()
        )
    }

    public func activate() {
        _isActive = true
    }

    public func deactivate() {
        _isActive = false
    }

    public func collect() async -> NetworkVolumeCollectionSnapshot {
        guard _isActive else {
            return NetworkVolumeCollectionSnapshot(volumes: [], timestamp: Date())
        }
        return mockSnapshot
    }

    public func setMockSnapshot(_ snapshot: NetworkVolumeCollectionSnapshot) {
        mockSnapshot = snapshot
    }
}
