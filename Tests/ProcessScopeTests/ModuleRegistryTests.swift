import XCTest
@testable import ProcessScope

final class ModuleRegistryTests: XCTestCase {

    @MainActor
    func testRegisterModule() {
        let registry = ModuleRegistry()
        let module = CPUModule()
        registry.register(module)

        XCTAssertEqual(registry.modules.count, 1)
        XCTAssertEqual(registry.modules.first?.id, "cpu")
    }

    @MainActor
    func testDuplicateRegistration() {
        let registry = ModuleRegistry()
        let module1 = CPUModule()
        let module2 = CPUModule()
        registry.register(module1)
        registry.register(module2) // Should be ignored

        XCTAssertEqual(registry.modules.count, 1)
    }

    @MainActor
    func testEnableDisable() async {
        let registry = ModuleRegistry()
        let module = CPUModule()
        registry.register(module)

        await registry.setEnabled("cpu", enabled: true)
        XCTAssertTrue(registry.isEnabled("cpu"))

        await registry.setEnabled("cpu", enabled: false)
        XCTAssertFalse(registry.isEnabled("cpu"))
    }

    @MainActor
    func testActivePollingTiers() {
        let registry = ModuleRegistry()
        registry.register(CPUModule())
        registry.register(MemoryModule())

        // Force enable
        registry.enabledModuleIDs = ["cpu", "memory"]

        let tiers = registry.activePollingTiers
        XCTAssertTrue(tiers.contains(.critical)) // Both CPU and Memory need critical
        XCTAssertTrue(tiers.contains(.standard)) // CPU needs standard
    }

    @MainActor
    func testDisabledModuleZeroPolling() {
        let registry = ModuleRegistry()
        registry.register(CPUModule())

        // Disable all
        registry.enabledModuleIDs = []

        XCTAssertTrue(registry.activePollingTiers.isEmpty)
        XCTAssertTrue(registry.enabledModules.isEmpty)
    }

    @MainActor
    func testModuleOrdering() {
        let registry = ModuleRegistry()
        registry.register(CPUModule())
        registry.register(MemoryModule())
        registry.register(GPUModule())

        registry.moduleOrder = ["gpu", "cpu", "memory"]

        let ordered = registry.orderedModules
        XCTAssertEqual(ordered[0].id, "gpu")
        XCTAssertEqual(ordered[1].id, "cpu")
        XCTAssertEqual(ordered[2].id, "memory")
    }
}
