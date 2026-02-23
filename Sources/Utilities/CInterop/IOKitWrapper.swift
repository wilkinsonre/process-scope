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

    // MARK: - Per-Component Power

    /// Per-component power breakdown in watts.
    /// All fields are optional since IOReport may not expose every metric on all hardware.
    public struct ComponentPower: Codable, Sendable {
        /// Total CPU package power in watts (includes E-cores + P-cores)
        public let cpuPackage: Double?
        /// Efficiency core cluster power in watts
        public let eCores: Double?
        /// Performance core cluster power in watts
        public let pCores: Double?
        /// GPU power in watts
        public let gpu: Double?
        /// Apple Neural Engine power in watts
        public let ane: Double?
        /// DRAM power in watts
        public let dram: Double?

        public init(
            cpuPackage: Double? = nil,
            eCores: Double? = nil,
            pCores: Double? = nil,
            gpu: Double? = nil,
            ane: Double? = nil,
            dram: Double? = nil
        ) {
            self.cpuPackage = cpuPackage
            self.eCores = eCores
            self.pCores = pCores
            self.gpu = gpu
            self.ane = ane
            self.dram = dram
        }

        /// Total of all non-nil component power values in watts
        public var totalWatts: Double {
            let values: [Double?] = [cpuPackage, gpu, ane, dram]
            return values.compactMap { $0 }.reduce(0, +)
        }

        /// Returns named breakdown pairs for UI rendering, filtering nil components
        public var breakdown: [(name: String, watts: Double)] {
            var result: [(String, Double)] = []
            if let v = cpuPackage { result.append(("CPU", v)) }
            if let v = gpu { result.append(("GPU", v)) }
            if let v = ane { result.append(("ANE", v)) }
            if let v = dram { result.append(("DRAM", v)) }
            return result
        }
    }

    /// Reads per-component power from IOReport channels.
    /// Returns nil if IOReport is unavailable on this hardware.
    ///
    /// On Apple Silicon, power data is exposed via IOReport channel groups:
    /// - "Energy Model" for CPU/GPU/ANE/DRAM power
    /// - Individual cluster channels for E-core and P-core breakdown
    ///
    /// This implementation reads from IOKit registry properties as a fallback
    /// when full IOReport subscription is not available.
    public func perComponentPower() -> ComponentPower? {
        // Attempt to read power metrics from IOReport-derived IOKit properties.
        // On Apple Silicon, the AppleARMIODevice "pmgr" service often exposes
        // power telemetry that mirrors IOReport channel data.
        let gpuPower = gpuPowerFromAccelerator()
        let cpuPower = cpuPowerFromPMGR()

        // If we got nothing from any source, return nil
        if gpuPower == nil && cpuPower == nil {
            Self.logger.debug("Per-component power: no IOReport data available")
            return nil
        }

        return ComponentPower(
            cpuPackage: cpuPower,
            eCores: nil,
            pCores: nil,
            gpu: gpuPower,
            ane: anePowerFromIOKit(),
            dram: dramPowerFromIOKit()
        )
    }

    /// Reads GPU power from IOAccelerator PerformanceStatistics if available
    private func gpuPowerFromAccelerator() -> Double? {
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

        // GPU power in milliwatts on some Apple Silicon variants
        if let powerMW = perfStats["GPU Power"] as? Int {
            return Double(powerMW) / 1000.0
        }
        if let powerMW = perfStats["GPU Energy(mJ)"] as? Int {
            // Energy per sample period; approximate watts from most recent delta
            return Double(powerMW) / 1000.0
        }
        return nil
    }

    /// Reads CPU package power from power manager IOKit service
    private func cpuPowerFromPMGR() -> Double? {
        // Try AppleARMIODevice for power telemetry
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleARMIODevice")
        )
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = properties?.takeRetainedValue() as? [String: Any] else {
            return nil
        }

        if let cpuMW = dict["CPU Power"] as? Int {
            return Double(cpuMW) / 1000.0
        }
        return nil
    }

    /// Reads ANE power from IOKit if available
    private func anePowerFromIOKit() -> Double? {
        // ANE power is typically only available via full IOReport subscription.
        // Return nil for now; will be populated when IOReport wrapper is complete.
        return nil
    }

    /// Reads DRAM power from IOKit if available
    private func dramPowerFromIOKit() -> Double? {
        // DRAM power is typically only available via full IOReport subscription.
        // Return nil for now; will be populated when IOReport wrapper is complete.
        return nil
    }

    // MARK: - CPU Frequency

    /// CPU frequency information for throttle detection
    public struct CPUFrequency: Codable, Sendable {
        /// Current CPU frequency in MHz (0 if unavailable)
        public let currentMHz: Double
        /// Maximum CPU frequency in MHz (0 if unavailable)
        public let maxMHz: Double

        public init(currentMHz: Double, maxMHz: Double) {
            self.currentMHz = currentMHz
            self.maxMHz = maxMHz
        }

        /// True if current frequency is below 90% of max, indicating throttling
        public var isThrottled: Bool {
            guard maxMHz > 0 else { return false }
            return currentMHz < maxMHz * 0.9
        }

        /// Ratio of current to max frequency (0.0 to 1.0)
        public var frequencyRatio: Double {
            guard maxMHz > 0 else { return 0 }
            return min(currentMHz / maxMHz, 1.0)
        }
    }

    /// Returns current CPU frequency information from sysctl.
    /// Uses hw.cpufrequency and hw.cpufrequency_max when available.
    /// Returns nil if frequency data cannot be read.
    public func cpuFrequency() -> CPUFrequency? {
        let currentHz = sysctlInt64ByName("hw.cpufrequency") ?? sysctlInt64ByName("hw.tbfrequency")
        let maxHz = sysctlInt64ByName("hw.cpufrequency_max")

        // On Apple Silicon, hw.cpufrequency may not be available.
        // Fall back to hw.tbfrequency (timebase frequency) as a rough indicator,
        // though it is not the actual CPU clock.
        guard let current = currentHz else {
            Self.logger.debug("CPU frequency: sysctl hw.cpufrequency unavailable")
            return nil
        }

        let currentMHz = Double(current) / 1_000_000.0
        let maxMHz: Double
        if let max = maxHz {
            maxMHz = Double(max) / 1_000_000.0
        } else {
            // If max is unavailable, use current as max (no throttle detection)
            maxMHz = currentMHz
        }

        return CPUFrequency(currentMHz: currentMHz, maxMHz: maxMHz)
    }

    /// Helper to read a 64-bit integer from sysctl by name
    private func sysctlInt64ByName(_ name: String) -> Int64? {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        let result = sysctlbyname(name, &value, &size, nil, 0)
        guard result == 0 else { return nil }
        return value
    }

    // MARK: - Temperature Readings

    /// Reads CPU die temperature in Celsius from SMC via IOKit.
    /// Returns nil if temperature data is unavailable (e.g., no SMC access).
    public func cpuDieTemperature() -> Double? {
        return readSMCTemperature(key: "TC0P") ?? readSMCTemperature(key: "Tc0a")
    }

    /// Reads GPU die temperature in Celsius from SMC via IOKit.
    /// Returns nil if temperature data is unavailable.
    public func gpuDieTemperature() -> Double? {
        return readSMCTemperature(key: "TG0P") ?? readSMCTemperature(key: "Tg0a")
    }

    /// Reads a temperature value from SMC via the AppleSMC IOKit service.
    /// SMC temperature keys are 4-character codes (e.g., "TC0P" for CPU proximity).
    /// Returns nil if the key is not available or SMC cannot be accessed.
    private func readSMCTemperature(key: String) -> Double? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSMC")
        )
        guard service != 0 else {
            Self.logger.debug("SMC service not found for temperature key \(key)")
            return nil
        }
        defer { IOObjectRelease(service) }

        // SMC requires a connection and specific calls that are semi-private.
        // For now, return nil and log. Full SMC implementation would require
        // the helper daemon with elevated privileges.
        Self.logger.debug("SMC temperature read for \(key): requires helper daemon")
        return nil
    }

    // MARK: - GPU Power (IOReport stub)

    /// Returns GPU power in watts from IOReport channels.
    /// Falls back to IOAccelerator PerformanceStatistics if IOReport unavailable.
    public func gpuPowerWatts() -> Double? {
        return gpuPowerFromAccelerator()
    }

    // MARK: - ANE Power (IOReport stub)

    /// Returns Apple Neural Engine power in watts.
    /// Currently returns nil; will be populated when IOReport wrapper is complete.
    public func anePowerWatts() -> Double? {
        return anePowerFromIOKit()
    }

    // MARK: - Thermal

    /// Returns thermal state as integer (0=nominal, 1=fair, 2=serious, 3=critical)
    public func thermalState() -> Int {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return 0
        case .fair: return 1
        case .serious: return 2
        case .critical: return 3
        @unknown default: return 0
        }
    }

    /// Returns string description for a thermal state value
    public static func thermalStateDescription(_ state: Int) -> String {
        switch state {
        case 0: return "Nominal"
        case 1: return "Fair"
        case 2: return "Serious"
        case 3: return "Critical"
        default: return "Unknown"
        }
    }

    // MARK: - Fan Speed (if available)

    /// Returns fan speed in RPM if a fan is present.
    /// Returns nil on fanless Macs (MacBook Air, etc.).
    public func fanSpeedRPM() -> Int? {
        // Apple Silicon Macs with fans expose this via IOKit SMC.
        // Requires helper daemon for SMC access; stub for now.
        return nil
    }

    // MARK: - Storage Interface Detection

    /// Determines the connection interface type for a storage device by walking
    /// the IOKit registry tree from the IOMedia node up through transport layers.
    ///
    /// - Parameter bsdName: The BSD device name without partition suffix (e.g. "disk3")
    /// - Returns: The detected ``StorageInterfaceType``
    public func storageInterfaceType(bsdName: String) -> StorageInterfaceType {
        let matching = IOServiceMatching("IOMedia") as NSMutableDictionary
        matching["BSD Name"] = bsdName

        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else {
            Self.logger.debug("IOMedia not found for BSD name: \(bsdName)")
            return .unknown
        }
        defer { IOObjectRelease(service) }

        // Walk the parent chain in the IOService plane to find transport type
        var current = service
        IOObjectRetain(current) // Retain because we'll release in the loop
        defer {
            if current != service {
                IOObjectRelease(current)
            }
        }

        var parent: io_registry_entry_t = 0
        while IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS {
            if current != service {
                IOObjectRelease(current)
            }
            current = parent

            var className = [CChar](repeating: 0, count: 128)
            IOObjectGetClass(current, &className)
            let name = String(cString: className)

            if name.contains("NVMe") || name.contains("AppleANS") {
                return .nvmeInternal
            }
            if name.contains("Thunderbolt") {
                return .thunderbolt
            }
            if name.contains("USB") {
                return .usb
            }
            if name.contains("AHCI") || name.contains("SATA") {
                return .sata
            }
            if name.contains("SDXC") || name.contains("SDCard") || name.contains("CardReader") {
                return .sdCard
            }
        }

        return .unknown
    }

    /// Reads SMART health status for a storage device from IOKit registry.
    ///
    /// Checks the IOBlockStorageDevice entry for SMART Status properties.
    /// Returns `.unknown` if SMART data is not available for the device.
    ///
    /// - Parameter bsdName: The BSD device name without partition suffix (e.g. "disk0")
    /// - Returns: The SMART health status
    public func smartStatus(bsdName: String) -> SMARTStatus {
        let matching = IOServiceMatching("IOMedia") as NSMutableDictionary
        matching["BSD Name"] = bsdName

        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return .unknown }
        defer { IOObjectRelease(service) }

        // Walk up to find the IOBlockStorageDevice parent
        var current = service
        IOObjectRetain(current)

        var parent: io_registry_entry_t = 0
        while IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS {
            if current != service {
                IOObjectRelease(current)
            }
            current = parent

            var className = [CChar](repeating: 0, count: 128)
            IOObjectGetClass(current, &className)
            let name = String(cString: className)

            if name.contains("IOBlockStorageDevice") || name.contains("IONVMeBlockStorageDevice") {
                var properties: Unmanaged<CFMutableDictionary>?
                if IORegistryEntryCreateCFProperties(current, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                   let dict = properties?.takeRetainedValue() as? [String: Any] {
                    if let status = dict["SMART Status"] as? String {
                        IOObjectRelease(current)
                        return status == "Verified" ? .healthy : .failing
                    }
                }
                IOObjectRelease(current)
                return .unknown
            }
        }

        if current != service {
            IOObjectRelease(current)
        }
        return .unknown
    }

    // MARK: - Battery Info (Enhanced)

    /// Comprehensive battery information from AppleSmartBattery IOKit service.
    /// All fields are populated from IOKit registry properties.
    public struct BatteryInfo: Codable, Sendable {
        /// Current charge capacity in mAh
        public let currentCapacity: Int
        /// Current maximum capacity in mAh (degrades over time)
        public let maxCapacity: Int
        /// Original design capacity in mAh
        public let designCapacity: Int
        /// Number of charge cycles
        public let cycleCount: Int
        /// Whether the battery is currently charging
        public let isCharging: Bool
        /// Whether external power is connected
        public let isPluggedIn: Bool
        /// Battery temperature in degrees Celsius
        public let temperature: Double
        /// Battery voltage in millivolts
        public let voltage: Double
        /// Estimated charge/discharge rate in watts (positive=charging, negative=discharging)
        public let chargeRateWatts: Double?
        /// Time remaining in minutes (charge or discharge, depending on state)
        public let timeRemainingMinutes: Int?
        /// Whether optimized battery charging is enabled
        public let optimizedChargingEnabled: Bool

        /// Charge level as percentage (0-100)
        public var chargePercent: Int {
            guard maxCapacity > 0 else { return 0 }
            return min(Int(Double(currentCapacity) / Double(maxCapacity) * 100), 100)
        }

        /// Battery health as a percentage of design capacity (0.0 to 1.0+)
        public var health: Double {
            guard designCapacity > 0 else { return 1.0 }
            return Double(maxCapacity) / Double(designCapacity)
        }

        /// Battery health as percentage string
        public var healthPercent: Double {
            return health * 100.0
        }

        public init(
            currentCapacity: Int,
            maxCapacity: Int,
            designCapacity: Int,
            cycleCount: Int,
            isCharging: Bool,
            isPluggedIn: Bool,
            temperature: Double,
            voltage: Double,
            chargeRateWatts: Double? = nil,
            timeRemainingMinutes: Int? = nil,
            optimizedChargingEnabled: Bool = false
        ) {
            self.currentCapacity = currentCapacity
            self.maxCapacity = maxCapacity
            self.designCapacity = designCapacity
            self.cycleCount = cycleCount
            self.isCharging = isCharging
            self.isPluggedIn = isPluggedIn
            self.temperature = temperature
            self.voltage = voltage
            self.chargeRateWatts = chargeRateWatts
            self.timeRemainingMinutes = timeRemainingMinutes
            self.optimizedChargingEnabled = optimizedChargingEnabled
        }
    }

    /// Reads comprehensive battery info from the AppleSmartBattery IOKit service.
    /// Returns nil on desktop Macs with no battery.
    public func batteryInfo() -> BatteryInfo? {
        let matching = IOServiceMatching("AppleSmartBattery")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
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

        // Calculate charge rate from amperage and voltage
        let amperage = dict["Amperage"] as? Int  // milliamps, negative when discharging
        let voltage = dict["Voltage"] as? Int ?? 0  // millivolts
        var chargeRate: Double?
        if let amps = amperage, voltage > 0 {
            // Power (W) = Voltage (V) * Current (A)
            chargeRate = (Double(voltage) / 1000.0) * (Double(amps) / 1000.0)
        }

        // Time remaining from AppleSmartBattery (minutes)
        let timeRemaining = dict["TimeRemaining"] as? Int
        let validTimeRemaining: Int?
        if let tr = timeRemaining, tr > 0, tr < 6000 {
            validTimeRemaining = tr
        } else {
            validTimeRemaining = nil
        }

        return BatteryInfo(
            currentCapacity: currentCap,
            maxCapacity: maxCap,
            designCapacity: dict["DesignCapacity"] as? Int ?? maxCap,
            cycleCount: dict["CycleCount"] as? Int ?? 0,
            isCharging: dict["IsCharging"] as? Bool ?? false,
            isPluggedIn: dict["ExternalConnected"] as? Bool ?? false,
            temperature: Double(dict["Temperature"] as? Int ?? 0) / 100.0,
            voltage: Double(voltage),
            chargeRateWatts: chargeRate,
            timeRemainingMinutes: validTimeRemaining,
            optimizedChargingEnabled: dict["OptimizedBatteryChargingEngaged"] as? Bool ?? false
        )
    }
}
