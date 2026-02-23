import Foundation
import os

// MARK: - Speed Test Data Types

/// Result of a network speed test using Apple's networkQuality tool
public struct SpeedTestResult: Codable, Sendable {
    public let downloadMbps: Double
    public let uploadMbps: Double
    public let rpm: Int
    public let timestamp: Date

    public init(downloadMbps: Double, uploadMbps: Double, rpm: Int, timestamp: Date) {
        self.downloadMbps = downloadMbps
        self.uploadMbps = uploadMbps
        self.rpm = rpm
        self.timestamp = timestamp
    }

    /// Human-readable responsiveness quality derived from RPM
    public var responsivenessQuality: String {
        switch rpm {
        case 0..<200: return "Low"
        case 200..<500: return "Moderate"
        case 500..<800: return "Good"
        case 800..<1200: return "High"
        default: return "Excellent"
        }
    }
}

/// Current state of the speed test runner
public enum SpeedTestState: Sendable {
    case idle
    case running
    case completed(SpeedTestResult)
    case failed(String)
}

/// Raw JSON structure from networkQuality -c output
struct NetworkQualityOutput: Codable {
    let dl_throughput: Double
    let ul_throughput: Double
    let responsiveness: Int

    // Optional fields that may not always be present
    let dl_flows: Int?
    let ul_flows: Int?
    let base_rtt: Int?
}

// MARK: - Speed Test Runner Protocol

/// Protocol for speed test execution, enabling mock injection for tests
public protocol SpeedTestRunning: AnyObject, Sendable {
    func run() async throws -> SpeedTestResult
    func currentState() async -> SpeedTestState
}

// MARK: - Speed Test Runner

/// Runs Apple's built-in `networkQuality` tool to measure download/upload
/// throughput and responsiveness (RPM).
///
/// Runs on a low-priority queue to avoid blocking the UI thread.
/// Times out after 30 seconds. Only available on macOS 12+.
///
/// Can be triggered on-demand or auto-run on the Infrequent polling tier (60s).
public actor SpeedTestRunner: SpeedTestRunning {

    private let logger = Logger(subsystem: "com.processscope", category: "SpeedTestRunner")
    private var _state: SpeedTestState = .idle
    private var runningProcess: Process?
    private static let toolPath = "/usr/bin/networkQuality"
    private static let timeoutSeconds: TimeInterval = 30

    public init() {}

    /// Returns the current state of the speed test
    public func currentState() -> SpeedTestState { _state }

    // MARK: - Execution

    /// Runs the speed test and returns the result
    ///
    /// Launches `/usr/bin/networkQuality -v -c` in a subprocess,
    /// parses the JSON output, and returns structured results.
    ///
    /// - Throws: `SpeedTestError` if the tool is not found, times out, or produces invalid output
    /// - Returns: The speed test result
    public func run() async throws -> SpeedTestResult {
        guard FileManager.default.fileExists(atPath: Self.toolPath) else {
            _state = .failed("networkQuality tool not found")
            throw SpeedTestError.toolNotFound
        }

        if case .running = _state {
            throw SpeedTestError.alreadyRunning
        }

        _state = .running

        do {
            let result = try await executeSpeedTest()
            _state = .completed(result)
            return result
        } catch {
            let message = error.localizedDescription
            _state = .failed(message)
            throw error
        }
    }

    /// Cancel a running speed test
    public func cancel() {
        runningProcess?.terminate()
        runningProcess = nil
        _state = .idle
    }

    // MARK: - Internal

    private func executeSpeedTest() async throws -> SpeedTestResult {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: Self.toolPath)
        task.arguments = ["-c"]  // JSON output
        task.qualityOfService = .utility

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe() // Suppress stderr

        runningProcess = task

        do {
            try task.run()
        } catch {
            runningProcess = nil
            throw SpeedTestError.launchFailed(error.localizedDescription)
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<SpeedTestResult, Error>) in
                // Set up timeout
                nonisolated(unsafe) let timeoutWork = DispatchWorkItem { [weak task] in
                    task?.terminate()
                }
                DispatchQueue.global(qos: .utility).asyncAfter(
                    deadline: .now() + Self.timeoutSeconds,
                    execute: timeoutWork
                )

                nonisolated(unsafe) let capturedTimeoutWork = timeoutWork
                task.terminationHandler = { [weak self] process in
                    capturedTimeoutWork.cancel()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()

                    Task { @Sendable [weak self] in
                        await self?.clearRunningProcess()
                    }

                    guard process.terminationStatus == 0 else {
                        if process.terminationReason == .uncaughtSignal {
                            continuation.resume(throwing: SpeedTestError.timeout)
                        } else {
                            continuation.resume(throwing: SpeedTestError.toolFailed(
                                exitCode: process.terminationStatus
                            ))
                        }
                        return
                    }

                    do {
                        let result = try SpeedTestRunner.parseOutput(data)
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            task.terminate()
        }
    }

    private func clearRunningProcess() {
        runningProcess = nil
    }

    // MARK: - Parsing

    /// Parses the JSON output from networkQuality -c
    ///
    /// The tool outputs throughput in bits per second; this method converts to Mbps.
    ///
    /// - Parameter data: Raw output data from the tool
    /// - Returns: Parsed speed test result
    public static func parseOutput(_ data: Data) throws -> SpeedTestResult {
        guard !data.isEmpty else {
            throw SpeedTestError.emptyOutput
        }

        let decoder = JSONDecoder()
        let output = try decoder.decode(NetworkQualityOutput.self, from: data)

        return SpeedTestResult(
            downloadMbps: output.dl_throughput / 1_000_000.0,
            uploadMbps: output.ul_throughput / 1_000_000.0,
            rpm: output.responsiveness,
            timestamp: Date()
        )
    }
}

// MARK: - Speed Test Errors

/// Errors that can occur during speed test execution
public enum SpeedTestError: LocalizedError {
    case toolNotFound
    case alreadyRunning
    case launchFailed(String)
    case timeout
    case toolFailed(exitCode: Int32)
    case emptyOutput
    case parseError(String)

    public var errorDescription: String? {
        switch self {
        case .toolNotFound: "networkQuality tool not found at /usr/bin/networkQuality"
        case .alreadyRunning: "A speed test is already running"
        case .launchFailed(let reason): "Failed to launch speed test: \(reason)"
        case .timeout: "Speed test timed out after 30 seconds"
        case .toolFailed(let code): "Speed test failed with exit code \(code)"
        case .emptyOutput: "Speed test produced no output"
        case .parseError(let reason): "Failed to parse speed test output: \(reason)"
        }
    }
}

// MARK: - Mock Speed Test Runner

/// Mock runner for testing speed test UI without running the actual tool
public final class MockSpeedTestRunner: SpeedTestRunning, @unchecked Sendable {
    public var mockResult: SpeedTestResult?
    public var mockError: Error?
    public var mockState: SpeedTestState = .idle
    public private(set) var runCount = 0

    public init() {}

    public func run() async throws -> SpeedTestResult {
        runCount += 1
        if let error = mockError { throw error }
        guard let result = mockResult else {
            throw SpeedTestError.emptyOutput
        }
        return result
    }

    public func currentState() async -> SpeedTestState { mockState }
}
