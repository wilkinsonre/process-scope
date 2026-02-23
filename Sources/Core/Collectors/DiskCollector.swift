import Foundation
import os

/// Collects disk/storage metrics
public actor DiskCollector: SystemCollector {
    public nonisolated let id = "disk"
    public nonisolated let displayName = "Disk"
    public nonisolated let requiresHelper = false
    public nonisolated var isAvailable: Bool { true }

    private let logger = Logger(subsystem: "com.processscope", category: "DiskCollector")
    private var _isActive = false

    public init() {}

    public func activate() {
        _isActive = true
        logger.info("DiskCollector activated")
    }

    public func deactivate() {
        _isActive = false
        logger.info("DiskCollector deactivated")
    }

    // MARK: - Collection

    /// Information about a mounted volume
    public struct VolumeInfo: Sendable, Identifiable {
        public var id: String { mountPoint }
        public let mountPoint: String
        public let fileSystem: String
        public let totalBytes: UInt64
        public let freeBytes: UInt64
        public let usedBytes: UInt64
        public let isRemovable: Bool
        public let isNetwork: Bool
    }

    /// Collects information about all mounted (non-hidden) volumes
    public func collect() -> [VolumeInfo] {
        guard _isActive else { return [] }

        var volumes: [VolumeInfo] = []
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeIsRemovableKey, .volumeIsLocalKey]

        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) else {
            return []
        }

        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            let total = UInt64(values.volumeTotalCapacity ?? 0)
            let free = UInt64(values.volumeAvailableCapacity ?? 0)

            volumes.append(VolumeInfo(
                mountPoint: url.path,
                fileSystem: values.volumeName ?? url.lastPathComponent,
                totalBytes: total,
                freeBytes: free,
                usedBytes: total > free ? total - free : 0,
                isRemovable: values.volumeIsRemovable ?? false,
                isNetwork: !(values.volumeIsLocal ?? true)
            ))
        }
        return volumes
    }
}
