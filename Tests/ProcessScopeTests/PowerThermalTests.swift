import XCTest
@testable import ProcessScope

final class PowerThermalTests: XCTestCase {

    // MARK: - ComponentPower Tests

    func testComponentPowerTotalWatts() {
        let power = IOKitWrapper.ComponentPower(
            cpuPackage: 5.0,
            eCores: 1.0,
            pCores: 4.0,
            gpu: 3.0,
            ane: 0.5,
            dram: 1.5
        )
        // totalWatts sums cpuPackage + gpu + ane + dram (not e/p cores, as they are part of package)
        XCTAssertEqual(power.totalWatts, 10.0, accuracy: 0.001)
    }

    func testComponentPowerTotalWattsWithNils() {
        let power = IOKitWrapper.ComponentPower(
            cpuPackage: 5.0,
            eCores: nil,
            pCores: nil,
            gpu: nil,
            ane: nil,
            dram: nil
        )
        XCTAssertEqual(power.totalWatts, 5.0, accuracy: 0.001)
    }

    func testComponentPowerAllNil() {
        let power = IOKitWrapper.ComponentPower()
        XCTAssertEqual(power.totalWatts, 0.0, accuracy: 0.001)
        XCTAssertTrue(power.breakdown.isEmpty)
    }

    func testComponentPowerBreakdownFiltersNils() {
        let power = IOKitWrapper.ComponentPower(
            cpuPackage: 5.0,
            gpu: 3.0,
            ane: nil,
            dram: 1.5
        )
        let breakdown = power.breakdown
        XCTAssertEqual(breakdown.count, 3)
        XCTAssertEqual(breakdown[0].name, "CPU")
        XCTAssertEqual(breakdown[0].watts, 5.0, accuracy: 0.001)
        XCTAssertEqual(breakdown[1].name, "GPU")
        XCTAssertEqual(breakdown[1].watts, 3.0, accuracy: 0.001)
        XCTAssertEqual(breakdown[2].name, "DRAM")
        XCTAssertEqual(breakdown[2].watts, 1.5, accuracy: 0.001)
    }

    func testComponentPowerCodable() throws {
        let original = IOKitWrapper.ComponentPower(
            cpuPackage: 5.0,
            eCores: 1.0,
            pCores: 4.0,
            gpu: 3.0,
            ane: 0.5,
            dram: 1.5
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(IOKitWrapper.ComponentPower.self, from: data)
        XCTAssertEqual(decoded.cpuPackage, original.cpuPackage)
        XCTAssertEqual(decoded.eCores, original.eCores)
        XCTAssertEqual(decoded.pCores, original.pCores)
        XCTAssertEqual(decoded.gpu, original.gpu)
        XCTAssertEqual(decoded.ane, original.ane)
        XCTAssertEqual(decoded.dram, original.dram)
    }

    // MARK: - BatteryInfo Tests

    func testBatteryHealthComputation() {
        let battery = IOKitWrapper.BatteryInfo(
            currentCapacity: 4000,
            maxCapacity: 4500,
            designCapacity: 5000,
            cycleCount: 200,
            isCharging: false,
            isPluggedIn: false,
            temperature: 30.0,
            voltage: 12500
        )
        // health = maxCapacity / designCapacity = 4500 / 5000 = 0.9
        XCTAssertEqual(battery.health, 0.9, accuracy: 0.001)
        XCTAssertEqual(battery.healthPercent, 90.0, accuracy: 0.001)
    }

    func testBatteryChargePercent() {
        let battery = IOKitWrapper.BatteryInfo(
            currentCapacity: 3750,
            maxCapacity: 5000,
            designCapacity: 5500,
            cycleCount: 100,
            isCharging: true,
            isPluggedIn: true,
            temperature: 28.0,
            voltage: 12000
        )
        // chargePercent = currentCapacity / maxCapacity * 100 = 3750 / 5000 * 100 = 75
        XCTAssertEqual(battery.chargePercent, 75)
    }

    func testBatteryChargePercentZeroMax() {
        let battery = IOKitWrapper.BatteryInfo(
            currentCapacity: 100,
            maxCapacity: 0,
            designCapacity: 5000,
            cycleCount: 0,
            isCharging: false,
            isPluggedIn: false,
            temperature: 25.0,
            voltage: 12000
        )
        XCTAssertEqual(battery.chargePercent, 0)
    }

    func testBatteryHealthZeroDesignCapacity() {
        let battery = IOKitWrapper.BatteryInfo(
            currentCapacity: 100,
            maxCapacity: 5000,
            designCapacity: 0,
            cycleCount: 0,
            isCharging: false,
            isPluggedIn: false,
            temperature: 25.0,
            voltage: 12000
        )
        // When designCapacity is 0, health returns 1.0 (defensive)
        XCTAssertEqual(battery.health, 1.0, accuracy: 0.001)
    }

    func testBatteryInfoCodable() throws {
        let original = IOKitWrapper.BatteryInfo(
            currentCapacity: 4000,
            maxCapacity: 5000,
            designCapacity: 5500,
            cycleCount: 150,
            isCharging: true,
            isPluggedIn: true,
            temperature: 32.5,
            voltage: 12400,
            chargeRateWatts: 35.0,
            timeRemainingMinutes: 45,
            optimizedChargingEnabled: true
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(IOKitWrapper.BatteryInfo.self, from: data)
        XCTAssertEqual(decoded.currentCapacity, 4000)
        XCTAssertEqual(decoded.maxCapacity, 5000)
        XCTAssertEqual(decoded.designCapacity, 5500)
        XCTAssertEqual(decoded.cycleCount, 150)
        XCTAssertEqual(decoded.isCharging, true)
        XCTAssertEqual(decoded.chargeRateWatts, 35.0)
        XCTAssertEqual(decoded.timeRemainingMinutes, 45)
        XCTAssertEqual(decoded.optimizedChargingEnabled, true)
    }

    // MARK: - CPUFrequency Tests

    func testCPUFrequencyIsThrottled() {
        // 89% of max = throttled (below 90%)
        let throttled = IOKitWrapper.CPUFrequency(currentMHz: 2670, maxMHz: 3000)
        XCTAssertTrue(throttled.isThrottled)
    }

    func testCPUFrequencyNotThrottled() {
        // 91% of max = not throttled (at or above 90%)
        let normal = IOKitWrapper.CPUFrequency(currentMHz: 2730, maxMHz: 3000)
        XCTAssertFalse(normal.isThrottled)
    }

    func testCPUFrequencyExactThreshold() {
        // Exactly 90% should not be throttled
        let exact = IOKitWrapper.CPUFrequency(currentMHz: 2700, maxMHz: 3000)
        XCTAssertFalse(exact.isThrottled)
    }

    func testCPUFrequencyZeroMax() {
        // Zero max should not report throttled
        let zeroMax = IOKitWrapper.CPUFrequency(currentMHz: 0, maxMHz: 0)
        XCTAssertFalse(zeroMax.isThrottled)
        XCTAssertEqual(zeroMax.frequencyRatio, 0)
    }

    func testCPUFrequencyRatio() {
        let freq = IOKitWrapper.CPUFrequency(currentMHz: 2400, maxMHz: 3200)
        XCTAssertEqual(freq.frequencyRatio, 0.75, accuracy: 0.001)
    }

    func testCPUFrequencyRatioCapped() {
        // If current exceeds max (turbo boost), ratio is capped at 1.0
        let freq = IOKitWrapper.CPUFrequency(currentMHz: 3500, maxMHz: 3200)
        XCTAssertEqual(freq.frequencyRatio, 1.0, accuracy: 0.001)
    }

    func testCPUFrequencyCodable() throws {
        let original = IOKitWrapper.CPUFrequency(currentMHz: 2400, maxMHz: 3200)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(IOKitWrapper.CPUFrequency.self, from: data)
        XCTAssertEqual(decoded.currentMHz, 2400)
        XCTAssertEqual(decoded.maxMHz, 3200)
    }

    // MARK: - PowerSnapshot Tests

    func testPowerSnapshotWithNilBattery() {
        // Desktop Mac scenario: no battery
        let snapshot = PowerSnapshot(
            componentPower: IOKitWrapper.ComponentPower(cpuPackage: 10.0, gpu: 5.0),
            totalWatts: 15.0,
            frequency: IOKitWrapper.CPUFrequency(currentMHz: 3000, maxMHz: 3200),
            thermalState: 0,
            battery: nil
        )
        XCTAssertNil(snapshot.battery)
        XCTAssertFalse(snapshot.isThrottled)
        XCTAssertEqual(snapshot.totalWatts, 15.0)
    }

    func testPowerSnapshotThermalThrottle() {
        let snapshot = PowerSnapshot(
            thermalState: 2  // "serious" triggers throttle
        )
        XCTAssertTrue(snapshot.isThrottled)
    }

    func testPowerSnapshotFrequencyThrottle() {
        let snapshot = PowerSnapshot(
            frequency: IOKitWrapper.CPUFrequency(currentMHz: 1500, maxMHz: 3200),
            thermalState: 0
        )
        XCTAssertTrue(snapshot.isThrottled)
    }

    func testPowerSnapshotNoThrottle() {
        let snapshot = PowerSnapshot(
            frequency: IOKitWrapper.CPUFrequency(currentMHz: 3000, maxMHz: 3200),
            thermalState: 0
        )
        XCTAssertFalse(snapshot.isThrottled)
    }

    func testPowerSnapshotCodable() throws {
        let original = PowerSnapshot(
            componentPower: IOKitWrapper.ComponentPower(cpuPackage: 5.0, gpu: 3.0),
            totalWatts: 8.0,
            frequency: IOKitWrapper.CPUFrequency(currentMHz: 3000, maxMHz: 3200),
            cpuTemp: 65.0,
            gpuTemp: 55.0,
            thermalState: 1,
            battery: IOKitWrapper.BatteryInfo(
                currentCapacity: 4000,
                maxCapacity: 5000,
                designCapacity: 5500,
                cycleCount: 100,
                isCharging: false,
                isPluggedIn: false,
                temperature: 30.0,
                voltage: 12000
            ),
            fanSpeedRPM: 2000,
            timestamp: Date()
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PowerSnapshot.self, from: data)
        XCTAssertEqual(decoded.totalWatts, 8.0)
        XCTAssertEqual(decoded.thermalState, 1)
        XCTAssertEqual(decoded.cpuTemp, 65.0)
        XCTAssertEqual(decoded.gpuTemp, 55.0)
        XCTAssertEqual(decoded.fanSpeedRPM, 2000)
        XCTAssertNotNil(decoded.battery)
        XCTAssertNotNil(decoded.componentPower)
        XCTAssertNotNil(decoded.frequency)
    }

    // MARK: - IOKitWrapper Graceful Nil Returns

    func testIOKitWrapperGracefulNilReturns() {
        let iokit = IOKitWrapper.shared

        // These should not crash on any hardware, even if data is unavailable
        // They may return nil or a value depending on the machine
        let _ = iokit.perComponentPower()
        let _ = iokit.cpuFrequency()
        let _ = iokit.cpuDieTemperature()
        let _ = iokit.gpuDieTemperature()
        let _ = iokit.batteryInfo()
        let _ = iokit.fanSpeedRPM()
        let _ = iokit.thermalState()

        // If we get here without crashing, the graceful nil return is working
        XCTAssertTrue(true, "IOKitWrapper methods returned without crashing")
    }

    func testThermalStateDescription() {
        XCTAssertEqual(IOKitWrapper.thermalStateDescription(0), "Nominal")
        XCTAssertEqual(IOKitWrapper.thermalStateDescription(1), "Fair")
        XCTAssertEqual(IOKitWrapper.thermalStateDescription(2), "Serious")
        XCTAssertEqual(IOKitWrapper.thermalStateDescription(3), "Critical")
        XCTAssertEqual(IOKitWrapper.thermalStateDescription(99), "Unknown")
    }

    // MARK: - MockPowerCollector Tests

    func testMockPowerCollectorLifecycle() async {
        let mock = MockPowerCollector()
        XCTAssertEqual(mock.activateCount, 0)
        XCTAssertEqual(mock.deactivateCount, 0)

        await mock.activate()
        XCTAssertEqual(mock.activateCount, 1)

        await mock.deactivate()
        XCTAssertEqual(mock.deactivateCount, 1)
    }

    func testMockPowerCollectorProperties() {
        let mock = MockPowerCollector()
        XCTAssertEqual(mock.id, "power-mock")
        XCTAssertEqual(mock.displayName, "Power & Thermal (Mock)")
        XCTAssertEqual(mock.requiresHelper, false)
        XCTAssertTrue(mock.isAvailable)
    }

    // MARK: - PowerThermalModule Registration

    @MainActor
    func testPowerThermalModuleRegistration() {
        let module = PowerThermalModule()
        XCTAssertEqual(module.id, "power")
        XCTAssertEqual(module.displayName, "Power & Thermal")
        XCTAssertEqual(module.symbolName, "bolt.fill")
        XCTAssertEqual(module.category, .hardware)
        XCTAssertTrue(module.isAvailable)
        XCTAssertTrue(module.pollingSubscriptions.contains(.critical))
        XCTAssertTrue(module.pollingSubscriptions.contains(.infrequent))
        XCTAssertEqual(module.collectors.count, 2) // ThermalCollector + PowerCollector
    }

    @MainActor
    func testPowerThermalModuleInRegistry() {
        let registry = ModuleRegistry()
        let module = PowerThermalModule()
        registry.register(module)

        XCTAssertEqual(registry.modules.count, 1)
        XCTAssertEqual(registry.modules.first?.id, "power")
    }
}
