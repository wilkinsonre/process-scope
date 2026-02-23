import Foundation
import os

/// Collects network connection information
public actor NetworkCollector: SystemCollector {
    public nonisolated let id = "network"
    public nonisolated let displayName = "Network"
    public nonisolated let requiresHelper = false
    public nonisolated var isAvailable: Bool { true }

    private let logger = Logger(subsystem: "com.processscope", category: "NetworkCollector")
    private var _isActive = false

    public init() {}

    public func activate() {
        _isActive = true
        logger.info("NetworkCollector activated")
    }

    public func deactivate() {
        _isActive = false
        logger.info("NetworkCollector deactivated")
    }

    // MARK: - Collection

    /// Information about a network interface
    public struct InterfaceInfo: Sendable, Identifiable {
        public var id: String { name }
        public let name: String
        public let address: String
        public let isUp: Bool
        public let bytesIn: UInt64
        public let bytesOut: UInt64
    }

    /// Collects IPv4 interface information using getifaddrs
    public func collectInterfaces() -> [InterfaceInfo] {
        guard _isActive else { return [] }

        var interfaces: [InterfaceInfo] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let addr = ptr {
            let name = String(cString: addr.pointee.ifa_name)
            let flags = Int32(addr.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0

            if addr.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_INET) {
                let sockAddr = addr.pointee.ifa_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                var addrBuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                var inAddr = sockAddr.sin_addr
                inet_ntop(AF_INET, &inAddr, &addrBuf, socklen_t(INET_ADDRSTRLEN))
                let address = String(cString: addrBuf)

                interfaces.append(InterfaceInfo(
                    name: name,
                    address: address,
                    isUp: isUp,
                    bytesIn: 0,
                    bytesOut: 0
                ))
            }
            ptr = addr.pointee.ifa_next
        }
        return interfaces
    }
}
