import Foundation
import CoreWLAN
import os

// MARK: - WiFi Data Types

/// Snapshot of the current WiFi connection state
public struct WiFiSnapshot: Codable, Sendable {
    public let ssid: String?
    public let bssid: String?
    public let channel: Int?
    public let band: String
    public let rssi: Int
    public let noiseMeasurement: Int
    public let snr: Int
    public let txRate: Double
    public let security: String
    public let countryCode: String?
    public let interfaceName: String

    public init(ssid: String?, bssid: String?, channel: Int?, band: String,
                rssi: Int, noiseMeasurement: Int, snr: Int, txRate: Double,
                security: String, countryCode: String?, interfaceName: String) {
        self.ssid = ssid
        self.bssid = bssid
        self.channel = channel
        self.band = band
        self.rssi = rssi
        self.noiseMeasurement = noiseMeasurement
        self.snr = snr
        self.txRate = txRate
        self.security = security
        self.countryCode = countryCode
        self.interfaceName = interfaceName
    }

    /// Signal quality as a percentage (0-100) computed from SNR
    ///
    /// Uses a linear mapping: SNR of 10 dB maps to 0%, SNR of 40 dB maps to 100%
    public var signalQuality: Int {
        let clamped = min(max(snr, 10), 40)
        return Int(Double(clamped - 10) / 30.0 * 100.0)
    }

    /// Number of signal bars (0-4) for UI display
    public var signalBars: Int {
        switch rssi {
        case -50...0: return 4
        case -60..<(-50): return 3
        case -70..<(-60): return 2
        case -80..<(-70): return 1
        default: return 0
        }
    }
}

/// A nearby WiFi network found during a scan
public struct NearbyNetwork: Codable, Sendable, Identifiable {
    public var id: String { "\(ssid)-\(bssid)" }
    public let ssid: String
    public let bssid: String
    public let rssi: Int
    public let channel: Int
    public let band: String
    public let security: String

    public init(ssid: String, bssid: String, rssi: Int, channel: Int,
                band: String, security: String) {
        self.ssid = ssid
        self.bssid = bssid
        self.rssi = rssi
        self.channel = channel
        self.band = band
        self.security = security
    }
}

// MARK: - WiFi Collector Protocol

/// Protocol for WiFi data collection, enabling mock injection for tests
public protocol WiFiCollecting: AnyObject, Sendable {
    func collectSnapshot() async -> WiFiSnapshot?
    func scanForNetworks() async -> [NearbyNetwork]
}

// MARK: - WiFi Collector

/// Collects WiFi connection details using CoreWLAN framework.
///
/// Uses only public `CWWiFiClient` APIs (no private APIs). CoreWLAN requires
/// the Location Services entitlement for some operations on macOS 14+;
/// the collector degrades gracefully if access is restricted.
///
/// Subscribes to the Slow polling tier (10s).
public actor WiFiCollector: SystemCollector, WiFiCollecting {
    public nonisolated let id = "wifi"
    public nonisolated let displayName = "WiFi"
    public nonisolated let requiresHelper = false

    public nonisolated var isAvailable: Bool {
        CWWiFiClient.shared().interface() != nil
    }

    private let logger = Logger(subsystem: "com.processscope", category: "WiFiCollector")
    private var _isActive = false

    public init() {}

    public func activate() {
        _isActive = true
        logger.info("WiFiCollector activated")
    }

    public func deactivate() {
        _isActive = false
        logger.info("WiFiCollector deactivated")
    }

    // MARK: - Collection

    /// Collects the current WiFi connection snapshot
    ///
    /// Returns nil if WiFi is disabled, not connected, or if CoreWLAN
    /// access is restricted.
    public func collectSnapshot() async -> WiFiSnapshot? {
        guard _isActive else { return nil }
        guard let iface = CWWiFiClient.shared().interface() else {
            logger.debug("No WiFi interface available")
            return nil
        }

        let rssi = iface.rssiValue()
        let noise = iface.noiseMeasurement()

        return WiFiSnapshot(
            ssid: iface.ssid(),
            bssid: iface.bssid(),
            channel: iface.wlanChannel()?.channelNumber,
            band: Self.bandName(iface.wlanChannel()),
            rssi: rssi,
            noiseMeasurement: noise,
            snr: rssi - noise,
            txRate: iface.transmitRate(),
            security: Self.securityName(iface.security()),
            countryCode: iface.countryCode(),
            interfaceName: iface.interfaceName ?? "en0"
        )
    }

    /// Scans for nearby WiFi networks
    ///
    /// This is an on-demand operation that may take several seconds to complete.
    /// Returns an empty array if scanning fails or if CoreWLAN access is restricted.
    public func scanForNetworks() async -> [NearbyNetwork] {
        guard _isActive else { return [] }
        guard let iface = CWWiFiClient.shared().interface() else { return [] }

        do {
            let networks = try iface.scanForNetworks(withSSID: nil)

            return networks.compactMap { network in
                NearbyNetwork(
                    ssid: network.ssid ?? "(hidden)",
                    bssid: network.bssid ?? "",
                    rssi: network.rssiValue,
                    channel: network.wlanChannel?.channelNumber ?? 0,
                    band: Self.bandName(network.wlanChannel),
                    security: Self.securityNameFromNetwork(network)
                )
            }.sorted { $0.rssi > $1.rssi }
        } catch {
            logger.warning("WiFi scan failed: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Helpers

    /// Returns a human-readable band name for a CWChannel
    private static func bandName(_ channel: CWChannel?) -> String {
        guard let ch = channel else { return "Unknown" }
        switch ch.channelBand {
        case .band2GHz: return "2.4 GHz"
        case .band5GHz: return "5 GHz"
        case .band6GHz: return "6 GHz"
        @unknown default: return "Unknown"
        }
    }

    /// Returns a human-readable security mode name
    private static func securityName(_ security: CWSecurity) -> String {
        switch security {
        case .none: return "Open"
        case .WEP: return "WEP"
        case .wpaPersonal: return "WPA Personal"
        case .wpaPersonalMixed: return "WPA Mixed"
        case .wpa2Personal: return "WPA2 Personal"
        case .personal: return "WPA3 Personal"
        case .wpaEnterprise: return "WPA Enterprise"
        case .wpaEnterpriseMixed: return "WPA Enterprise Mixed"
        case .wpa2Enterprise: return "WPA2 Enterprise"
        case .enterprise: return "WPA3 Enterprise"
        case .dynamicWEP: return "Dynamic WEP"
        case .unknown: return "Unknown"
        @unknown default: return "Unknown"
        }
    }

    /// Extracts security info from a scanned CWNetwork
    private static func securityNameFromNetwork(_ network: CWNetwork) -> String {
        if network.supportsSecurity(.personal) || network.supportsSecurity(.wpa2Personal) {
            return "WPA2/3"
        }
        if network.supportsSecurity(.enterprise) || network.supportsSecurity(.wpa2Enterprise) {
            return "Enterprise"
        }
        if network.supportsSecurity(.wpaPersonal) || network.supportsSecurity(.wpaPersonalMixed) {
            return "WPA"
        }
        if network.supportsSecurity(.WEP) {
            return "WEP"
        }
        if network.supportsSecurity(.none) {
            return "Open"
        }
        return "Unknown"
    }
}

// MARK: - Mock WiFi Collector

/// Mock collector for testing WiFi UI without a real WiFi interface
public final class MockWiFiCollector: WiFiCollecting, SystemCollector, @unchecked Sendable {
    public let id = "wifi-mock"
    public let displayName = "WiFi (Mock)"
    public let requiresHelper = false
    public var isAvailable: Bool = true

    public var mockSnapshot: WiFiSnapshot?
    public var mockNetworks: [NearbyNetwork] = []
    public private(set) var activateCount = 0
    public private(set) var deactivateCount = 0

    public init() {}

    public func activate() async { activateCount += 1 }
    public func deactivate() async { deactivateCount += 1 }

    public func collectSnapshot() async -> WiFiSnapshot? { mockSnapshot }
    public func scanForNetworks() async -> [NearbyNetwork] { mockNetworks }
}
