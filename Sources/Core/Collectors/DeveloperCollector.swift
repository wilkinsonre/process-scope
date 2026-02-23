import Foundation
import AppKit
import os

// MARK: - Running IDE

/// Represents a running IDE or code editor detected by bundle ID
public struct RunningIDE: Codable, Sendable, Identifiable, Equatable {
    /// Unique identifier from PID
    public var id: Int32 { pid }

    /// Display name of the IDE (e.g. "Xcode", "Visual Studio Code")
    public let name: String

    /// Process ID
    public let pid: pid_t

    /// Bundle identifier (e.g. "com.apple.dt.Xcode")
    public let bundleID: String

    public init(name: String, pid: pid_t, bundleID: String) {
        self.name = name
        self.pid = pid
        self.bundleID = bundleID
    }

    /// SF Symbol representing this IDE
    public var symbolName: String {
        switch bundleID {
        case let b where b.contains("Xcode"):
            return "hammer"
        case let b where b.contains("VSCode") || b.contains("VSCodium"):
            return "chevron.left.forwardslash.chevron.right"
        case let b where b.contains("jetbrains"):
            return "sparkle"
        case let b where b.contains("sublimetext"):
            return "text.cursor"
        case let b where b.contains("iterm2"):
            return "terminal"
        default:
            return "app"
        }
    }
}

// MARK: - Active Build

/// Represents an active build process detected by process inspection
public struct ActiveBuild: Codable, Sendable, Identifiable, Equatable {
    /// Unique identifier from PID
    public var id: Int32 { pid }

    /// Build tool name (e.g. "xcodebuild", "swift build", "cargo")
    public let tool: String

    /// Process ID of the build tool
    public let pid: pid_t

    /// Project path if detectable from working directory
    public let projectPath: String?

    /// Elapsed time since build started
    public let startTime: Date?

    public init(tool: String, pid: pid_t, projectPath: String? = nil, startTime: Date? = nil) {
        self.tool = tool
        self.pid = pid
        self.projectPath = projectPath
        self.startTime = startTime
    }

    /// SF Symbol for the build tool
    public var symbolName: String {
        switch tool.lowercased() {
        case let t where t.contains("xcode") || t.contains("xcbuild"):
            return "hammer.fill"
        case let t where t.contains("swift"):
            return "swift"
        case let t where t.contains("cargo"):
            return "shippingbox"
        case let t where t.contains("go"):
            return "globe"
        case let t where t.contains("npm") || t.contains("yarn"):
            return "shippingbox.fill"
        case let t where t.contains("make") || t.contains("cmake"):
            return "wrench"
        case let t where t.contains("gradle"):
            return "building.2"
        default:
            return "gearshape"
        }
    }
}

// MARK: - Developer Snapshot

/// A point-in-time snapshot of developer environment state
public struct DeveloperSnapshot: Codable, Sendable {
    /// Running IDEs and code editors
    public let runningIDEs: [RunningIDE]

    /// Active build processes
    public let activeBuilds: [ActiveBuild]

    /// Whether Docker is available (socket exists)
    public let dockerAvailable: Bool

    /// Number of Docker containers (running + stopped), -1 if Docker unavailable
    public let dockerContainerCount: Int

    /// Timestamp of collection
    public let timestamp: Date

    public init(
        runningIDEs: [RunningIDE] = [],
        activeBuilds: [ActiveBuild] = [],
        dockerAvailable: Bool = false,
        dockerContainerCount: Int = -1,
        timestamp: Date = Date()
    ) {
        self.runningIDEs = runningIDEs
        self.activeBuilds = activeBuilds
        self.dockerAvailable = dockerAvailable
        self.dockerContainerCount = dockerContainerCount
        self.timestamp = timestamp
    }

    /// Whether any IDE is running
    public var hasRunningIDEs: Bool {
        !runningIDEs.isEmpty
    }

    /// Whether any build is in progress
    public var hasActiveBuilds: Bool {
        !activeBuilds.isEmpty
    }
}

// MARK: - Developer Collector Protocol

/// Protocol for developer environment collection, enabling mock injection for tests
public protocol DeveloperCollecting: SystemCollector, Sendable {
    /// Collects a snapshot of the developer environment
    func collect() async -> DeveloperSnapshot
}

// MARK: - Developer Collector

/// Collects developer environment information including running IDEs,
/// active build processes, and Docker availability.
///
/// Uses `NSRunningApplication` for IDE detection, process inspection via
/// `SysctlWrapper` for build detection, and file system checks for Docker
/// socket availability.
///
/// Registered with ``DeveloperModule`` on the extended (3s) polling tier.
public actor DeveloperCollector: DeveloperCollecting {
    public nonisolated let id = "developer"
    public nonisolated let displayName = "Developer"
    public nonisolated let requiresHelper = false
    public nonisolated var isAvailable: Bool { true }

    private let logger = Logger(subsystem: "com.processscope", category: "DeveloperCollector")
    private var _isActive = false

    /// Known IDE bundle ID prefixes mapped to display names
    private static let knownIDEs: [(prefix: String, name: String)] = [
        ("com.apple.dt.Xcode", "Xcode"),
        ("com.microsoft.VSCode", "Visual Studio Code"),
        ("com.vscodium", "VSCodium"),
        ("com.jetbrains.intellij", "IntelliJ IDEA"),
        ("com.jetbrains.CLion", "CLion"),
        ("com.jetbrains.pycharm", "PyCharm"),
        ("com.jetbrains.WebStorm", "WebStorm"),
        ("com.jetbrains.goland", "GoLand"),
        ("com.jetbrains.rider", "Rider"),
        ("com.jetbrains.rustrover", "RustRover"),
        ("com.jetbrains.fleet", "Fleet"),
        ("com.sublimehq.Sublime-Text", "Sublime Text"),
        ("com.googlecode.iterm2", "iTerm2"),
        ("dev.zed.Zed", "Zed"),
        ("com.panic.Nova", "Nova"),
        ("com.barebones.bbedit", "BBEdit"),
    ]

    /// Known build tool process names
    private static let buildTools: Set<String> = [
        "xcodebuild", "XCBBuildService",
        "swift-build", "swiftc",
        "cargo",
        "make", "cmake", "ninja",
        "gradle", "gradlew",
        "go",
        "npm", "yarn", "pnpm",
        "rustc",
    ]

    public init() {}

    public func activate() {
        _isActive = true
        logger.info("DeveloperCollector activated")
    }

    public func deactivate() {
        _isActive = false
        logger.info("DeveloperCollector deactivated")
    }

    // MARK: - Collection

    /// Collect a snapshot of the developer environment
    public func collect() async -> DeveloperSnapshot {
        guard _isActive else {
            return DeveloperSnapshot()
        }

        let ides = await detectRunningIDEs()
        let builds = detectActiveBuilds()
        let dockerInfo = detectDocker()

        return DeveloperSnapshot(
            runningIDEs: ides,
            activeBuilds: builds,
            dockerAvailable: dockerInfo.available,
            dockerContainerCount: dockerInfo.containerCount,
            timestamp: Date()
        )
    }

    // MARK: - IDE Detection

    /// Detect running IDEs by scanning NSRunningApplication for known bundle IDs
    @MainActor
    private func detectRunningIDEs() -> [RunningIDE] {
        let runningApps = NSWorkspace.shared.runningApplications
        var ides: [RunningIDE] = []

        for app in runningApps {
            guard let bundleID = app.bundleIdentifier else { continue }

            for (prefix, displayName) in Self.knownIDEs {
                if bundleID.hasPrefix(prefix) {
                    ides.append(RunningIDE(
                        name: app.localizedName ?? displayName,
                        pid: app.processIdentifier,
                        bundleID: bundleID
                    ))
                    break
                }
            }
        }

        return ides
    }

    // MARK: - Build Detection

    /// Detect active build processes by inspecting the process list
    private func detectActiveBuilds() -> [ActiveBuild] {
        let allProcs = SysctlWrapper.allProcesses()
        var builds: [ActiveBuild] = []

        for proc in allProcs {
            let pid = proc.kp_proc.p_pid
            guard pid > 0 else { continue }

            let name = LibProcWrapper.processName(for: pid) ?? ""
            guard Self.buildTools.contains(name) else { continue }

            // Filter out non-build invocations (e.g. "go" without "build" arg)
            if name == "go" || name == "npm" || name == "yarn" || name == "pnpm" {
                guard isBuildInvocation(pid: pid, toolName: name) else { continue }
            }

            // Skip compiler processes that are children of known build tools
            // (we want the top-level build tool, not individual swiftc/rustc invocations)
            if name == "swiftc" || name == "rustc" {
                let ppid = proc.kp_eproc.e_ppid
                let parentName = LibProcWrapper.processName(for: ppid) ?? ""
                if Self.buildTools.contains(parentName) {
                    continue
                }
            }

            let startTime = Date(
                timeIntervalSince1970: TimeInterval(proc.kp_proc.p_starttime.tv_sec)
            )
            let workDir = LibProcWrapper.workingDirectory(for: pid)

            let toolName = Self.friendlyToolName(name)

            builds.append(ActiveBuild(
                tool: toolName,
                pid: pid,
                projectPath: workDir,
                startTime: startTime
            ))
        }

        return builds
    }

    /// Check if a process invocation is a build command (not just the tool running)
    private func isBuildInvocation(pid: pid_t, toolName: String) -> Bool {
        guard let argsResult = SysctlWrapper.processArguments(for: pid) else {
            return false
        }
        let args = argsResult.arguments

        switch toolName {
        case "go":
            return args.contains("build") || args.contains("install") || args.contains("test")
        case "npm":
            return args.contains("run") || args.contains("build") || args.contains("test") || args.contains("start")
        case "yarn", "pnpm":
            return args.contains("build") || args.contains("dev") || args.contains("start") || args.contains("test")
        default:
            return true
        }
    }

    /// Convert process name to a friendlier display name
    private static func friendlyToolName(_ processName: String) -> String {
        switch processName {
        case "xcodebuild": return "Xcode Build"
        case "XCBBuildService": return "Xcode Build Service"
        case "swift-build": return "Swift Package Manager"
        case "swiftc": return "Swift Compiler"
        case "cargo": return "Cargo (Rust)"
        case "make": return "Make"
        case "cmake": return "CMake"
        case "ninja": return "Ninja"
        case "gradle", "gradlew": return "Gradle"
        case "go": return "Go"
        case "npm": return "npm"
        case "yarn": return "Yarn"
        case "pnpm": return "pnpm"
        case "rustc": return "Rust Compiler"
        default: return processName
        }
    }

    // MARK: - Docker Detection

    /// Check Docker socket availability and container count
    private func detectDocker() -> (available: Bool, containerCount: Int) {
        let socketPaths = [
            "/var/run/docker.sock",
            NSHomeDirectory() + "/.colima/default/docker.sock",
            NSHomeDirectory() + "/.orbstack/run/docker.sock",
        ]

        let available = socketPaths.contains { path in
            FileManager.default.fileExists(atPath: path)
        }

        // Container count would require Docker API access; return -1 if unavailable
        // The DockerDetailView handles full Docker integration
        return (available, available ? 0 : -1)
    }
}

// MARK: - Mock Developer Collector

/// Mock developer collector for testing
public final class MockDeveloperCollector: DeveloperCollecting, @unchecked Sendable {
    public let id = "developer-mock"
    public let displayName = "Developer (Mock)"
    public let requiresHelper = false
    public var isAvailable: Bool = true

    public var mockSnapshot: DeveloperSnapshot = DeveloperSnapshot()
    public private(set) var activateCount = 0
    public private(set) var deactivateCount = 0

    public init() {}

    public func activate() async { activateCount += 1 }
    public func deactivate() async { deactivateCount += 1 }

    public func collect() async -> DeveloperSnapshot {
        mockSnapshot
    }
}
