import Foundation
import IOBluetooth
import IOKit
import os

// MARK: - Bluetooth Device Type

/// Classification of a Bluetooth device by its function
public enum BluetoothDeviceType: String, Codable, Sendable, CaseIterable {
    case headphones
    case speaker
    case mouse
    case keyboard
    case trackpad
    case gamepad
    case other

    /// SF Symbol name for this device type
    public var symbolName: String {
        switch self {
        case .headphones: "headphones"
        case .speaker: "hifispeaker"
        case .mouse: "computermouse"
        case .keyboard: "keyboard"
        case .trackpad: "trackpad"
        case .gamepad: "gamecontroller"
        case .other: "wave.3.right"
        }
    }
}

// MARK: - AirPods Detail

/// Battery detail for AirPods (left, right, case)
public struct AirPodsDetail: Codable, Sendable, Equatable {
    /// Left earbud battery percentage (0-100), nil if unavailable
    public let leftBattery: Int?
    /// Right earbud battery percentage (0-100), nil if unavailable
    public let rightBattery: Int?
    /// Charging case battery percentage (0-100), nil if unavailable
    public let caseBattery: Int?

    public init(leftBattery: Int?, rightBattery: Int?, caseBattery: Int?) {
        self.leftBattery = leftBattery
        self.rightBattery = rightBattery
        self.caseBattery = caseBattery
    }
}

// MARK: - Bluetooth Device

/// Represents a single Bluetooth device with its properties
public struct BluetoothDevice: Codable, Sendable, Identifiable, Equatable {
    /// Unique identifier derived from the MAC address
    public var id: String { address }

    /// Device display name
    public let name: String

    /// MAC address string (e.g. "AA-BB-CC-DD-EE-FF")
    public let address: String

    /// Bluetooth device class code
    public let deviceClass: UInt32

    /// Classified device type based on device class
    public let deviceType: BluetoothDeviceType

    /// Overall battery level (0-100), nil if not reported
    public let batteryLevel: Int?

    /// RSSI in dBm, nil if not connected or unavailable
    public let rssi: Int?

    /// Whether the device is currently connected
    public let isConnected: Bool

    /// Whether the device is paired
    public let isPaired: Bool

    /// AirPods-specific battery breakdown, nil for non-AirPods
    public let airPodsDetail: AirPodsDetail?

    public init(
        name: String,
        address: String,
        deviceClass: UInt32,
        deviceType: BluetoothDeviceType,
        batteryLevel: Int?,
        rssi: Int?,
        isConnected: Bool,
        isPaired: Bool,
        airPodsDetail: AirPodsDetail?
    ) {
        self.name = name
        self.address = address
        self.deviceClass = deviceClass
        self.deviceType = deviceType
        self.batteryLevel = batteryLevel
        self.rssi = rssi
        self.isConnected = isConnected
        self.isPaired = isPaired
        self.airPodsDetail = airPodsDetail
    }
}

// MARK: - Bluetooth Snapshot

/// A point-in-time snapshot of Bluetooth state
public struct BluetoothSnapshot: Codable, Sendable {
    /// Devices that are currently connected
    public let connectedDevices: [BluetoothDevice]

    /// Devices that are paired but not currently connected
    public let pairedDisconnectedDevices: [BluetoothDevice]

    /// Whether Bluetooth hardware is enabled on this Mac
    public let isBluetoothEnabled: Bool

    /// Timestamp of collection
    public let timestamp: Date

    public init(
        connectedDevices: [BluetoothDevice] = [],
        pairedDisconnectedDevices: [BluetoothDevice] = [],
        isBluetoothEnabled: Bool = false,
        timestamp: Date = Date()
    ) {
        self.connectedDevices = connectedDevices
        self.pairedDisconnectedDevices = pairedDisconnectedDevices
        self.isBluetoothEnabled = isBluetoothEnabled
        self.timestamp = timestamp
    }
}

// MARK: - Bluetooth Collector Protocol

/// Protocol for Bluetooth collection, enabling mock injection for tests
public protocol BluetoothCollecting: SystemCollector, Sendable {
    func collect() async -> BluetoothSnapshot
}

// MARK: - Bluetooth Collector

/// Collects Bluetooth device information using IOBluetooth framework
public actor BluetoothCollector: BluetoothCollecting {
    public nonisolated let id = "bluetooth"
    public nonisolated let displayName = "Bluetooth"
    public nonisolated let requiresHelper = false
    public nonisolated var isAvailable: Bool { true }

    private let logger = Logger(subsystem: "com.processscope", category: "BluetoothCollector")
    private var _isActive = false

    public init() {
        // Do NOT call IOBluetoothDevice.pairedDevices() here.
        // That triggers a TCC Bluetooth permission check which will crash
        // if the user has not yet granted permission. Availability is checked
        // lazily on the first collect() call instead.
    }

    public func activate() {
        _isActive = true
        logger.info("BluetoothCollector activated")
    }

    public func deactivate() {
        _isActive = false
        logger.info("BluetoothCollector deactivated")
    }

    // MARK: - Collection

    /// Collect a snapshot of all Bluetooth devices
    public func collect() async -> BluetoothSnapshot {
        guard _isActive else {
            return BluetoothSnapshot()
        }

        // IOBluetoothDevice.pairedDevices() triggers a TCC Bluetooth permission check.
        // In test environments (xctest), TCC cannot present the permission dialog and
        // kills the process with SIGKILL. Skip IOBluetooth calls in that context.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              ProcessInfo.processInfo.environment["XCTestBundlePath"] == nil else {
            return BluetoothSnapshot(isBluetoothEnabled: false, timestamp: Date())
        }

        guard let pairedDevices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            logger.debug("IOBluetooth unavailable — returning empty snapshot")
            return BluetoothSnapshot(isBluetoothEnabled: false, timestamp: Date())
        }

        var connected: [BluetoothDevice] = []
        var disconnected: [BluetoothDevice] = []

        for device in pairedDevices {
            let name = device.name ?? "Unknown"
            let address = device.addressString ?? "00-00-00-00-00-00"
            let classOfDevice = device.classOfDevice
            let deviceType = Self.classifyDevice(classOfDevice: classOfDevice, name: name)
            let isConnected = device.isConnected()

            // Read battery level from IOKit registry
            let batteryLevel = Self.readBatteryLevel(for: device)

            // Detect AirPods and read per-component battery
            let airPodsDetail = Self.detectAirPods(device: device, name: name)

            // Read RSSI only for connected devices
            let rssi: Int? = isConnected ? Self.readRSSI(for: device) : nil

            let btDevice = BluetoothDevice(
                name: name,
                address: address,
                deviceClass: classOfDevice,
                deviceType: deviceType,
                batteryLevel: batteryLevel,
                rssi: rssi,
                isConnected: isConnected,
                isPaired: true,
                airPodsDetail: airPodsDetail
            )

            if isConnected {
                connected.append(btDevice)
            } else {
                disconnected.append(btDevice)
            }
        }

        return BluetoothSnapshot(
            connectedDevices: connected,
            pairedDisconnectedDevices: disconnected,
            isBluetoothEnabled: true,
            timestamp: Date()
        )
    }

    // MARK: - Device Classification

    /// Classify a Bluetooth device based on its Class of Device (CoD) code and name
    ///
    /// CoD bit layout:
    /// - Bits 12-8: Major Device Class
    /// - Bits 7-2: Minor Device Class
    public static func classifyDevice(classOfDevice: UInt32, name: String = "") -> BluetoothDeviceType {
        let majorClass = (classOfDevice >> 8) & 0x1F
        let minorClass = (classOfDevice >> 2) & 0x3F

        // Name-based heuristics for Apple devices that may not have proper CoD
        let lowercaseName = name.lowercased()
        if lowercaseName.contains("airpods") || lowercaseName.contains("beats") {
            return .headphones
        }
        if lowercaseName.contains("magic mouse") || lowercaseName.contains("mouse") {
            return .mouse
        }
        if lowercaseName.contains("magic keyboard") || lowercaseName.contains("keyboard") {
            return .keyboard
        }
        if lowercaseName.contains("magic trackpad") || lowercaseName.contains("trackpad") {
            return .trackpad
        }

        switch majorClass {
        case 0x04: // Audio/Video
            switch minorClass {
            case 0x01, 0x02, 0x06: return .headphones // Wearable headset / Hands-free / Headphones
            case 0x04, 0x05: return .speaker // Loudspeaker / HiFi Audio
            default: return .speaker
            }
        case 0x05: // Peripheral
            switch minorClass & 0x0F {
            case 0x01: return .keyboard // Keyboard (minor bits 0-3 of full minor)
            case 0x02: return .mouse // Pointing device
            case 0x03: return .trackpad // Combo keyboard/pointing — map to trackpad
            default: return .gamepad
            }
        case 0x01: // Computer — could be another Mac
            return .other
        case 0x02: // Phone
            return .other
        default:
            return .other
        }
    }

    // MARK: - Battery Reading

    /// Read the battery level from a Bluetooth device via IOKit registry
    private static func readBatteryLevel(for device: IOBluetoothDevice) -> Int? {
        guard let address = device.addressString else { return nil }

        // Search IOKit for the Bluetooth device's battery property
        let matching = IOServiceMatching("AppleDeviceManagementHIDEventService") as NSMutableDictionary
        var iterator: io_iterator_t = 0

        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = properties?.takeRetainedValue() as? [String: Any] else {
                continue
            }

            // Match by device address
            if let deviceAddr = dict["DeviceAddress"] as? String,
               deviceAddr.lowercased() == address.lowercased(),
               let battery = dict["BatteryPercent"] as? Int {
                return battery
            }
        }

        return nil
    }

    /// Read RSSI value for a connected Bluetooth device
    private static func readRSSI(for device: IOBluetoothDevice) -> Int? {
        // IOBluetoothDevice rawRSSI may not be accurate without an active L2CAP connection
        // Return the value if the device reports it, otherwise nil
        let rssi = device.rawRSSI()
        guard rssi != 127 else { return nil } // 127 means unavailable per BT spec
        return Int(rssi)
    }

    // MARK: - AirPods Detection

    /// Detect AirPods and read per-component battery (left, right, case)
    ///
    /// Apple exposes AirPods battery via IOKit keys:
    /// - BatteryPercentLeft, BatteryPercentRight, BatteryPercentCase
    private static func detectAirPods(device: IOBluetoothDevice, name: String) -> AirPodsDetail? {
        guard name.lowercased().contains("airpods") else { return nil }
        guard let address = device.addressString else { return nil }

        let matching = IOServiceMatching("AppleDeviceManagementHIDEventService") as NSMutableDictionary
        var iterator: io_iterator_t = 0

        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return AirPodsDetail(leftBattery: nil, rightBattery: nil, caseBattery: nil)
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = properties?.takeRetainedValue() as? [String: Any] else {
                continue
            }

            if let deviceAddr = dict["DeviceAddress"] as? String,
               deviceAddr.lowercased() == address.lowercased() {
                let left = dict["BatteryPercentLeft"] as? Int
                let right = dict["BatteryPercentRight"] as? Int
                let caseBatt = dict["BatteryPercentCase"] as? Int

                return AirPodsDetail(
                    leftBattery: left,
                    rightBattery: right,
                    caseBattery: caseBatt
                )
            }
        }

        // AirPods detected by name but no IOKit battery data available
        return AirPodsDetail(leftBattery: nil, rightBattery: nil, caseBattery: nil)
    }
}

// MARK: - Mock Bluetooth Collector

/// Mock Bluetooth collector for testing
public final class MockBluetoothCollector: BluetoothCollecting, @unchecked Sendable {
    public let id = "bluetooth-mock"
    public let displayName = "Bluetooth (Mock)"
    public let requiresHelper = false
    public var isAvailable: Bool = true

    public var mockSnapshot: BluetoothSnapshot = BluetoothSnapshot()
    public private(set) var activateCount = 0
    public private(set) var deactivateCount = 0

    public init() {}

    public func activate() async { activateCount += 1 }
    public func deactivate() async { deactivateCount += 1 }

    public func collect() async -> BluetoothSnapshot {
        mockSnapshot
    }
}
