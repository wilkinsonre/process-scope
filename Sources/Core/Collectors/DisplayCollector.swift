import Foundation
import CoreGraphics
import AppKit
import os

// MARK: - Display Info

/// Information about a single connected display
public struct DisplayInfo: Codable, Sendable, Identifiable, Equatable {
    /// Unique identifier derived from the CoreGraphics display ID
    public var id: UInt32 { displayID }

    /// CoreGraphics display identifier
    public let displayID: UInt32

    /// Display name (e.g. "Built-in Retina Display", "LG UltraFine 5K")
    public let name: String

    /// Logical width in points
    public let width: Int

    /// Logical height in points
    public let height: Int

    /// Pixel width (backing store)
    public let pixelWidth: Int

    /// Pixel height (backing store)
    public let pixelHeight: Int

    /// Current refresh rate in Hz
    public let refreshRate: Double

    /// Display scale factor (e.g. 2.0 for Retina)
    public let scaleFactor: Double

    /// Color profile name, nil if unavailable
    public let colorProfileName: String?

    /// Whether this is the built-in display (MacBook panel)
    public let isBuiltIn: Bool

    /// Whether this is the main (primary) display
    public let isMain: Bool

    /// Whether this display supports HDR (extended dynamic range)
    public let isHDR: Bool

    public init(
        displayID: UInt32,
        name: String,
        width: Int,
        height: Int,
        pixelWidth: Int,
        pixelHeight: Int,
        refreshRate: Double,
        scaleFactor: Double,
        colorProfileName: String?,
        isBuiltIn: Bool,
        isMain: Bool,
        isHDR: Bool
    ) {
        self.displayID = displayID
        self.name = name
        self.width = width
        self.height = height
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.refreshRate = refreshRate
        self.scaleFactor = scaleFactor
        self.colorProfileName = colorProfileName
        self.isBuiltIn = isBuiltIn
        self.isMain = isMain
        self.isHDR = isHDR
    }

    /// Human-readable resolution string (e.g. "2560 x 1600")
    public var resolutionString: String {
        "\(width) x \(height)"
    }

    /// Human-readable pixel resolution string (e.g. "5120 x 3200")
    public var pixelResolutionString: String {
        "\(pixelWidth) x \(pixelHeight)"
    }

    /// Human-readable refresh rate (e.g. "120 Hz" or "ProMotion")
    public var refreshRateString: String {
        if refreshRate == 0 {
            return "Unknown"
        }
        let hz = Int(refreshRate)
        return "\(hz) Hz"
    }
}

// MARK: - Display Snapshot

/// A point-in-time snapshot of all connected displays
public struct DisplaySnapshot: Codable, Sendable {
    /// All active displays
    public let displays: [DisplayInfo]

    /// Timestamp of collection
    public let timestamp: Date

    public init(displays: [DisplayInfo] = [], timestamp: Date = Date()) {
        self.displays = displays
        self.timestamp = timestamp
    }

    /// Number of connected displays
    public var displayCount: Int { displays.count }

    /// The main (primary) display, if any
    public var mainDisplay: DisplayInfo? {
        displays.first(where: \.isMain)
    }

    /// External displays only
    public var externalDisplays: [DisplayInfo] {
        displays.filter { !$0.isBuiltIn }
    }
}

// MARK: - Display Collector Protocol

/// Protocol for display collection, enabling mock injection for tests
public protocol DisplayCollecting: SystemCollector, Sendable {
    /// Collects a snapshot of all connected displays
    func collect() async -> DisplaySnapshot
}

// MARK: - Display Collector

/// Collects display information using CoreGraphics and NSScreen APIs
///
/// Uses `CGGetActiveDisplayList` to enumerate displays, `CGDisplayCopyDisplayMode`
/// for refresh rate and pixel dimensions, and `NSScreen` for scale factor and
/// color space information.
///
/// Registered with ``DisplayModule`` on the slow (10s) polling tier.
public actor DisplayCollector: DisplayCollecting {
    public nonisolated let id = "display"
    public nonisolated let displayName = "Display"
    public nonisolated let requiresHelper = false
    public nonisolated var isAvailable: Bool { true }

    private let logger = Logger(subsystem: "com.processscope", category: "DisplayCollector")
    private var _isActive = false

    public init() {}

    public func activate() {
        _isActive = true
        logger.info("DisplayCollector activated")
    }

    public func deactivate() {
        _isActive = false
        logger.info("DisplayCollector deactivated")
    }

    // MARK: - Collection

    /// Collect a snapshot of all connected displays
    public func collect() async -> DisplaySnapshot {
        guard _isActive else {
            return DisplaySnapshot()
        }

        // NSScreen must be accessed on the main actor
        let screenInfos = await MainActor.run {
            Self.gatherScreenInfo()
        }

        var displays: [DisplayInfo] = []

        var displayIDs = [CGDirectDisplayID](repeating: 0, count: 16)
        var displayCount: UInt32 = 0
        let result = CGGetActiveDisplayList(16, &displayIDs, &displayCount)

        guard result == .success else {
            logger.warning("CGGetActiveDisplayList failed with status \(result.rawValue)")
            return DisplaySnapshot(timestamp: Date())
        }

        for i in 0..<Int(displayCount) {
            let cgID = displayIDs[i]

            let bounds = CGDisplayBounds(cgID)
            let logicalWidth = Int(bounds.width)
            let logicalHeight = Int(bounds.height)

            var pixelWidth = logicalWidth
            var pixelHeight = logicalHeight
            var refreshRate: Double = 0

            if let mode = CGDisplayCopyDisplayMode(cgID) {
                pixelWidth = mode.pixelWidth
                pixelHeight = mode.pixelHeight
                refreshRate = mode.refreshRate
            }

            let isBuiltIn = CGDisplayIsBuiltin(cgID) != 0
            let isMain = CGDisplayIsMain(cgID) != 0

            // Find matching NSScreen info
            let screenInfo = screenInfos.first { $0.displayID == cgID }

            let scaleFactor = screenInfo?.scaleFactor ?? (logicalWidth > 0 ? Double(pixelWidth) / Double(logicalWidth) : 1.0)
            let colorProfile = screenInfo?.colorSpaceName
            let name = screenInfo?.localizedName ?? (isBuiltIn ? "Built-in Display" : "External Display")
            let isHDR = screenInfo?.isHDR ?? false

            displays.append(DisplayInfo(
                displayID: cgID,
                name: name,
                width: logicalWidth,
                height: logicalHeight,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight,
                refreshRate: refreshRate,
                scaleFactor: scaleFactor,
                colorProfileName: colorProfile,
                isBuiltIn: isBuiltIn,
                isMain: isMain,
                isHDR: isHDR
            ))
        }

        return DisplaySnapshot(displays: displays, timestamp: Date())
    }

    // MARK: - NSScreen Info Gathering

    /// Information gathered from NSScreen (must be accessed on MainActor)
    private struct ScreenInfo: Sendable {
        let displayID: CGDirectDisplayID
        let scaleFactor: Double
        let colorSpaceName: String?
        let localizedName: String
        let isHDR: Bool
    }

    /// Gathers display information from NSScreen (must be called on MainActor)
    @MainActor
    private static func gatherScreenInfo() -> [ScreenInfo] {
        NSScreen.screens.compactMap { screen in
            guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                return nil
            }

            let colorSpaceName = screen.colorSpace?.localizedName
            let isHDR = screen.maximumExtendedDynamicRangeColorComponentValue > 1.0

            return ScreenInfo(
                displayID: screenNumber,
                scaleFactor: screen.backingScaleFactor,
                colorSpaceName: colorSpaceName,
                localizedName: screen.localizedName,
                isHDR: isHDR
            )
        }
    }
}

// MARK: - Mock Display Collector

/// Mock display collector for testing
public final class MockDisplayCollector: DisplayCollecting, @unchecked Sendable {
    public let id = "display-mock"
    public let displayName = "Display (Mock)"
    public let requiresHelper = false
    public var isAvailable: Bool = true

    public var mockSnapshot: DisplaySnapshot = DisplaySnapshot()
    public private(set) var activateCount = 0
    public private(set) var deactivateCount = 0

    public init() {}

    public func activate() async { activateCount += 1 }
    public func deactivate() async { deactivateCount += 1 }

    public func collect() async -> DisplaySnapshot {
        mockSnapshot
    }
}
