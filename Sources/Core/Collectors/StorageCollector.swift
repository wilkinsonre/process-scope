import Foundation
import IOKit
import os

// MARK: - Storage Snapshot Types

/// Status of a volume's SMART health diagnostics
public enum SMARTStatus: String, Codable, Sendable {
    case healthy
    case failing
    case unknown
}

/// Connection interface type for a storage device
public enum StorageInterfaceType: String, Codable, Sendable {
    case nvmeInternal = "NVMe (Internal)"
    case thunderbolt = "Thunderbolt"
    case usb = "USB"
    case sata = "SATA"
    case sdCard = "SD Card"
    case network = "Network"
    case diskImage = "Disk Image"
    case unknown = "Unknown"

    /// SF Symbol representing this interface type
    public var symbolName: String {
        switch self {
        case .nvmeInternal: return "internaldrive.fill"
        case .thunderbolt: return "bolt.horizontal.fill"
        case .usb: return "cable.connector"
        case .sata: return "internaldrive"
        case .sdCard: return "sdcard"
        case .network: return "externaldrive.connected.to.line.below"
        case .diskImage: return "doc.zipper"
        case .unknown: return "questionmark.circle"
        }
    }

    /// Theoretical maximum bandwidth in bytes per second
    public var theoreticalBandwidth: UInt64? {
        switch self {
        case .nvmeInternal: return 7_000_000_000    // ~7 GB/s (M-series)
        case .thunderbolt: return 5_000_000_000     // ~5 GB/s (TB4)
        case .usb: return 1_250_000_000             // ~1.25 GB/s (USB 3.2 Gen 2x2)
        case .sata: return 600_000_000              // ~600 MB/s (SATA III)
        case .sdCard: return 312_000_000            // ~312 MB/s (UHS-II)
        case .network: return nil
        case .diskImage: return nil
        case .unknown: return nil
        }
    }
}

/// Snapshot of a single mounted volume
public struct VolumeSnapshot: Codable, Sendable, Identifiable {
    public var id: String { mountPoint }

    /// Display name of the volume
    public let name: String

    /// Absolute mount point path
    public let mountPoint: String

    /// Total capacity in bytes
    public let totalBytes: UInt64

    /// Available capacity in bytes
    public let freeBytes: UInt64

    /// Used capacity in bytes
    public var usedBytes: UInt64 { totalBytes > freeBytes ? totalBytes - freeBytes : 0 }

    /// Usage fraction (0.0 to 1.0)
    public var usageFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }

    /// File system type (APFS, HFS+, ExFAT, etc.)
    public let fileSystemType: String

    /// Connection interface for the underlying device
    public let interfaceType: StorageInterfaceType

    /// Whether the volume is removable (external USB, SD card, etc.)
    public let isRemovable: Bool

    /// Whether the volume is a network mount
    public let isNetwork: Bool

    /// Whether the volume is the system boot volume
    public let isBootVolume: Bool

    /// Whether the volume is encrypted (APFS encryption, FileVault)
    public let isEncrypted: Bool

    /// SMART health status for the underlying device
    public let smartStatus: SMARTStatus

    /// Whether the volume is ready to be safely ejected
    public let isEjectable: Bool

    /// BSD device name (e.g. "disk0s1")
    public let bsdName: String?
}

/// Time Machine backup status
public enum TimeMachineState: Codable, Sendable, Equatable {
    case idle(lastBackup: Date?)
    case backingUp(percent: Double)
    case unavailable
}

/// Complete storage snapshot for one collection cycle
public struct StorageSnapshot: Codable, Sendable {
    /// All mounted local volumes
    public let volumes: [VolumeSnapshot]

    /// Current Time Machine backup status
    public let timeMachineState: TimeMachineState

    /// Collection timestamp
    public let timestamp: Date
}

// MARK: - Storage Collector Protocol

/// Protocol for storage data collection (enables mocking)
public protocol StorageCollecting: SystemCollector {
    /// Collects a complete storage snapshot
    func collect() async -> StorageSnapshot
}

// MARK: - Storage Collector

/// Expanded storage data collector using FileManager, IOKit, and tmutil.
///
/// Collects per-volume information including capacity, file system type,
/// connection interface, SMART status, encryption, and Time Machine state.
/// Registered with ``StorageModule`` on the slow (10s) and infrequent (60s) polling tiers.
public actor StorageCollector: StorageCollecting {
    public nonisolated let id = "storage"
    public nonisolated let displayName = "Storage"
    public nonisolated let requiresHelper = false
    public nonisolated var isAvailable: Bool { true }

    private let logger = Logger(subsystem: "com.processscope", category: "StorageCollector")
    private var _isActive = false

    public init() {}

    public func activate() {
        _isActive = true
        logger.info("StorageCollector activated")
    }

    public func deactivate() {
        _isActive = false
        logger.info("StorageCollector deactivated")
    }

    // MARK: - Collection

    /// Collects snapshot of all mounted local volumes and Time Machine status
    public func collect() async -> StorageSnapshot {
        guard _isActive else {
            return StorageSnapshot(volumes: [], timeMachineState: .unavailable, timestamp: Date())
        }

        let volumes = collectVolumes()
        let tmState = collectTimeMachineStatus()

        return StorageSnapshot(
            volumes: volumes,
            timeMachineState: tmState,
            timestamp: Date()
        )
    }

    // MARK: - Volume Discovery

    private func collectVolumes() -> [VolumeSnapshot] {
        let keys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeIsRemovableKey,
            .volumeIsLocalKey,
            .volumeIsEjectableKey,
            .volumeIsRootFileSystemKey,
            .volumeLocalizedFormatDescriptionKey,
            .volumeSupportsFileCloningKey,
        ]

        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(keys),
            options: []
        ) else {
            logger.warning("Failed to enumerate mounted volumes")
            return []
        }

        var snapshots: [VolumeSnapshot] = []

        for url in urls {
            guard let values = try? url.resourceValues(forKeys: keys) else { continue }

            let mountPoint = url.path
            let name = values.volumeName ?? url.lastPathComponent
            let total = UInt64(values.volumeTotalCapacity ?? 0)
            let free = UInt64(values.volumeAvailableCapacity ?? 0)
            let isRemovable = values.volumeIsRemovable ?? false
            let isLocal = values.volumeIsLocal ?? true
            let isEjectable = values.volumeIsEjectable ?? false
            let isBootVolume = values.volumeIsRootFileSystem ?? false

            // Skip pseudo-filesystems with zero capacity (devfs, etc.)
            if total == 0 && !isLocal { continue }

            let fsType = fileSystemType(for: mountPoint)
            let bsdName = bsdDeviceName(for: mountPoint)
            let interfaceType = isLocal ? detectInterface(bsdName: bsdName, mountPoint: mountPoint) : .network
            let encrypted = detectEncryption(mountPoint: mountPoint, fsType: fsType)
            let smart = isLocal ? detectSMARTStatus(bsdName: bsdName) : .unknown

            snapshots.append(VolumeSnapshot(
                name: name,
                mountPoint: mountPoint,
                totalBytes: total,
                freeBytes: free,
                fileSystemType: fsType,
                interfaceType: interfaceType,
                isRemovable: isRemovable,
                isNetwork: !isLocal,
                isBootVolume: isBootVolume,
                isEncrypted: encrypted,
                smartStatus: smart,
                isEjectable: isEjectable,
                bsdName: bsdName
            ))
        }

        return snapshots
    }

    // MARK: - File System Type

    private func fileSystemType(for mountPoint: String) -> String {
        var stat = statfs()
        guard statfs(mountPoint, &stat) == 0 else { return "Unknown" }
        return withUnsafePointer(to: &stat.f_fstypename) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: 16) { cStr in
                String(cString: cStr)
            }
        }
    }

    // MARK: - BSD Device Name

    private func bsdDeviceName(for mountPoint: String) -> String? {
        var stat = statfs()
        guard statfs(mountPoint, &stat) == 0 else { return nil }
        return withUnsafePointer(to: &stat.f_mntfromname) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { cStr in
                let raw = String(cString: cStr)
                // /dev/disk3s1 -> disk3s1
                if raw.hasPrefix("/dev/") {
                    return String(raw.dropFirst(5))
                }
                return nil
            }
        }
    }

    // MARK: - Interface Detection

    private func detectInterface(bsdName: String?, mountPoint: String) -> StorageInterfaceType {
        // Disk images mount from /dev/ but are backed by files
        if isDiskImage(mountPoint: mountPoint) {
            return .diskImage
        }

        guard let bsdName else { return .unknown }

        // Strip partition suffix (disk3s1 -> disk3)
        let baseName = stripPartition(bsdName)

        return IOKitWrapper.shared.storageInterfaceType(bsdName: baseName)
    }

    private func isDiskImage(mountPoint: String) -> Bool {
        // Check if the volume was mounted from a disk image (.dmg, .sparseimage, etc.)
        var stat = statfs()
        guard statfs(mountPoint, &stat) == 0 else { return false }
        let mntFrom = withUnsafePointer(to: &stat.f_mntfromname) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { cStr in
                String(cString: cStr)
            }
        }
        // Disk images use a virtual disk device but we can check mount flags
        // Checking f_flags for MNT_DONTBROWSE which is commonly set for DMGs
        let flags = stat.f_flags
        let isDontBrowse = (flags & UInt32(MNT_DONTBROWSE)) != 0
        // /dev/diskN where N is a high number could be a disk image
        // A definitive check would require DiskArbitration, but this is a reasonable heuristic
        return isDontBrowse && mntFrom.hasPrefix("/dev/disk")
    }

    /// Strips partition suffix from BSD name: "disk3s1" -> "disk3"
    private func stripPartition(_ bsdName: String) -> String {
        // Match pattern like "disk3s1" and extract "disk3"
        guard let sRange = bsdName.range(of: "s", options: .backwards) else { return bsdName }
        let afterS = bsdName[sRange.upperBound...]
        // Ensure everything after 's' is digits (it's a partition, not part of the disk name)
        if afterS.allSatisfy(\.isNumber) {
            return String(bsdName[..<sRange.lowerBound])
        }
        return bsdName
    }

    // MARK: - Encryption Detection

    private func detectEncryption(mountPoint: String, fsType: String) -> Bool {
        // APFS encrypted volumes can be detected via URLResourceKey
        let url = URL(fileURLWithPath: mountPoint)
        if let values = try? url.resourceValues(forKeys: [.volumeIsEncryptedKey]) {
            return values.volumeIsEncrypted ?? false
        }
        return false
    }

    // MARK: - SMART Status Detection

    private func detectSMARTStatus(bsdName: String?) -> SMARTStatus {
        guard let bsdName else { return .unknown }
        let baseName = stripPartition(bsdName)
        return IOKitWrapper.shared.smartStatus(bsdName: baseName)
    }

    // MARK: - Time Machine Status

    /// Parses Time Machine status by invoking `tmutil status`
    func collectTimeMachineStatus() -> TimeMachineState {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        task.arguments = ["status"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe() // Discard stderr

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            logger.debug("tmutil not available: \(error.localizedDescription)")
            return .unavailable
        }

        guard task.terminationStatus == 0 else {
            return .unavailable
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return .unavailable
        }

        return parseTimeMachineOutput(output)
    }

    /// Parses plist-style output from `tmutil status`
    func parseTimeMachineOutput(_ output: String) -> TimeMachineState {
        // tmutil status outputs a plist dictionary
        let isRunning = output.contains("Running = 1")

        if isRunning {
            let percent = extractTimeMachinePercent(from: output)
            return .backingUp(percent: percent)
        }

        // Try to get last backup date via tmutil latestbackup
        let lastBackup = lastTimeMachineBackupDate()
        return .idle(lastBackup: lastBackup)
    }

    private func extractTimeMachinePercent(from output: String) -> Double {
        // Look for "Percent = X.XXX" or "Percent = \"X.XXX\""
        let lines = output.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Percent =") || trimmed.hasPrefix("\"Percent\" =") {
                let parts = trimmed.components(separatedBy: "=")
                if parts.count >= 2 {
                    let valueStr = parts[1]
                        .trimmingCharacters(in: .whitespaces)
                        .replacingOccurrences(of: ";", with: "")
                        .replacingOccurrences(of: "\"", with: "")
                    if let value = Double(valueStr) {
                        return value
                    }
                }
            }
        }
        return 0
    }

    private func lastTimeMachineBackupDate() -> Date? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        task.arguments = ["latestbackup"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return nil
        }

        guard task.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            return nil
        }

        // The backup path contains the date: /Volumes/BackupDrive/Backups.backupdb/.../2024-01-15-120000
        // Extract the date component from the last path element
        let lastComponent = (path as NSString).lastPathComponent
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.date(from: lastComponent)
    }
}

// MARK: - Mock Storage Collector

/// Mock implementation for testing
public actor MockStorageCollector: StorageCollecting {
    public nonisolated let id = "storage-mock"
    public nonisolated let displayName = "Storage (Mock)"
    public nonisolated let requiresHelper = false
    public nonisolated var isAvailable: Bool { true }

    private var _isActive = false

    /// Configurable snapshot for testing
    public var mockSnapshot: StorageSnapshot

    public init(snapshot: StorageSnapshot? = nil) {
        self.mockSnapshot = snapshot ?? StorageSnapshot(
            volumes: [],
            timeMachineState: .unavailable,
            timestamp: Date()
        )
    }

    public func activate() {
        _isActive = true
    }

    public func deactivate() {
        _isActive = false
    }

    public func collect() async -> StorageSnapshot {
        guard _isActive else {
            return StorageSnapshot(volumes: [], timeMachineState: .unavailable, timestamp: Date())
        }
        return mockSnapshot
    }

    public func setMockSnapshot(_ snapshot: StorageSnapshot) {
        mockSnapshot = snapshot
    }
}
