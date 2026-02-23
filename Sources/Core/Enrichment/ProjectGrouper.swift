import Foundation

/// Groups processes by their inferred project root directory
///
/// Walks up from each process's working directory looking for common
/// project indicators (.git, package.json, Cargo.toml, etc.) and
/// groups processes that share the same project root.
public enum ProjectGrouper {

    /// A group of processes sharing a common project root directory
    public struct ProjectGroup: Identifiable, Sendable {
        public var id: String { rootDirectory }
        public let rootDirectory: String
        public let displayName: String
        public let processes: [ProcessRecord]

        /// Total RSS memory of all processes in this group
        public var totalRSS: UInt64 { processes.reduce(0) { $0 + $1.rssBytes } }

        /// Number of processes in this group
        public var count: Int { processes.count }
    }

    /// Groups processes by project root directory
    /// - Parameter processes: Flat list of process records
    /// - Returns: Array of project groups sorted by total RSS (descending)
    public static func group(_ processes: [ProcessRecord]) -> [ProjectGroup] {
        var groups: [String: [ProcessRecord]] = [:]

        for process in processes {
            guard let workDir = process.workingDirectory,
                  workDir != "/" && workDir != "/usr" else { continue }

            let projectRoot = inferProjectRoot(from: workDir)
            groups[projectRoot, default: []].append(process)
        }

        return groups.map { root, procs in
            ProjectGroup(
                rootDirectory: root,
                displayName: URL(fileURLWithPath: root).lastPathComponent,
                processes: procs.sorted { $0.name < $1.name }
            )
        }
        .sorted { $0.totalRSS > $1.totalRSS }
    }

    // MARK: - Project Root Inference

    /// Infers the project root from a working directory
    /// Walks up looking for .git, package.json, Cargo.toml, etc.
    private static func inferProjectRoot(from path: String) -> String {
        let projectIndicators: Set<String> = [
            ".git", "package.json", "Cargo.toml", "go.mod", "Gemfile",
            "pyproject.toml", "setup.py", "Makefile", "CMakeLists.txt",
            "Package.swift", ".xcodeproj", ".xcworkspace", "build.gradle",
            "pom.xml", "composer.json", "mix.exs", "Dockerfile"
        ]

        var current = path
        let fm = FileManager.default

        while current != "/" && current != "/Users" {
            for indicator in projectIndicators {
                let checkPath = (current as NSString).appendingPathComponent(indicator)
                if fm.fileExists(atPath: checkPath) {
                    return current
                }
            }
            current = (current as NSString).deletingLastPathComponent
        }

        // No project root found -- use the original directory
        return path
    }
}
