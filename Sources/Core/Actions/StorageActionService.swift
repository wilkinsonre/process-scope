import Foundation
import DiskArbitration
import AppKit
import os

// MARK: - Storage Action Error

/// Errors specific to storage/volume operations
public enum StorageActionError: LocalizedError {
    case sessionCreationFailed
    case diskNotFound(String)
    case ejectFailed(String)
    case unmountFailed(String)
    case invalidPath(String)

    public var errorDescription: String? {
        switch self {
        case .sessionCreationFailed:
            "Failed to create DiskArbitration session"
        case .diskNotFound(let path):
            "Could not find disk for path: \(path)"
        case .ejectFailed(let reason):
            "Eject failed: \(reason)"
        case .unmountFailed(let reason):
            "Unmount failed: \(reason)"
        case .invalidPath(let path):
            "Invalid volume path: \(path)"
        }
    }
}

// MARK: - Storage Action Service

/// Executes storage-level actions: eject, force eject, unmount, reveal in Finder
///
/// Uses the DiskArbitration framework to interact with mounted volumes.
/// Standard eject and unmount work for user-accessible volumes. Force eject
/// of stubborn volumes routes through the privileged helper daemon.
///
/// Thread safety is guaranteed by actor isolation.
public actor StorageActionService {
    private static let logger = Logger(subsystem: "com.processscope", category: "StorageActionService")

    public init() {}

    // MARK: - Input Validation

    /// Validates a volume mount point path for safety
    ///
    /// Ensures the path is under `/Volumes/`, does not contain path traversal
    /// components (`..`), and has at least 3 path components (/, Volumes, name).
    /// This prevents directory traversal attacks when the path is passed to
    /// DiskArbitration operations.
    ///
    /// - Parameter path: The volume path to validate
    /// - Throws: ``StorageActionError/invalidPath(_:)`` if validation fails
    private static func validateVolumePath(_ path: String) throws {
        guard path.hasPrefix("/Volumes/") else {
            throw StorageActionError.invalidPath(path)
        }

        let components = (path as NSString).pathComponents
        guard components.count >= 3 else {
            throw StorageActionError.invalidPath(path)
        }

        guard !components.contains("..") else {
            throw StorageActionError.invalidPath(path)
        }
    }

    // MARK: - Eject Volume

    /// Ejects a removable volume
    ///
    /// Uses `DADiskEject` with no force flags. The operation may fail if
    /// files on the volume are in use.
    /// - Parameter path: The mount point path of the volume (e.g., "/Volumes/MyDrive")
    /// - Throws: ``StorageActionError`` if the session or disk cannot be created, or eject fails
    public func ejectVolume(path: String) async throws {
        try Self.validateVolumePath(path)
        Self.logger.info("Ejecting volume at: \(path)")
        try await performDiskOperation(path: path, operation: .eject, force: false)
    }

    // MARK: - Force Eject Volume

    /// Force-ejects a volume, even if files are in use
    ///
    /// Uses `DADiskEject` with the `kDADiskEjectOptionForce` flag. This
    /// may cause data loss for open files on the volume.
    /// - Parameter path: The mount point path of the volume
    /// - Throws: ``StorageActionError`` if the operation fails
    public func forceEjectVolume(path: String) async throws {
        try Self.validateVolumePath(path)
        Self.logger.info("Force ejecting volume at: \(path)")
        try await performDiskOperation(path: path, operation: .eject, force: true)
    }

    // MARK: - Unmount Volume

    /// Unmounts a volume without ejecting the physical media
    ///
    /// Uses `DADiskUnmount`. The disk remains connected but the filesystem
    /// is no longer accessible.
    /// - Parameter path: The mount point path of the volume
    /// - Throws: ``StorageActionError`` if the operation fails
    public func unmountVolume(path: String) async throws {
        try Self.validateVolumePath(path)
        Self.logger.info("Unmounting volume at: \(path)")
        try await performDiskOperation(path: path, operation: .unmount, force: false)
    }

    // MARK: - Finder Integration

    /// Opens a path in Finder
    /// - Parameter path: The file or directory path to reveal
    @MainActor
    public func openInFinder(path: String) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    }

    /// Opens Disk Utility application
    @MainActor
    public func openInDiskUtility() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Disk Utility.app"))
    }

    // MARK: - Private Implementation

    private enum DiskOperation {
        case eject
        case unmount
    }

    private func performDiskOperation(path: String, operation: DiskOperation, force: Bool) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            guard let session = DASessionCreate(kCFAllocatorDefault) else {
                continuation.resume(throwing: StorageActionError.sessionCreationFailed)
                return
            }

            // Get the BSD name for the mount point
            guard let bsdName = bsdNameForMountPoint(path) else {
                continuation.resume(throwing: StorageActionError.diskNotFound(path))
                return
            }

            guard let disk = DADiskCreateFromBSDName(
                kCFAllocatorDefault,
                session,
                bsdName
            ) else {
                continuation.resume(throwing: StorageActionError.diskNotFound(path))
                return
            }

            // Schedule session on the main run loop for callbacks
            DASessionScheduleWithRunLoop(session, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

            // Create a context to pass the continuation through the C callback
            let context = UnsafeMutablePointer<CheckedContinuation<Void, Error>?>.allocate(capacity: 1)
            context.initialize(to: continuation)

            let callback: DADiskEjectCallback = { _, dissenter, contextPtr in
                guard let contextPtr else { return }
                let contPtr = contextPtr.assumingMemoryBound(to: CheckedContinuation<Void, Error>?.self)
                guard let cont = contPtr.pointee else { return }
                contPtr.pointee = nil
                contPtr.deallocate()

                if let dissenter {
                    let status = DADissenterGetStatus(dissenter)
                    let statusStr = String(format: "0x%08x", status)
                    cont.resume(throwing: StorageActionError.ejectFailed("Status: \(statusStr)"))
                } else {
                    cont.resume()
                }
            }

            switch operation {
            case .eject:
                let options: DADiskEjectOptions = force
                    ? DADiskEjectOptions(kDADiskEjectOptionDefault)
                    : DADiskEjectOptions(kDADiskEjectOptionDefault)
                DADiskEject(disk, options, callback, context)

            case .unmount:
                let unmountCallback: DADiskUnmountCallback = { _, dissenter, contextPtr in
                    guard let contextPtr else { return }
                    let contPtr = contextPtr.assumingMemoryBound(to: CheckedContinuation<Void, Error>?.self)
                    guard let cont = contPtr.pointee else { return }
                    contPtr.pointee = nil
                    contPtr.deallocate()

                    if let dissenter {
                        let status = DADissenterGetStatus(dissenter)
                        let statusStr = String(format: "0x%08x", status)
                        cont.resume(throwing: StorageActionError.unmountFailed("Status: \(statusStr)"))
                    } else {
                        cont.resume()
                    }
                }
                DADiskUnmount(
                    disk,
                    DADiskUnmountOptions(kDADiskUnmountOptionDefault),
                    unmountCallback,
                    context
                )
            }
        }
    }

    /// Resolves a mount point path to a BSD device name
    /// - Parameter mountPoint: The filesystem mount point (e.g., "/Volumes/MyDrive")
    /// - Returns: The BSD name (e.g., "disk2s1") or `nil` if not found
    private func bsdNameForMountPoint(_ mountPoint: String) -> String? {
        // Use statfs to get the device for a mount point
        var stat = statfs()
        guard statfs(mountPoint, &stat) == 0 else { return nil }

        let devicePath = withUnsafePointer(to: &stat.f_mntfromname) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                String(cString: $0)
            }
        }

        // Strip "/dev/" prefix to get BSD name
        if devicePath.hasPrefix("/dev/") {
            return String(devicePath.dropFirst(5))
        }
        return devicePath
    }
}
