import Foundation
import IOKit
import os

/// Centralized wrapper for all IOKit and IOReport access.
/// This is the ONLY file that touches semi-private IOReport APIs.
public final class IOKitWrapper: @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.processscope", category: "IOKitWrapper")

    public static let shared = IOKitWrapper()

    private init() {}

    // MARK: - GPU Metrics

    /// Returns GPU utilization percentage (0-100)
    public func gpuUtilization() -> Double? {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOAccelerator")

        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        let service = IOIteratorNext(iterator)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = properties?.takeRetainedValue() as? [String: Any],
              let perfStats = dict["PerformanceStatistics"] as? [String: Any] else {
            return nil
        }

        if let utilization = perfStats["GPU Activity(%)"] as? Double {
            return utilization
        }
        if let deviceUtil = perfStats["Device Utilization %"] as? Int {
            return Double(deviceUtil)
        }
        return nil
    }

    // MARK: - GPU Power (stub — IOReport needed for real values)

    public func gpuPowerWatts() -> Double? {
        // Requires IOReport subscription — stub for now
        Self.logger.debug("GPU power: IOReport not yet implemented")
        return nil
    }

    // MARK: - ANE Power (stub)

    public func anePowerWatts() -> Double? {
        Self.logger.debug("ANE power: IOReport not yet implemented")
        return nil
    }

    // MARK: - Thermal

    public func thermalState() -> Int {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return 0
        case .fair: return 1
        case .serious: return 2
        case .critical: return 3
        @unknown default: return 0
        }
    }

    // MARK: - Fan Speed (if available)

    public func fanSpeedRPM() -> Int? {
        // Apple Silicon Macs with fans expose this via IOKit SMC
        // Stub for now
        return nil
    }

    // MARK: - Battery Info

    public struct BatteryInfo: Sendable {
        public let currentCapacity: Int
        public let maxCapacity: Int
        public let designCapacity: Int
        public let cycleCount: Int
        public let isCharging: Bool
        public let isPluggedIn: Bool
        public let temperature: Double // Celsius
        public let voltage: Double // mV
    }

    public func batteryInfo() -> BatteryInfo? {
        let matching = IOServiceMatching("AppleSmartBattery")
        var service: io_service_t = 0
        service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = properties?.takeRetainedValue() as? [String: Any] else {
            return nil
        }

        guard let currentCap = dict["CurrentCapacity"] as? Int,
              let maxCap = dict["MaxCapacity"] as? Int else {
            return nil
        }

        return BatteryInfo(
            currentCapacity: currentCap,
            maxCapacity: maxCap,
            designCapacity: dict["DesignCapacity"] as? Int ?? maxCap,
            cycleCount: dict["CycleCount"] as? Int ?? 0,
            isCharging: dict["IsCharging"] as? Bool ?? false,
            isPluggedIn: dict["ExternalConnected"] as? Bool ?? false,
            temperature: Double(dict["Temperature"] as? Int ?? 0) / 100.0,
            voltage: Double(dict["Voltage"] as? Int ?? 0)
        )
    }
}
