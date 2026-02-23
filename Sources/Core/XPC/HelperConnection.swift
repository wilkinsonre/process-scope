import Foundation
import os

/// Manages the XPC connection to the privileged helper daemon
public actor HelperConnection {
    private static let logger = Logger(subsystem: "com.processscope", category: "HelperConnection")
    private static let machServiceName = "com.processscope.helper"

    private var connection: NSXPCConnection?
    private var isConnecting = false

    public init() {}

    // MARK: - Connection Management

    public var isConnected: Bool { connection != nil }

    private func connect() -> NSXPCConnection {
        if let existing = connection { return existing }

        let conn = NSXPCConnection(machServiceName: Self.machServiceName)
        conn.remoteObjectInterface = NSXPCInterface(with: PSHelperProtocol.self)
        conn.invalidationHandler = {
            // Connection invalidated — will reconnect on next call
        }
        conn.interruptionHandler = {
            // Connection interrupted — proxy will auto-reconnect
        }
        conn.resume()
        connection = conn
        Self.logger.info("Connected to helper daemon")
        return conn
    }

    private func handleInvalidation() {
        connection = nil
        Self.logger.warning("Helper connection invalidated")
    }

    private func handleInterruption() {
        Self.logger.warning("Helper connection interrupted")
    }

    public func disconnect() {
        connection?.invalidate()
        connection = nil
    }

    // MARK: - Data Queries

    public func getProcessSnapshot() async throws -> ProcessSnapshot {
        let conn = connect()
        return try await withCheckedThrowingContinuation { continuation in
            let proxy = conn.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: error)
            }
            guard let helper = proxy as? PSHelperProtocol else {
                continuation.resume(throwing: HelperError.connectionFailed)
                return
            }
            helper.getProcessSnapshot { data, error in
                if let error { continuation.resume(throwing: error); return }
                guard let data else { continuation.resume(throwing: HelperError.noData); return }
                do {
                    let snapshot = try JSONDecoder().decode(ProcessSnapshot.self, from: data)
                    continuation.resume(returning: snapshot)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    public func getSystemMetrics() async throws -> SystemMetricsSnapshot {
        let conn = connect()
        return try await withCheckedThrowingContinuation { continuation in
            let proxy = conn.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: error)
            }
            guard let helper = proxy as? PSHelperProtocol else {
                continuation.resume(throwing: HelperError.connectionFailed)
                return
            }
            helper.getSystemMetrics { data, error in
                if let error { continuation.resume(throwing: error); return }
                guard let data else { continuation.resume(throwing: HelperError.noData); return }
                do {
                    let snapshot = try JSONDecoder().decode(SystemMetricsSnapshot.self, from: data)
                    continuation.resume(returning: snapshot)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    public func getNetworkConnections() async throws -> NetworkSnapshot {
        let conn = connect()
        return try await withCheckedThrowingContinuation { continuation in
            let proxy = conn.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: error)
            }
            guard let helper = proxy as? PSHelperProtocol else {
                continuation.resume(throwing: HelperError.connectionFailed)
                return
            }
            helper.getNetworkConnections { data, error in
                if let error { continuation.resume(throwing: error); return }
                guard let data else { continuation.resume(throwing: HelperError.noData); return }
                do {
                    let snapshot = try JSONDecoder().decode(NetworkSnapshot.self, from: data)
                    continuation.resume(returning: snapshot)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    public func getHelperVersion() async throws -> String {
        let conn = connect()
        return try await withCheckedThrowingContinuation { continuation in
            let proxy = conn.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: error)
            }
            guard let helper = proxy as? PSHelperProtocol else {
                continuation.resume(throwing: HelperError.connectionFailed)
                return
            }
            helper.getHelperVersion { version in
                continuation.resume(returning: version)
            }
        }
    }

    // MARK: - Action Methods

    public func killProcess(pid: pid_t, signal: Int32) async throws -> Bool {
        let conn = connect()
        return try await withCheckedThrowingContinuation { continuation in
            let proxy = conn.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: error)
            }
            guard let helper = proxy as? PSHelperProtocol else {
                continuation.resume(throwing: HelperError.connectionFailed)
                return
            }
            helper.killProcess(pid: pid, signal: signal) { success, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: success)
            }
        }
    }
}

// MARK: - Error Types

public enum HelperError: LocalizedError {
    case connectionFailed
    case noData
    case notInstalled

    public var errorDescription: String? {
        switch self {
        case .connectionFailed: "Failed to connect to helper daemon"
        case .noData: "No data received from helper"
        case .notInstalled: "Helper daemon is not installed"
        }
    }
}
