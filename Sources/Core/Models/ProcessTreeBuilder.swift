import Foundation

/// A node in the process tree
public final class ProcessTreeNode: Identifiable, Sendable {
    public let process: ProcessRecord
    public let children: [ProcessTreeNode]
    public var id: pid_t { process.pid }

    /// Enriched label from ProcessEnricher (set post-construction)
    public let enrichedLabel: String?

    /// CPU usage percentage (computed from delta)
    public let cpuPercent: Double

    /// Memory in bytes
    public var memoryBytes: UInt64 { process.rssBytes }

    public init(process: ProcessRecord, children: [ProcessTreeNode] = [],
                enrichedLabel: String? = nil, cpuPercent: Double = 0) {
        self.process = process
        self.children = children
        self.enrichedLabel = enrichedLabel
        self.cpuPercent = cpuPercent
    }
}

/// Builds a parent-child tree from a flat process list
public enum ProcessTreeBuilder {

    /// Builds the process tree from a flat list of ProcessRecords
    public static func buildTree(from processes: [ProcessRecord],
                                  cpuPercentages: [pid_t: Double] = [:],
                                  enrichedLabels: [pid_t: String] = [:]) -> [ProcessTreeNode] {
        // Group processes by parent PID
        var childrenMap: [pid_t: [ProcessRecord]] = [:]
        var processMap: [pid_t: ProcessRecord] = [:]

        for process in processes {
            processMap[process.pid] = process
            childrenMap[process.ppid, default: []].append(process)
        }

        // Find root processes (ppid=0 or ppid=1, or parent not in list)
        let rootProcesses = processes.filter { proc in
            proc.ppid == 0 || proc.ppid == 1 || processMap[proc.ppid] == nil
        }

        func buildNode(for process: ProcessRecord) -> ProcessTreeNode {
            let children = (childrenMap[process.pid] ?? [])
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                .map { buildNode(for: $0) }

            return ProcessTreeNode(
                process: process,
                children: children,
                enrichedLabel: enrichedLabels[process.pid],
                cpuPercent: cpuPercentages[process.pid] ?? 0
            )
        }

        return rootProcesses
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { buildNode(for: $0) }
    }

    /// Flattens the tree back to a list (for search/filter operations)
    public static func flatten(_ nodes: [ProcessTreeNode]) -> [ProcessTreeNode] {
        var result: [ProcessTreeNode] = []
        func walk(_ node: ProcessTreeNode) {
            result.append(node)
            for child in node.children { walk(child) }
        }
        nodes.forEach { walk($0) }
        return result
    }

    /// Finds a node by PID in the tree
    public static func find(pid: pid_t, in nodes: [ProcessTreeNode]) -> ProcessTreeNode? {
        for node in nodes {
            if node.process.pid == pid { return node }
            if let found = find(pid: pid, in: node.children) { return found }
        }
        return nil
    }

    /// Returns the parent chain from root to the given PID
    public static func parentChain(for pid: pid_t, in nodes: [ProcessTreeNode]) -> [ProcessTreeNode] {
        var chain: [ProcessTreeNode] = []
        func search(_ node: ProcessTreeNode) -> Bool {
            if node.process.pid == pid { chain.append(node); return true }
            for child in node.children {
                if search(child) { chain.insert(node, at: 0); return true }
            }
            return false
        }
        for node in nodes { if search(node) { break } }
        return chain
    }
}
