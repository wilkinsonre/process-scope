import Foundation
import os

// MARK: - Listening Port Data Types

/// Represents a port on which a process is listening for connections
public struct ListeningPort: Codable, Sendable, Identifiable {
    public var id: String { "\(pid)-\(port)-\(protocolName)-\(address)" }
    public let port: UInt16
    public let protocolName: String  // "TCP" or "UDP"
    public let pid: pid_t
    public let processName: String
    public let address: String
    public let isExposed: Bool

    public init(port: UInt16, protocolName: String, pid: pid_t,
                processName: String, address: String, isExposed: Bool) {
        self.port = port
        self.protocolName = protocolName
        self.pid = pid
        self.processName = processName
        self.address = address
        self.isExposed = isExposed
    }

    /// Well-known service name for common ports
    public var serviceName: String? {
        Self.wellKnownPorts[port]
    }

    /// Map of well-known port numbers to service names
    private static let wellKnownPorts: [UInt16: String] = [
        22: "SSH", 53: "DNS", 80: "HTTP", 443: "HTTPS",
        631: "CUPS", 993: "IMAP", 995: "POP3", 1080: "SOCKS",
        3000: "Dev Server", 3306: "MySQL", 4000: "Dev Server",
        5000: "Dev Server", 5432: "PostgreSQL", 5900: "VNC",
        6379: "Redis", 8000: "Dev Server", 8080: "HTTP Alt",
        8443: "HTTPS Alt", 8888: "Jupyter", 9090: "Prometheus",
        27017: "MongoDB",
    ]
}

// MARK: - Listening Ports Collector Protocol

/// Protocol for listening port collection, enabling mock injection for tests
public protocol ListeningPortsCollecting: AnyObject, Sendable {
    func collectListeningPorts() async -> [ListeningPort]
}

// MARK: - Listening Ports Collector

/// Enumerates listening sockets across all accessible processes using
/// `proc_pidinfo(PROC_PIDLISTFDS)` and `proc_pidfdinfo(PROC_PIDFDSOCKETINFO)`.
///
/// Identifies processes with open listening sockets and flags ports that are
/// exposed on all interfaces (0.0.0.0 or ::) as potentially security-relevant.
///
/// Subscribes to the Extended polling tier (3s).
public actor ListeningPortsCollector: SystemCollector, ListeningPortsCollecting {
    public nonisolated let id = "listening-ports"
    public nonisolated let displayName = "Listening Ports"
    public nonisolated let requiresHelper = false
    public nonisolated var isAvailable: Bool { true }

    private let logger = Logger(subsystem: "com.processscope", category: "ListeningPortsCollector")
    private var _isActive = false

    public init() {}

    public func activate() {
        _isActive = true
        logger.info("ListeningPortsCollector activated")
    }

    public func deactivate() {
        _isActive = false
        logger.info("ListeningPortsCollector deactivated")
    }

    // MARK: - Collection

    /// Collects all listening ports from all accessible processes
    ///
    /// Iterates through the process list, enumerates file descriptors for each,
    /// filters for sockets in the LISTEN state, and extracts port/address info.
    public func collectListeningPorts() async -> [ListeningPort] {
        guard _isActive else { return [] }

        let allProcs = SysctlWrapper.allProcesses()
        var ports: [ListeningPort] = []
        var seen = Set<String>()

        for kinfo in allProcs {
            let pid = kinfo.kp_proc.p_pid
            guard pid > 0 else { continue }

            let fds = LibProcWrapper.fileDescriptors(for: pid)
            let socketFDs = fds.filter { $0.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) }

            guard !socketFDs.isEmpty else { continue }

            let processName = LibProcWrapper.processName(for: pid) ?? "unknown"

            for fd in socketFDs {
                guard let socketInfo = LibProcWrapper.socketInfo(pid: pid, fd: fd.proc_fd) else {
                    continue
                }

                // Check for TCP sockets in LISTEN state
                let family = socketInfo.psi.soi_family
                guard family == AF_INET || family == AF_INET6 else { continue }

                let proto = socketInfo.psi.soi_protocol
                let isTCP = proto == IPPROTO_TCP
                let isUDP = proto == IPPROTO_UDP
                guard isTCP || isUDP else { continue }

                // For TCP, check listen state
                if isTCP {
                    let tcpState = socketInfo.psi.soi_proto.pri_tcp.tcpsi_state
                    guard tcpState == TSI_S_LISTEN else { continue }
                }

                // Extract local address and port
                let (address, localPort) = Self.extractLocalAddress(
                    socketInfo: socketInfo,
                    family: family
                )

                guard localPort > 0 else { continue }

                let isExposed = address == "0.0.0.0" || address == "::" || address == "*"
                let dedupeKey = "\(pid)-\(localPort)-\(isTCP ? "TCP" : "UDP")"
                guard !seen.contains(dedupeKey) else { continue }
                seen.insert(dedupeKey)

                ports.append(ListeningPort(
                    port: localPort,
                    protocolName: isTCP ? "TCP" : "UDP",
                    pid: pid,
                    processName: processName,
                    address: address,
                    isExposed: isExposed
                ))
            }
        }

        return ports.sorted { $0.port < $1.port }
    }

    // MARK: - Address Extraction

    /// Extracts the local address and port from a socket_fdinfo structure
    private static func extractLocalAddress(
        socketInfo: socket_fdinfo,
        family: Int32
    ) -> (address: String, port: UInt16) {
        let lportRaw = socketInfo.psi.soi_proto.pri_tcp.tcpsi_ini.insi_lport
        let port = UInt16(truncatingIfNeeded: lportRaw).bigEndian

        if family == AF_INET {
            var laddr = socketInfo.psi.soi_proto.pri_tcp.tcpsi_ini.insi_laddr.ina_46.i46a_addr4
            var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            inet_ntop(AF_INET, &laddr, &buf, socklen_t(INET_ADDRSTRLEN))
            let address = String(decoding: buf.prefix(while: { $0 != 0 }).map(UInt8.init), as: UTF8.self)
            return (address, port)
        } else {
            var laddr = socketInfo.psi.soi_proto.pri_tcp.tcpsi_ini.insi_laddr.ina_6
            var buf = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            inet_ntop(AF_INET6, &laddr, &buf, socklen_t(INET6_ADDRSTRLEN))
            let address = String(decoding: buf.prefix(while: { $0 != 0 }).map(UInt8.init), as: UTF8.self)
            return (address, port)
        }
    }
}

// MARK: - Mock Listening Ports Collector

/// Mock collector for testing listening ports UI without real socket enumeration
public final class MockListeningPortsCollector: ListeningPortsCollecting, SystemCollector, @unchecked Sendable {
    public let id = "listening-ports-mock"
    public let displayName = "Listening Ports (Mock)"
    public let requiresHelper = false
    public var isAvailable: Bool = true

    public var mockPorts: [ListeningPort] = []
    public private(set) var activateCount = 0
    public private(set) var deactivateCount = 0

    public init() {}

    public func activate() async { activateCount += 1 }
    public func deactivate() async { deactivateCount += 1 }

    public func collectListeningPorts() async -> [ListeningPort] { mockPorts }
}
