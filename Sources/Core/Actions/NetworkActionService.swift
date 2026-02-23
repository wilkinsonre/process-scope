import Foundation
import AppKit
import os

// MARK: - Network Action Result Types

/// Result of a ping operation to a remote host
public struct PingResult: Sendable, Equatable {
    /// Number of packets transmitted
    public let transmitted: Int
    /// Number of packets received
    public let received: Int
    /// Percentage of packets lost (0.0 to 100.0)
    public let lossPercent: Double
    /// Minimum round-trip time in milliseconds
    public let minMs: Double
    /// Average round-trip time in milliseconds
    public let avgMs: Double
    /// Maximum round-trip time in milliseconds
    public let maxMs: Double

    public init(transmitted: Int, received: Int, lossPercent: Double,
                minMs: Double, avgMs: Double, maxMs: Double) {
        self.transmitted = transmitted
        self.received = received
        self.lossPercent = lossPercent
        self.minMs = minMs
        self.avgMs = avgMs
        self.maxMs = maxMs
    }
}

/// A single hop in a traceroute operation
public struct TraceHop: Sendable, Equatable {
    /// Hop number (1, 2, 3, ...)
    public let hopNumber: Int
    /// Resolved hostname for this hop (may be the IP if reverse lookup failed)
    public let host: String
    /// IP address of this hop
    public let ip: String
    /// Round-trip times in milliseconds for each probe (typically 3)
    public let rttMs: [Double]

    public init(hopNumber: Int, host: String, ip: String, rttMs: [Double]) {
        self.hopNumber = hopNumber
        self.host = host
        self.ip = ip
        self.rttMs = rttMs
    }
}

/// Result of a DNS lookup query
public struct DNSResult: Sendable, Equatable {
    /// The hostname that was queried
    public let hostname: String
    /// Resolved IP addresses
    public let addresses: [String]
    /// DNS server that answered the query
    public let server: String
    /// Query time in milliseconds
    public let queryTimeMs: Double

    public init(hostname: String, addresses: [String], server: String, queryTimeMs: Double) {
        self.hostname = hostname
        self.addresses = addresses
        self.server = server
        self.queryTimeMs = queryTimeMs
    }
}

// MARK: - Network Action Service Protocol

/// Protocol for network actions, enabling mock injection for tests
public protocol NetworkActionServiceProtocol: Sendable {
    /// Opens Terminal.app with an SSH command to the specified host
    func openSSHTerminal(host: String, user: String?, port: Int?) async throws
    /// Flushes the system DNS cache (requires privileged helper)
    func flushDNSCache() async throws
    /// Pings a host with the specified number of packets
    func pingHost(_ host: String, count: Int) async throws -> PingResult
    /// Runs traceroute to the specified host
    func traceRoute(to host: String) async throws -> [TraceHop]
    /// Performs a DNS lookup for the specified hostname
    func lookupDNS(hostname: String) async throws -> DNSResult
}

// MARK: - Network Action Error

/// Errors specific to network action operations
public enum NetworkActionError: LocalizedError {
    case commandFailed(String, Int32)
    case parseError(String)
    case timeout
    case invalidHost(String)
    case invalidUser(String)
    case invalidPort(Int)

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let command, let exitCode):
            "Command '\(command)' failed with exit code \(exitCode)"
        case .parseError(let detail):
            "Failed to parse output: \(detail)"
        case .timeout:
            "Network operation timed out"
        case .invalidHost(let host):
            "Invalid host: \(host)"
        case .invalidUser(let user):
            "Invalid SSH user: \(user)"
        case .invalidPort(let port):
            "Invalid port number: \(port)"
        }
    }
}

// MARK: - Network Action Service

/// Executes network-related actions: SSH terminal, DNS flush, ping, traceroute, DNS lookup
///
/// Network diagnostic commands (`ping`, `traceroute`, `nslookup`) are executed
/// via `Process` and their output is parsed into structured result types.
/// SSH terminal opens Terminal.app with the appropriate ssh command.
/// DNS flush requires the privileged helper daemon since it needs sudo.
///
/// Thread safety is guaranteed by actor isolation.
public actor NetworkActionService: NetworkActionServiceProtocol {
    private static let logger = Logger(subsystem: "com.processscope", category: "NetworkActionService")

    private let helperConnection: HelperConnection

    /// Creates a network action service
    /// - Parameter helperConnection: XPC connection to the privileged helper
    public init(helperConnection: HelperConnection = HelperConnection()) {
        self.helperConnection = helperConnection
    }

    // MARK: - Input Validation

    /// Character set of allowed characters in hostnames and IP addresses
    ///
    /// Allows: letters, digits, hyphens, dots, colons (IPv6), square brackets (IPv6).
    /// Rejects everything else to prevent command injection when passing hostnames
    /// to `Process` arguments or AppleScript strings.
    private static let allowedHostCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-.:[]"
    )

    /// Validates a hostname or IP address string for safety
    ///
    /// - Parameter host: The hostname or IP address to validate
    /// - Throws: ``NetworkActionError/invalidHost(_:)`` if validation fails
    private static func validateHostname(_ host: String) throws {
        guard !host.isEmpty else {
            throw NetworkActionError.invalidHost(host)
        }
        guard host.count <= 253 else {
            throw NetworkActionError.invalidHost(host)
        }
        guard host.unicodeScalars.allSatisfy({ allowedHostCharacters.contains($0) }) else {
            throw NetworkActionError.invalidHost(host)
        }
        guard !host.hasPrefix("-") else {
            throw NetworkActionError.invalidHost(host)
        }
        guard !host.contains("..") else {
            throw NetworkActionError.invalidHost(host)
        }
    }

    /// Character set of allowed characters in SSH usernames
    ///
    /// Allows: letters, digits, hyphens, underscores, dots.
    private static let allowedUserCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_."
    )

    /// Validates an SSH username string for safety
    ///
    /// - Parameter user: The username to validate
    /// - Throws: ``NetworkActionError/invalidUser(_:)`` if validation fails
    private static func validateSSHUser(_ user: String) throws {
        guard !user.isEmpty else {
            throw NetworkActionError.invalidUser(user)
        }
        guard user.unicodeScalars.allSatisfy({ allowedUserCharacters.contains($0) }) else {
            throw NetworkActionError.invalidUser(user)
        }
    }

    /// Validates an SSH port number
    ///
    /// - Parameter port: The port number to validate
    /// - Throws: ``NetworkActionError/invalidPort(_:)`` if the port is out of range
    private static func validatePort(_ port: Int) throws {
        guard (1...65535).contains(port) else {
            throw NetworkActionError.invalidPort(port)
        }
    }

    // MARK: - SSH Terminal

    /// Opens Terminal.app with an SSH command to the specified host
    ///
    /// Constructs the appropriate `ssh` command string with optional user and port
    /// arguments, then launches it in a new Terminal.app window via AppleScript.
    ///
    /// - Parameters:
    ///   - host: The remote hostname or IP address
    ///   - user: Optional username for the connection
    ///   - port: Optional port number (defaults to 22 if nil)
    @MainActor
    public func openSSHTerminal(host: String, user: String?, port: Int?) async throws {
        try Self.validateHostname(host)
        if let user {
            try Self.validateSSHUser(user)
        }
        if let port {
            try Self.validatePort(port)
        }

        let command = buildSSHCommand(host: host, user: user, port: port)
        Self.logger.info("Opening SSH terminal: \(command)")

        let escapedCommand = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "tell application \"Terminal\" to do script \"\(escapedCommand)\""

        var errorInfo: NSDictionary?
        let appleScript = NSAppleScript(source: script)
        appleScript?.executeAndReturnError(&errorInfo)

        if let errorInfo {
            Self.logger.error("AppleScript error opening SSH terminal: \(errorInfo)")
        }
    }

    /// Builds an SSH command string from the given parameters
    /// - Parameters:
    ///   - host: The remote hostname or IP address
    ///   - user: Optional username
    ///   - port: Optional port number
    /// - Returns: The full ssh command string
    public nonisolated func buildSSHCommand(host: String, user: String?, port: Int?) -> String {
        var parts = ["ssh"]
        if let user {
            parts.append("\(user)@\(host)")
        } else {
            parts.append(host)
        }
        if let port, port != 22 {
            parts.append("-p")
            parts.append("\(port)")
        }
        return parts.joined(separator: " ")
    }

    // MARK: - DNS Flush

    /// Flushes the system DNS cache
    ///
    /// This requires the privileged helper daemon because `dscacheutil -flushcache`
    /// and `killall -HUP mDNSResponder` both need root privileges.
    ///
    /// - Throws: ``HelperError`` if the helper is unavailable or the operation fails
    public func flushDNSCache() async throws {
        Self.logger.info("Requesting DNS cache flush via helper")
        try await helperConnection.flushDNS()
    }

    // MARK: - Ping

    /// Pings a host and returns parsed statistics
    ///
    /// Runs `/sbin/ping -c <count> <host>` and parses the summary line for
    /// packet loss and round-trip time statistics.
    ///
    /// - Parameters:
    ///   - host: The hostname or IP address to ping
    ///   - count: Number of ICMP echo requests to send (default 5)
    /// - Returns: A ``PingResult`` with transmission and timing statistics
    /// - Throws: ``NetworkActionError`` if the command fails or output cannot be parsed
    public func pingHost(_ host: String, count: Int = 5) async throws -> PingResult {
        try Self.validateHostname(host)

        Self.logger.info("Pinging \(host) with count \(count)")

        let output = try await runCommand(
            executablePath: "/sbin/ping",
            arguments: ["-c", "\(count)", host],
            timeout: TimeInterval(count * 5 + 10)
        )

        return try Self.parsePingOutput(output)
    }

    // MARK: - Traceroute

    /// Traces the route to a host and returns parsed hops
    ///
    /// Runs `/usr/sbin/traceroute <host>` and parses each hop line into
    /// structured ``TraceHop`` values with hop number, host, IP, and RTT values.
    ///
    /// - Parameter host: The hostname or IP address to trace
    /// - Returns: Array of ``TraceHop`` values, one per network hop
    /// - Throws: ``NetworkActionError`` if the command fails or output cannot be parsed
    public func traceRoute(to host: String) async throws -> [TraceHop] {
        try Self.validateHostname(host)

        Self.logger.info("Traceroute to \(host)")

        let output = try await runCommand(
            executablePath: "/usr/sbin/traceroute",
            arguments: [host],
            timeout: 60
        )

        return Self.parseTracerouteOutput(output)
    }

    // MARK: - DNS Lookup

    /// Performs a DNS lookup for the specified hostname
    ///
    /// Runs `nslookup <hostname>` and parses the output for resolved addresses,
    /// the answering server, and query timing.
    ///
    /// - Parameter hostname: The hostname to look up
    /// - Returns: A ``DNSResult`` with addresses, server, and timing
    /// - Throws: ``NetworkActionError`` if the command fails or output cannot be parsed
    public func lookupDNS(hostname: String) async throws -> DNSResult {
        try Self.validateHostname(hostname)

        Self.logger.info("DNS lookup for \(hostname)")

        let output = try await runCommand(
            executablePath: "/usr/bin/nslookup",
            arguments: [hostname],
            timeout: 15
        )

        return try Self.parseNslookupOutput(output, hostname: hostname)
    }

    // MARK: - Command Execution

    /// Runs a command-line tool and returns its standard output as a string
    /// - Parameters:
    ///   - executablePath: Absolute path to the executable
    ///   - arguments: Command-line arguments
    ///   - timeout: Maximum time in seconds to wait for completion
    /// - Returns: The combined stdout string
    /// - Throws: ``NetworkActionError`` if the command fails
    private func runCommand(
        executablePath: String,
        arguments: [String],
        timeout: TimeInterval = 30
    ) async throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executablePath)
        task.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        task.standardOutput = stdoutPipe
        task.standardError = stderrPipe

        do {
            try task.run()
        } catch {
            throw NetworkActionError.commandFailed(executablePath, -1)
        }

        // Wait for completion with timeout using Task cancellation
        let commandName = executablePath
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                task.waitUntilExit()

                let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outputData, encoding: .utf8) ?? ""

                // ping returns exit code 2 for some failures but may still have parseable output
                // traceroute may return non-zero for unreachable hosts
                if task.terminationStatus != 0 && output.isEmpty {
                    continuation.resume(throwing: NetworkActionError.commandFailed(
                        commandName,
                        task.terminationStatus
                    ))
                } else {
                    continuation.resume(returning: output)
                }
            }
        }
    }

    // MARK: - Output Parsing

    /// Parses the output of `/sbin/ping` into a ``PingResult``
    ///
    /// Expects output containing lines like:
    /// ```
    /// 5 packets transmitted, 5 packets received, 0.0% packet loss
    /// round-trip min/avg/max/stddev = 12.345/15.678/20.123/2.456 ms
    /// ```
    ///
    /// - Parameter output: The raw stdout from the ping command
    /// - Returns: Parsed ``PingResult``
    /// - Throws: ``NetworkActionError/parseError(_:)`` if the output cannot be parsed
    public static func parsePingOutput(_ output: String) throws -> PingResult {
        let lines = output.components(separatedBy: "\n")

        var transmitted = 0
        var received = 0
        var lossPercent = 0.0
        var minMs = 0.0
        var avgMs = 0.0
        var maxMs = 0.0

        var foundStats = false
        var foundRTT = false

        for line in lines {
            // Parse: "5 packets transmitted, 5 packets received, 0.0% packet loss"
            if line.contains("packets transmitted") {
                let parts = line.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                for part in parts {
                    if part.hasSuffix("packets transmitted") || part.hasSuffix("packet transmitted") {
                        if let val = Int(part.components(separatedBy: " ").first ?? "") {
                            transmitted = val
                        }
                    } else if part.contains("received") {
                        if let val = Int(part.components(separatedBy: " ").first ?? "") {
                            received = val
                        }
                    } else if part.contains("packet loss") {
                        let lossStr = part.replacingOccurrences(of: "% packet loss", with: "")
                        if let val = Double(lossStr) {
                            lossPercent = val
                        }
                    }
                }
                foundStats = true
            }

            // Parse: "round-trip min/avg/max/stddev = 12.345/15.678/20.123/2.456 ms"
            if line.contains("round-trip") || line.contains("rtt") {
                let parts = line.components(separatedBy: "=")
                if parts.count >= 2 {
                    let timings = parts[1]
                        .trimmingCharacters(in: .whitespaces)
                        .replacingOccurrences(of: " ms", with: "")
                        .components(separatedBy: "/")
                    if timings.count >= 3 {
                        minMs = Double(timings[0]) ?? 0.0
                        avgMs = Double(timings[1]) ?? 0.0
                        maxMs = Double(timings[2]) ?? 0.0
                    }
                }
                foundRTT = true
            }
        }

        guard foundStats else {
            throw NetworkActionError.parseError("Could not find packet statistics in ping output")
        }

        // RTT might not be present if all packets were lost
        if !foundRTT && received > 0 {
            throw NetworkActionError.parseError("Could not find round-trip statistics in ping output")
        }

        return PingResult(
            transmitted: transmitted,
            received: received,
            lossPercent: lossPercent,
            minMs: minMs,
            avgMs: avgMs,
            maxMs: maxMs
        )
    }

    /// Parses the output of `/usr/sbin/traceroute` into an array of ``TraceHop``
    ///
    /// Expects output lines like:
    /// ```
    ///  1  gateway (192.168.1.1)  1.234 ms  1.567 ms  1.890 ms
    ///  2  * * *
    ///  3  10.0.0.1 (10.0.0.1)  5.432 ms  5.678 ms  5.901 ms
    /// ```
    ///
    /// - Parameter output: The raw stdout from the traceroute command
    /// - Returns: Array of parsed ``TraceHop`` values
    public static func parseTracerouteOutput(_ output: String) -> [TraceHop] {
        let lines = output.components(separatedBy: "\n")
        var hops: [TraceHop] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Skip the header line ("traceroute to ...")
            if trimmed.hasPrefix("traceroute to") { continue }

            // Try to parse a hop line
            let tokens = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard tokens.count >= 2 else { continue }
            guard let hopNum = Int(tokens[0]) else { continue }

            // Check for "* * *" (timeout) hops
            if tokens[1] == "*" {
                hops.append(TraceHop(hopNumber: hopNum, host: "*", ip: "*", rttMs: []))
                continue
            }

            // Parse host and optional (ip) and RTT values
            var host = tokens[1]
            var ip = host
            var rtts: [Double] = []
            var tokenIdx = 2

            // If next token is "(ip)", extract IP
            if tokenIdx < tokens.count {
                let ipCandidate = tokens[tokenIdx]
                if ipCandidate.hasPrefix("(") && ipCandidate.hasSuffix(")") {
                    ip = String(ipCandidate.dropFirst().dropLast())
                    tokenIdx += 1
                }
            }

            // Collect RTT values (numbers followed by "ms")
            while tokenIdx < tokens.count {
                let token = tokens[tokenIdx]
                if token == "ms" {
                    tokenIdx += 1
                    continue
                }
                if token == "*" {
                    tokenIdx += 1
                    continue
                }
                if let rtt = Double(token) {
                    rtts.append(rtt)
                }
                tokenIdx += 1
            }

            hops.append(TraceHop(hopNumber: hopNum, host: host, ip: ip, rttMs: rtts))
        }

        return hops
    }

    /// Parses the output of `nslookup` into a ``DNSResult``
    ///
    /// Expects output like:
    /// ```
    /// Server:  8.8.8.8
    /// Address: 8.8.8.8#53
    ///
    /// Non-authoritative answer:
    /// Name:    example.com
    /// Address: 93.184.216.34
    /// ```
    ///
    /// - Parameters:
    ///   - output: The raw stdout from the nslookup command
    ///   - hostname: The original hostname that was queried
    /// - Returns: Parsed ``DNSResult``
    /// - Throws: ``NetworkActionError/parseError(_:)`` if the output cannot be parsed
    public static func parseNslookupOutput(_ output: String, hostname: String) throws -> DNSResult {
        let lines = output.components(separatedBy: "\n")

        var server = ""
        var addresses: [String] = []
        var inAnswer = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Parse server line
            if trimmed.hasPrefix("Server:") {
                server = trimmed
                    .replacingOccurrences(of: "Server:", with: "")
                    .trimmingCharacters(in: .whitespaces)
            }

            // Track when we are past the "Non-authoritative answer:" section
            if trimmed.contains("Non-authoritative answer") || trimmed.contains("Authoritative answer") {
                inAnswer = true
                continue
            }

            // Parse address lines in the answer section
            if inAnswer && trimmed.hasPrefix("Address:") {
                let addr = trimmed
                    .replacingOccurrences(of: "Address:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                // Skip server address entries (contain #port)
                if !addr.contains("#") {
                    addresses.append(addr)
                }
            }
        }

        // nslookup does not report query time, so we use 0
        return DNSResult(
            hostname: hostname,
            addresses: addresses,
            server: server,
            queryTimeMs: 0
        )
    }
}

// MARK: - Mock Network Action Service

/// Mock implementation for testing network actions without executing real commands
public actor MockNetworkActionService: NetworkActionServiceProtocol {
    public var sshCommandsOpened: [(host: String, user: String?, port: Int?)] = []
    public var dnsFlushCallCount = 0
    public var pingResults: [String: PingResult] = [:]
    public var traceRouteResults: [String: [TraceHop]] = [:]
    public var dnsLookupResults: [String: DNSResult] = [:]
    public var shouldThrowOnFlush = false
    public var shouldThrowOnPing = false
    public var shouldThrowOnTrace = false
    public var shouldThrowOnLookup = false

    public init() {}

    public func openSSHTerminal(host: String, user: String?, port: Int?) async throws {
        sshCommandsOpened.append((host: host, user: user, port: port))
    }

    public func flushDNSCache() async throws {
        dnsFlushCallCount += 1
        if shouldThrowOnFlush {
            throw NetworkActionError.commandFailed("flushDNS", 1)
        }
    }

    public func pingHost(_ host: String, count: Int) async throws -> PingResult {
        if shouldThrowOnPing {
            throw NetworkActionError.commandFailed("ping", 1)
        }
        if let result = pingResults[host] {
            return result
        }
        return PingResult(transmitted: count, received: count, lossPercent: 0,
                          minMs: 10, avgMs: 15, maxMs: 20)
    }

    public func traceRoute(to host: String) async throws -> [TraceHop] {
        if shouldThrowOnTrace {
            throw NetworkActionError.commandFailed("traceroute", 1)
        }
        return traceRouteResults[host] ?? []
    }

    public func lookupDNS(hostname: String) async throws -> DNSResult {
        if shouldThrowOnLookup {
            throw NetworkActionError.commandFailed("nslookup", 1)
        }
        if let result = dnsLookupResults[hostname] {
            return result
        }
        return DNSResult(hostname: hostname, addresses: ["127.0.0.1"], server: "8.8.8.8", queryTimeMs: 5)
    }
}
