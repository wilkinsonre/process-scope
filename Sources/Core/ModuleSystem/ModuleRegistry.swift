import Foundation
import os
import Combine

// MARK: - Module Protocol

/// Protocol for all ProcessScope modules
public protocol PSModule: AnyObject, Identifiable, Sendable where ID == String {
    var id: String { get }
    var displayName: String { get }
    var symbolName: String { get }   // SF Symbol name
    var category: ModuleCategory { get }
    var isAvailable: Bool { get }

    /// Collectors owned by this module
    var collectors: [any SystemCollector] { get }

    /// Polling tier subscriptions this module needs
    var pollingSubscriptions: Set<PollingTier> { get }

    /// Activate all collectors and resources
    func activate() async

    /// Deactivate all collectors and release resources (zero overhead)
    func deactivate() async
}

public enum ModuleCategory: String, Codable, Sendable, CaseIterable {
    case system = "System"
    case hardware = "Hardware"
    case network = "Network"
    case peripherals = "Peripherals"
    case developer = "Developer"
}

public enum PollingTier: String, Codable, Sendable, CaseIterable, Comparable {
    case critical   // 500ms
    case standard   // 1s
    case extended   // 3s
    case slow       // 10s
    case infrequent // 60s

    public var interval: TimeInterval {
        switch self {
        case .critical: 0.5
        case .standard: 1.0
        case .extended: 3.0
        case .slow: 10.0
        case .infrequent: 60.0
        }
    }

    public static func < (lhs: PollingTier, rhs: PollingTier) -> Bool {
        lhs.interval < rhs.interval
    }
}

// MARK: - Module Registry

/// Central registry for all ProcessScope modules.
/// Drives sidebar, polling subscriptions, and settings.
@MainActor
public final class ModuleRegistry: ObservableObject {
    private static let logger = Logger(subsystem: "com.processscope", category: "ModuleRegistry")

    @Published public private(set) var modules: [any PSModule] = []
    @Published public var enabledModuleIDs: Set<String> {
        didSet { saveState() }
    }
    @Published public var moduleOrder: [String] {
        didSet { saveState() }
    }

    private let defaults = UserDefaults.standard
    private let enabledKey = "moduleRegistry.enabled"
    private let orderKey = "moduleRegistry.order"

    /// Default enabled module IDs
    private static let defaultEnabled: Set<String> = [
        "cpu", "memory", "processes", "gpu", "network", "storage"
    ]

    public init() {
        let savedEnabled = Set(UserDefaults.standard.stringArray(forKey: enabledKey) ?? [])
        let savedOrder = UserDefaults.standard.stringArray(forKey: orderKey) ?? []
        self.enabledModuleIDs = savedEnabled.isEmpty ? Self.defaultEnabled : savedEnabled
        self.moduleOrder = savedOrder
    }

    // MARK: - Registration

    public func register(_ module: any PSModule) {
        guard !modules.contains(where: { $0.id == module.id }) else {
            Self.logger.warning("Module already registered: \(module.id)")
            return
        }
        modules.append(module)
        if !moduleOrder.contains(module.id) {
            moduleOrder.append(module.id)
        }
        Self.logger.info("Registered module: \(module.id)")
    }

    // MARK: - Enable/Disable

    public func setEnabled(_ moduleID: String, enabled: Bool) async {
        if enabled {
            enabledModuleIDs.insert(moduleID)
            if let module = modules.first(where: { $0.id == moduleID }) {
                await module.activate()
            }
        } else {
            enabledModuleIDs.remove(moduleID)
            if let module = modules.first(where: { $0.id == moduleID }) {
                await module.deactivate()
            }
        }
        Self.logger.info("Module \(moduleID) enabled: \(enabled)")
    }

    public func isEnabled(_ moduleID: String) -> Bool {
        enabledModuleIDs.contains(moduleID)
    }

    // MARK: - Ordered Modules

    public var orderedModules: [any PSModule] {
        let moduleMap = Dictionary(uniqueKeysWithValues: modules.map { ($0.id, $0) })
        var ordered: [any PSModule] = []
        for id in moduleOrder {
            if let module = moduleMap[id] { ordered.append(module) }
        }
        // Append any registered but not in order list
        for module in modules where !moduleOrder.contains(module.id) {
            ordered.append(module)
        }
        return ordered
    }

    public var enabledModules: [any PSModule] {
        orderedModules.filter { enabledModuleIDs.contains($0.id) }
    }

    // MARK: - Polling Subscriptions

    /// Returns the set of polling tiers needed by all enabled modules
    public var activePollingTiers: Set<PollingTier> {
        var tiers = Set<PollingTier>()
        for module in enabledModules {
            tiers.formUnion(module.pollingSubscriptions)
        }
        return tiers
    }

    // MARK: - Reorder

    public func moveModule(from source: IndexSet, to destination: Int) {
        moduleOrder.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: - Activation

    public func activateEnabledModules() async {
        for module in enabledModules {
            await module.activate()
        }
    }

    public func deactivateAllModules() async {
        for module in modules {
            await module.deactivate()
        }
    }

    // MARK: - Persistence

    private func saveState() {
        defaults.set(Array(enabledModuleIDs), forKey: enabledKey)
        defaults.set(moduleOrder, forKey: orderKey)
    }
}
