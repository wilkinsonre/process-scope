import XCTest
@testable import ProcessScope

// MARK: - AlertRule Tests

final class AlertRuleTests: XCTestCase {

    func testAlertRuleCreation() {
        let rule = AlertRule(
            name: "Test Rule",
            metric: .cpuUsage,
            condition: .greaterThan,
            threshold: 90,
            duration: 10,
            cooldown: 60,
            severity: .warning,
            soundEnabled: true,
            message: "CPU is high"
        )

        XCTAssertEqual(rule.name, "Test Rule")
        XCTAssertEqual(rule.metric, .cpuUsage)
        XCTAssertEqual(rule.condition, .greaterThan)
        XCTAssertEqual(rule.threshold, 90)
        XCTAssertEqual(rule.duration, 10)
        XCTAssertEqual(rule.cooldown, 60)
        XCTAssertTrue(rule.isEnabled)
        XCTAssertEqual(rule.severity, .warning)
        XCTAssertTrue(rule.soundEnabled)
        XCTAssertEqual(rule.message, "CPU is high")
    }

    func testAlertRuleDefaultValues() {
        let rule = AlertRule(name: "Simple", metric: .cpuUsage, condition: .greaterThan, threshold: 50)

        XCTAssertEqual(rule.duration, 0)
        XCTAssertEqual(rule.cooldown, 60)
        XCTAssertTrue(rule.isEnabled)
        XCTAssertEqual(rule.severity, .warning)
        XCTAssertFalse(rule.soundEnabled)
        XCTAssertNil(rule.message)
    }

    func testAlertRuleCodable() throws {
        let original = AlertRule(
            name: "Codable Test",
            metric: .memoryPressure,
            condition: .lessThan,
            threshold: 20,
            duration: 5,
            cooldown: 120,
            severity: .critical,
            soundEnabled: true,
            message: "Memory low"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AlertRule.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.metric, original.metric)
        XCTAssertEqual(decoded.condition, original.condition)
        XCTAssertEqual(decoded.threshold, original.threshold)
        XCTAssertEqual(decoded.duration, original.duration)
        XCTAssertEqual(decoded.cooldown, original.cooldown)
        XCTAssertEqual(decoded.isEnabled, original.isEnabled)
        XCTAssertEqual(decoded.severity, original.severity)
        XCTAssertEqual(decoded.soundEnabled, original.soundEnabled)
        XCTAssertEqual(decoded.message, original.message)
    }

    func testAlertRuleEquality() {
        let id = UUID()
        let a = AlertRule(id: id, name: "A", metric: .cpuUsage, condition: .greaterThan, threshold: 90)
        let b = AlertRule(id: id, name: "A", metric: .cpuUsage, condition: .greaterThan, threshold: 90)
        let c = AlertRule(name: "C", metric: .cpuUsage, condition: .greaterThan, threshold: 90)

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testConditionDescription() {
        let rule = AlertRule(name: "Test", metric: .cpuUsage, condition: .greaterThan, threshold: 90)
        XCTAssertEqual(rule.conditionDescription, "CPU Usage (%) > 90%")

        let rule2 = AlertRule(name: "Test", metric: .powerWatts, condition: .lessThan, threshold: 10.5)
        XCTAssertEqual(rule2.conditionDescription, "Power Draw (W) < 10.5 W")
    }
}

// MARK: - AlertCondition Tests

final class AlertConditionTests: XCTestCase {

    func testGreaterThan() {
        XCTAssertTrue(AlertCondition.greaterThan.evaluate(value: 95, threshold: 90))
        XCTAssertFalse(AlertCondition.greaterThan.evaluate(value: 90, threshold: 90))
        XCTAssertFalse(AlertCondition.greaterThan.evaluate(value: 85, threshold: 90))
    }

    func testLessThan() {
        XCTAssertTrue(AlertCondition.lessThan.evaluate(value: 5, threshold: 10))
        XCTAssertFalse(AlertCondition.lessThan.evaluate(value: 10, threshold: 10))
        XCTAssertFalse(AlertCondition.lessThan.evaluate(value: 15, threshold: 10))
    }

    func testEquals() {
        XCTAssertTrue(AlertCondition.equals.evaluate(value: 10, threshold: 10))
        XCTAssertTrue(AlertCondition.equals.evaluate(value: 10.0005, threshold: 10)) // within epsilon
        XCTAssertFalse(AlertCondition.equals.evaluate(value: 10.5, threshold: 10))
    }

    func testConditionDisplayNames() {
        XCTAssertEqual(AlertCondition.greaterThan.displayName, "Greater Than")
        XCTAssertEqual(AlertCondition.lessThan.displayName, "Less Than")
        XCTAssertEqual(AlertCondition.equals.displayName, "Equals")
    }

    func testConditionSymbols() {
        XCTAssertEqual(AlertCondition.greaterThan.symbol, ">")
        XCTAssertEqual(AlertCondition.lessThan.symbol, "<")
        XCTAssertEqual(AlertCondition.equals.symbol, "=")
    }

    func testConditionCodable() throws {
        for condition in AlertCondition.allCases {
            let data = try JSONEncoder().encode(condition)
            let decoded = try JSONDecoder().decode(AlertCondition.self, from: data)
            XCTAssertEqual(decoded, condition)
        }
    }
}

// MARK: - AlertMetric Tests

final class AlertMetricTests: XCTestCase {

    func testAllMetricsHaveDisplayNames() {
        for metric in AlertMetric.allCases {
            XCTAssertFalse(metric.displayName.isEmpty, "\(metric.rawValue) should have a display name")
        }
    }

    func testAllMetricsHaveSymbolNames() {
        for metric in AlertMetric.allCases {
            XCTAssertFalse(metric.symbolName.isEmpty, "\(metric.rawValue) should have a symbol name")
        }
    }

    func testMetricCodable() throws {
        for metric in AlertMetric.allCases {
            let data = try JSONEncoder().encode(metric)
            let decoded = try JSONDecoder().decode(AlertMetric.self, from: data)
            XCTAssertEqual(decoded, metric)
        }
    }

    func testMetricCount() {
        XCTAssertEqual(AlertMetric.allCases.count, 8, "Should have 8 alert metrics")
    }
}

// MARK: - AlertSeverity Tests

final class AlertSeverityTests: XCTestCase {

    func testSeverityDisplayNames() {
        XCTAssertEqual(AlertSeverity.info.displayName, "Info")
        XCTAssertEqual(AlertSeverity.warning.displayName, "Warning")
        XCTAssertEqual(AlertSeverity.critical.displayName, "Critical")
    }

    func testSeveritySymbolNames() {
        XCTAssertEqual(AlertSeverity.info.symbolName, "info.circle.fill")
        XCTAssertEqual(AlertSeverity.warning.symbolName, "exclamationmark.triangle.fill")
        XCTAssertEqual(AlertSeverity.critical.symbolName, "exclamationmark.octagon.fill")
    }

    func testSeverityCodable() throws {
        for severity in AlertSeverity.allCases {
            let data = try JSONEncoder().encode(severity)
            let decoded = try JSONDecoder().decode(AlertSeverity.self, from: data)
            XCTAssertEqual(decoded, severity)
        }
    }
}

// MARK: - AlertMetricValues Tests

final class AlertMetricValuesTests: XCTestCase {

    func testValueForMetric() {
        let values = AlertMetricValues(
            cpuUsage: 50,
            memoryPressure: 30,
            thermalState: 1,
            diskUsage: 75,
            processCount: 200,
            gpuUtilization: 60,
            batteryLevel: 80,
            powerWatts: 25
        )

        XCTAssertEqual(values.value(for: .cpuUsage), 50)
        XCTAssertEqual(values.value(for: .memoryPressure), 30)
        XCTAssertEqual(values.value(for: .thermalState), 1)
        XCTAssertEqual(values.value(for: .diskUsage), 75)
        XCTAssertEqual(values.value(for: .processCount), 200)
        XCTAssertEqual(values.value(for: .gpuUtilization), 60)
        XCTAssertEqual(values.value(for: .batteryLevel), 80)
        XCTAssertEqual(values.value(for: .powerWatts), 25)
    }

    func testNilMetricValues() {
        let values = AlertMetricValues()

        for metric in AlertMetric.allCases {
            XCTAssertNil(values.value(for: metric), "\(metric.rawValue) should be nil by default")
        }
    }
}

// MARK: - AlertEvent Tests

final class AlertEventTests: XCTestCase {

    func testEventCreation() {
        let rule = AlertRule(name: "Test", metric: .cpuUsage, condition: .greaterThan, threshold: 90)
        let event = AlertEvent(rule: rule, metricValue: 95, message: "CPU at 95%")

        XCTAssertEqual(event.rule, rule)
        XCTAssertEqual(event.metricValue, 95)
        XCTAssertEqual(event.message, "CPU at 95%")
        XCTAssertFalse(event.isAcknowledged)
        XCTAssertLessThan(Date().timeIntervalSince(event.timestamp), 5.0)
    }

    func testEventCodable() throws {
        let rule = AlertRule(name: "Test", metric: .cpuUsage, condition: .greaterThan, threshold: 90)
        let original = AlertEvent(rule: rule, metricValue: 95, message: "CPU high")

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AlertEvent.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.rule, original.rule)
        XCTAssertEqual(decoded.metricValue, original.metricValue)
        XCTAssertEqual(decoded.message, original.message)
    }
}

// MARK: - AlertEngine Tests

final class AlertEngineTests: XCTestCase {
    private var tempDir: String!
    private var engine: AlertEngine!

    override func setUp() async throws {
        let baseTempDir = NSTemporaryDirectory()
        tempDir = baseTempDir + "processscope-alert-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        engine = AlertEngine(directory: tempDir, maxHistoryCount: 100)
    }

    override func tearDown() async throws {
        if let dir = tempDir {
            try? FileManager.default.removeItem(atPath: dir)
        }
        tempDir = nil
        engine = nil
    }

    // MARK: - Rule Evaluation

    func testMetricAboveThresholdFiresAlert() async {
        let rule = AlertRule(
            name: "CPU High",
            metric: .cpuUsage,
            condition: .greaterThan,
            threshold: 90,
            duration: 0,
            cooldown: 0
        )
        await engine.setRules([rule])

        let metrics = AlertMetricValues(cpuUsage: 95)
        let events = await engine.evaluate(metrics: metrics)

        XCTAssertEqual(events.count, 1, "Should fire one alert when CPU > 90%")
        XCTAssertEqual(events.first?.rule.name, "CPU High")
        XCTAssertEqual(events.first?.metricValue, 95)
    }

    func testMetricBelowThresholdDoesNotFire() async {
        let rule = AlertRule(
            name: "CPU High",
            metric: .cpuUsage,
            condition: .greaterThan,
            threshold: 90,
            duration: 0,
            cooldown: 0
        )
        await engine.setRules([rule])

        let metrics = AlertMetricValues(cpuUsage: 85)
        let events = await engine.evaluate(metrics: metrics)

        XCTAssertTrue(events.isEmpty, "Should not fire when CPU < 90%")
    }

    func testLessThanCondition() async {
        let rule = AlertRule(
            name: "Low Battery",
            metric: .batteryLevel,
            condition: .lessThan,
            threshold: 15,
            duration: 0,
            cooldown: 0
        )
        await engine.setRules([rule])

        let metrics = AlertMetricValues(batteryLevel: 10)
        let events = await engine.evaluate(metrics: metrics)
        XCTAssertEqual(events.count, 1, "Should fire when battery < 15%")

        // Re-evaluate with battery above threshold
        let metrics2 = AlertMetricValues(batteryLevel: 50)
        let events2 = await engine.evaluate(metrics: metrics2)
        XCTAssertTrue(events2.isEmpty, "Should not fire when battery > 15%")
    }

    func testEqualsCondition() async {
        let rule = AlertRule(
            name: "Thermal Normal",
            metric: .thermalState,
            condition: .equals,
            threshold: 2,
            duration: 0,
            cooldown: 0
        )
        await engine.setRules([rule])

        let metrics = AlertMetricValues(thermalState: 2)
        let events = await engine.evaluate(metrics: metrics)
        XCTAssertEqual(events.count, 1, "Should fire when thermal state equals 2")
    }

    // MARK: - Duration (Sustained Condition)

    func testDurationDebounce() async {
        let rule = AlertRule(
            name: "CPU Sustained",
            metric: .cpuUsage,
            condition: .greaterThan,
            threshold: 90,
            duration: 2, // 2 seconds
            cooldown: 0
        )
        await engine.setRules([rule])

        let metrics = AlertMetricValues(cpuUsage: 95)

        // First evaluation: starts tracking but doesn't fire
        let events1 = await engine.evaluate(metrics: metrics)
        XCTAssertTrue(events1.isEmpty, "Should not fire immediately with duration > 0")

        // Verify sustained state is tracking
        let sustained = await engine.getSustainedState()
        XCTAssertNotNil(sustained[rule.id], "Should have started tracking sustained state")

        // Wait for duration to elapse
        try? await Task.sleep(for: .seconds(2.1))

        // Second evaluation: duration has elapsed, should fire
        let events2 = await engine.evaluate(metrics: metrics)
        XCTAssertEqual(events2.count, 1, "Should fire after sustained duration elapses")
    }

    func testDurationResetsWhenConditionDrops() async {
        let rule = AlertRule(
            name: "CPU Sustained",
            metric: .cpuUsage,
            condition: .greaterThan,
            threshold: 90,
            duration: 5,
            cooldown: 0
        )
        await engine.setRules([rule])

        // Start tracking
        let metricsHigh = AlertMetricValues(cpuUsage: 95)
        _ = await engine.evaluate(metrics: metricsHigh)

        let sustained1 = await engine.getSustainedState()
        XCTAssertNotNil(sustained1[rule.id])

        // Condition drops
        let metricsLow = AlertMetricValues(cpuUsage: 50)
        _ = await engine.evaluate(metrics: metricsLow)

        let sustained2 = await engine.getSustainedState()
        XCTAssertNil(sustained2[rule.id], "Sustained state should reset when condition drops")
    }

    // MARK: - Cooldown

    func testCooldownPreventsRefire() async {
        let rule = AlertRule(
            name: "CPU High",
            metric: .cpuUsage,
            condition: .greaterThan,
            threshold: 90,
            duration: 0,
            cooldown: 60 // 60 second cooldown
        )
        await engine.setRules([rule])

        let metrics = AlertMetricValues(cpuUsage: 95)

        // First fire
        let events1 = await engine.evaluate(metrics: metrics)
        XCTAssertEqual(events1.count, 1, "Should fire on first evaluation")

        // Immediate second evaluation -- should be suppressed by cooldown
        let events2 = await engine.evaluate(metrics: metrics)
        XCTAssertTrue(events2.isEmpty, "Should not re-fire within cooldown period")

        let firedTimes = await engine.getLastFiredTimes()
        XCTAssertNotNil(firedTimes[rule.id], "Should have recorded last-fired time")
    }

    func testCooldownAllowsRefireAfterExpiry() async {
        let rule = AlertRule(
            name: "Quick Test",
            metric: .cpuUsage,
            condition: .greaterThan,
            threshold: 90,
            duration: 0,
            cooldown: 1 // 1 second cooldown
        )
        await engine.setRules([rule])

        let metrics = AlertMetricValues(cpuUsage: 95)

        // First fire
        let events1 = await engine.evaluate(metrics: metrics)
        XCTAssertEqual(events1.count, 1)

        // Wait for cooldown
        try? await Task.sleep(for: .seconds(1.1))

        // Should fire again after cooldown
        let events2 = await engine.evaluate(metrics: metrics)
        XCTAssertEqual(events2.count, 1, "Should re-fire after cooldown expires")
    }

    // MARK: - Disabled Rules

    func testDisabledRulesAreSkipped() async {
        let rule = AlertRule(
            name: "Disabled Rule",
            metric: .cpuUsage,
            condition: .greaterThan,
            threshold: 90,
            duration: 0,
            cooldown: 0,
            isEnabled: false
        )
        await engine.setRules([rule])

        let metrics = AlertMetricValues(cpuUsage: 95)
        let events = await engine.evaluate(metrics: metrics)

        XCTAssertTrue(events.isEmpty, "Disabled rules should not fire")
    }

    // MARK: - Multiple Rules

    func testMultipleRulesEvaluated() async {
        let rule1 = AlertRule(
            name: "CPU High",
            metric: .cpuUsage,
            condition: .greaterThan,
            threshold: 90,
            duration: 0,
            cooldown: 0
        )
        let rule2 = AlertRule(
            name: "Memory High",
            metric: .memoryPressure,
            condition: .greaterThan,
            threshold: 80,
            duration: 0,
            cooldown: 0
        )
        let rule3 = AlertRule(
            name: "Disk Full",
            metric: .diskUsage,
            condition: .greaterThan,
            threshold: 90,
            duration: 0,
            cooldown: 0
        )
        await engine.setRules([rule1, rule2, rule3])

        // Only CPU and memory conditions met
        let metrics = AlertMetricValues(cpuUsage: 95, memoryPressure: 85, diskUsage: 50)
        let events = await engine.evaluate(metrics: metrics)

        XCTAssertEqual(events.count, 2, "Should fire 2 alerts (CPU and memory)")
        let names = Set(events.map { $0.rule.name })
        XCTAssertTrue(names.contains("CPU High"))
        XCTAssertTrue(names.contains("Memory High"))
    }

    // MARK: - Missing Metric

    func testMissingMetricDoesNotFire() async {
        let rule = AlertRule(
            name: "GPU High",
            metric: .gpuUtilization,
            condition: .greaterThan,
            threshold: 90,
            duration: 0,
            cooldown: 0
        )
        await engine.setRules([rule])

        // GPU utilization is nil
        let metrics = AlertMetricValues(cpuUsage: 50)
        let events = await engine.evaluate(metrics: metrics)

        XCTAssertTrue(events.isEmpty, "Should not fire when metric is unavailable")
    }

    // MARK: - Alert History

    func testAlertHistoryAppended() async {
        let rule = AlertRule(
            name: "Test",
            metric: .cpuUsage,
            condition: .greaterThan,
            threshold: 90,
            duration: 0,
            cooldown: 0
        )
        await engine.setRules([rule])

        let metrics = AlertMetricValues(cpuUsage: 95)
        _ = await engine.evaluate(metrics: metrics)

        let history = await engine.getHistory()
        XCTAssertEqual(history.count, 1, "History should have one event")
        XCTAssertEqual(history.first?.rule.name, "Test")
    }

    func testAlertHistoryLimitedTo100() async {
        let engine = AlertEngine(directory: tempDir, maxHistoryCount: 5)

        // Create rules with zero cooldown for rapid firing
        var rules: [AlertRule] = []
        for i in 0..<10 {
            rules.append(AlertRule(
                name: "Rule \(i)",
                metric: .cpuUsage,
                condition: .greaterThan,
                threshold: 90,
                duration: 0,
                cooldown: 0
            ))
        }
        await engine.setRules(rules)

        let metrics = AlertMetricValues(cpuUsage: 95)
        _ = await engine.evaluate(metrics: metrics)

        let history = await engine.getHistory()
        XCTAssertLessThanOrEqual(history.count, 5, "History should be capped at maxHistoryCount")
    }

    func testClearHistory() async {
        let rule = AlertRule(
            name: "Test",
            metric: .cpuUsage,
            condition: .greaterThan,
            threshold: 90,
            duration: 0,
            cooldown: 0
        )
        await engine.setRules([rule])

        _ = await engine.evaluate(metrics: AlertMetricValues(cpuUsage: 95))
        let before = await engine.getHistory()
        XCTAssertEqual(before.count, 1)

        await engine.clearHistory()
        let after = await engine.getHistory()
        XCTAssertTrue(after.isEmpty, "History should be empty after clear")
    }

    func testAcknowledgeEvent() async {
        let rule = AlertRule(
            name: "Test",
            metric: .cpuUsage,
            condition: .greaterThan,
            threshold: 90,
            duration: 0,
            cooldown: 0
        )
        await engine.setRules([rule])

        let events = await engine.evaluate(metrics: AlertMetricValues(cpuUsage: 95))
        XCTAssertEqual(events.count, 1)
        let eventID = events[0].id

        let countBefore = await engine.unacknowledgedCount
        XCTAssertEqual(countBefore, 1)

        await engine.acknowledgeEvent(id: eventID)

        let countAfter = await engine.unacknowledgedCount
        XCTAssertEqual(countAfter, 0, "Unacknowledged count should be 0 after acknowledgment")
    }

    func testAcknowledgeAll() async {
        var rules: [AlertRule] = []
        for i in 0..<3 {
            rules.append(AlertRule(
                name: "Rule \(i)",
                metric: .cpuUsage,
                condition: .greaterThan,
                threshold: 90,
                duration: 0,
                cooldown: 0
            ))
        }
        await engine.setRules(rules)

        _ = await engine.evaluate(metrics: AlertMetricValues(cpuUsage: 95))
        let countBefore = await engine.unacknowledgedCount
        XCTAssertEqual(countBefore, 3)

        await engine.acknowledgeAll()
        let countAfter = await engine.unacknowledgedCount
        XCTAssertEqual(countAfter, 0)
    }

    // MARK: - Rule CRUD

    func testAddRule() async {
        await engine.loadRules()
        let initialCount = await engine.getRules().count

        let newRule = AlertRule(name: "New", metric: .processCount, condition: .greaterThan, threshold: 500)
        await engine.addRule(newRule)

        let updatedRules = await engine.getRules()
        XCTAssertEqual(updatedRules.count, initialCount + 1)
        XCTAssertTrue(updatedRules.contains(where: { $0.name == "New" }))
    }

    func testUpdateRule() async {
        let rule = AlertRule(name: "Original", metric: .cpuUsage, condition: .greaterThan, threshold: 90)
        await engine.setRules([rule])

        var updated = rule
        updated.name = "Modified"
        updated.threshold = 80
        await engine.updateRule(updated)

        let rules = await engine.getRules()
        XCTAssertEqual(rules.first?.name, "Modified")
        XCTAssertEqual(rules.first?.threshold, 80)
    }

    func testRemoveRule() async {
        let rule = AlertRule(name: "ToRemove", metric: .cpuUsage, condition: .greaterThan, threshold: 90)
        await engine.setRules([rule])

        await engine.removeRule(id: rule.id)

        let rules = await engine.getRules()
        XCTAssertTrue(rules.isEmpty, "Rules should be empty after removal")
    }

    func testResetToDefaults() async {
        await engine.setRules([])
        let empty = await engine.getRules()
        XCTAssertTrue(empty.isEmpty)

        await engine.resetToDefaults()
        let defaults = await engine.getRules()
        XCTAssertGreaterThanOrEqual(defaults.count, 5, "Should have at least 5 built-in rules")
    }

    // MARK: - Built-in Rules

    func testBuiltInRulesHaveCorrectCount() {
        let builtIn = AlertEngine.builtInRules()
        XCTAssertEqual(builtIn.count, 7, "Should have 7 built-in rules")
    }

    func testBuiltInRulesAreAllEnabled() {
        let builtIn = AlertEngine.builtInRules()
        for rule in builtIn {
            XCTAssertTrue(rule.isEnabled, "Built-in rule '\(rule.name)' should be enabled")
        }
    }

    func testBuiltInRuleSeverities() {
        let builtIn = AlertEngine.builtInRules()
        let severities = builtIn.map { $0.severity }
        XCTAssertTrue(severities.contains(.warning), "Should have at least one warning rule")
        XCTAssertTrue(severities.contains(.critical), "Should have at least one critical rule")
        XCTAssertTrue(severities.contains(.info), "Should have at least one info rule")
    }

    func testBuiltInRuleCPUHigh() {
        let builtIn = AlertEngine.builtInRules()
        let cpuRule = builtIn.first { $0.metric == .cpuUsage }
        XCTAssertNotNil(cpuRule, "Should have a CPU usage rule")
        XCTAssertEqual(cpuRule?.condition, .greaterThan)
        XCTAssertEqual(cpuRule?.threshold, 90)
        XCTAssertGreaterThan(cpuRule?.duration ?? 0, 0, "CPU rule should have sustained duration")
    }

    func testBuiltInRuleMemoryCritical() {
        let builtIn = AlertEngine.builtInRules()
        let memRule = builtIn.first { $0.metric == .memoryPressure }
        XCTAssertNotNil(memRule, "Should have a memory pressure rule")
        XCTAssertEqual(memRule?.severity, .critical)
    }

    func testBuiltInRuleDiskFull() {
        let builtIn = AlertEngine.builtInRules()
        let diskRule = builtIn.first { $0.metric == .diskUsage }
        XCTAssertNotNil(diskRule, "Should have a disk usage rule")
        XCTAssertEqual(diskRule?.severity, .critical)
        XCTAssertEqual(diskRule?.threshold, 90)
    }

    func testBuiltInRuleThermal() {
        let builtIn = AlertEngine.builtInRules()
        let thermalRule = builtIn.first { $0.metric == .thermalState }
        XCTAssertNotNil(thermalRule, "Should have a thermal state rule")
        XCTAssertEqual(thermalRule?.condition, .greaterThan)
    }

    func testBuiltInRuleBattery() {
        let builtIn = AlertEngine.builtInRules()
        let batteryRule = builtIn.first { $0.metric == .batteryLevel }
        XCTAssertNotNil(batteryRule, "Should have a battery level rule")
        XCTAssertEqual(batteryRule?.condition, .lessThan)
        XCTAssertEqual(batteryRule?.threshold, 15)
    }

    // MARK: - Persistence

    func testRulesPersistence() async {
        let rule = AlertRule(name: "Persisted", metric: .cpuUsage, condition: .greaterThan, threshold: 90)
        await engine.setRules([rule])

        // Create a new engine instance pointing to the same directory
        let engine2 = AlertEngine(directory: tempDir)
        await engine2.loadRules()

        let loaded = await engine2.getRules()
        XCTAssertEqual(loaded.count, 1, "Should load persisted rules from disk")
        XCTAssertEqual(loaded.first?.name, "Persisted")
    }

    // MARK: - All Alert Metrics Tested

    func testAllMetricTypesEvaluation() async {
        var rules: [AlertRule] = []
        for metric in AlertMetric.allCases {
            rules.append(AlertRule(
                name: "Test \(metric.rawValue)",
                metric: metric,
                condition: .greaterThan,
                threshold: 0,
                duration: 0,
                cooldown: 0
            ))
        }
        await engine.setRules(rules)

        let metrics = AlertMetricValues(
            cpuUsage: 50,
            memoryPressure: 30,
            thermalState: 1,
            diskUsage: 75,
            processCount: 200,
            gpuUtilization: 60,
            batteryLevel: 80,
            powerWatts: 25
        )

        let events = await engine.evaluate(metrics: metrics)
        XCTAssertEqual(events.count, 8, "All 8 metrics should fire when threshold is 0 and all values > 0")
    }

    // MARK: - Event Message

    func testEventMessageWithCustomMessage() async {
        let rule = AlertRule(
            name: "Custom",
            metric: .cpuUsage,
            condition: .greaterThan,
            threshold: 90,
            duration: 0,
            cooldown: 0,
            message: "Custom alert message"
        )
        await engine.setRules([rule])

        let events = await engine.evaluate(metrics: AlertMetricValues(cpuUsage: 95))
        XCTAssertEqual(events.first?.message, "Custom alert message")
    }

    func testEventMessageWithoutCustomMessage() async {
        let rule = AlertRule(
            name: "Auto",
            metric: .cpuUsage,
            condition: .greaterThan,
            threshold: 90,
            duration: 0,
            cooldown: 0,
            message: nil
        )
        await engine.setRules([rule])

        let events = await engine.evaluate(metrics: AlertMetricValues(cpuUsage: 95))
        let msg = events.first?.message ?? ""
        XCTAssertTrue(msg.contains("CPU Usage"), "Auto message should reference the metric")
        XCTAssertTrue(msg.contains("95"), "Auto message should include the current value")
    }
}

// MARK: - AlertRuleStore (YAML) Tests

final class AlertRuleStoreTests: XCTestCase {

    func testParseYAML() {
        let yaml = """
        rules:
          - name: "CPU High"
            metric: cpuUsage
            condition: greaterThan
            threshold: 90
            duration: 10
            cooldown: 60
            severity: warning
            enabled: true
            sound: false
            message: "CPU above 90%"

          - name: "Low Battery"
            metric: batteryLevel
            condition: lessThan
            threshold: 15
            duration: 0
            cooldown: 300
            severity: critical
            enabled: true
            sound: true
        """

        let rules = AlertRuleStore.parseYAML(yaml)
        XCTAssertNotNil(rules)
        XCTAssertEqual(rules?.count, 2)

        let cpuRule = rules?.first
        XCTAssertEqual(cpuRule?.name, "CPU High")
        XCTAssertEqual(cpuRule?.metric, .cpuUsage)
        XCTAssertEqual(cpuRule?.condition, .greaterThan)
        XCTAssertEqual(cpuRule?.threshold, 90)
        XCTAssertEqual(cpuRule?.duration, 10)
        XCTAssertEqual(cpuRule?.cooldown, 60)
        XCTAssertEqual(cpuRule?.severity, .warning)
        XCTAssertTrue(cpuRule?.isEnabled ?? false)
        XCTAssertFalse(cpuRule?.soundEnabled ?? true)
        XCTAssertEqual(cpuRule?.message, "CPU above 90%")

        let batteryRule = rules?.last
        XCTAssertEqual(batteryRule?.name, "Low Battery")
        XCTAssertEqual(batteryRule?.metric, .batteryLevel)
        XCTAssertEqual(batteryRule?.condition, .lessThan)
        XCTAssertEqual(batteryRule?.threshold, 15)
        XCTAssertEqual(batteryRule?.severity, .critical)
        XCTAssertTrue(batteryRule?.soundEnabled ?? false)
    }

    func testParseInvalidYAML() {
        let yaml = "this is not valid yaml at all"
        let rules = AlertRuleStore.parseYAML(yaml)
        XCTAssertNil(rules, "Invalid YAML should return nil")
    }

    func testParseEmptyYAML() {
        let yaml = ""
        let rules = AlertRuleStore.parseYAML(yaml)
        XCTAssertNil(rules, "Empty YAML should return nil")
    }

    func testExportYAML() {
        let rules = [
            AlertRule(
                name: "Test Rule",
                metric: .cpuUsage,
                condition: .greaterThan,
                threshold: 90,
                duration: 10,
                cooldown: 60,
                severity: .warning,
                soundEnabled: false,
                message: "CPU is high"
            )
        ]

        let yaml = AlertRuleStore.exportYAML(rules)

        XCTAssertTrue(yaml.contains("rules:"))
        XCTAssertTrue(yaml.contains("name: \"Test Rule\""))
        XCTAssertTrue(yaml.contains("metric: cpuUsage"))
        XCTAssertTrue(yaml.contains("condition: greaterThan"))
        XCTAssertTrue(yaml.contains("threshold: 90"))
        XCTAssertTrue(yaml.contains("duration: 10"))
        XCTAssertTrue(yaml.contains("cooldown: 60"))
        XCTAssertTrue(yaml.contains("severity: warning"))
        XCTAssertTrue(yaml.contains("enabled: true"))
        XCTAssertTrue(yaml.contains("sound: false"))
        XCTAssertTrue(yaml.contains("message: \"CPU is high\""))
    }

    func testYAMLRoundTrip() {
        let original = [
            AlertRule(name: "A", metric: .cpuUsage, condition: .greaterThan, threshold: 90, duration: 10, cooldown: 60, severity: .warning, soundEnabled: true, message: "Alert A"),
            AlertRule(name: "B", metric: .batteryLevel, condition: .lessThan, threshold: 15, duration: 0, cooldown: 300, severity: .critical, soundEnabled: false),
        ]

        let yaml = AlertRuleStore.exportYAML(original)
        let parsed = AlertRuleStore.parseYAML(yaml)

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.count, 2)
        XCTAssertEqual(parsed?[0].name, "A")
        XCTAssertEqual(parsed?[0].metric, .cpuUsage)
        XCTAssertEqual(parsed?[0].threshold, 90)
        XCTAssertEqual(parsed?[0].duration, 10)
        XCTAssertEqual(parsed?[0].severity, .warning)
        XCTAssertTrue(parsed?[0].soundEnabled ?? false)
        XCTAssertEqual(parsed?[0].message, "Alert A")

        XCTAssertEqual(parsed?[1].name, "B")
        XCTAssertEqual(parsed?[1].metric, .batteryLevel)
        XCTAssertEqual(parsed?[1].condition, .lessThan)
        XCTAssertEqual(parsed?[1].threshold, 15)
        XCTAssertEqual(parsed?[1].severity, .critical)
        XCTAssertFalse(parsed?[1].soundEnabled ?? true)
    }
}

// MARK: - MockAlertNotifier Tests

final class MockAlertNotifierTests: XCTestCase {

    func testMockDelivery() async {
        let mock = MockAlertNotifier()
        let rule = AlertRule(name: "Test", metric: .cpuUsage, condition: .greaterThan, threshold: 90)
        let event = AlertEvent(rule: rule, metricValue: 95, message: "Test alert")

        await mock.deliver(event: event)

        XCTAssertEqual(mock.deliveredEvents.count, 1)
        XCTAssertEqual(mock.deliveredEvents.first?.message, "Test alert")
    }

    func testMockPermission() async {
        let mock = MockAlertNotifier()
        mock.grantPermission = true

        let granted = await mock.requestPermission()
        XCTAssertTrue(granted)
        XCTAssertTrue(mock.permissionRequested)
    }

    func testMockBadge() async {
        let mock = MockAlertNotifier()
        await mock.updateBadge(count: 5)
        XCTAssertEqual(mock.lastBadgeCount, 5)

        await mock.clearBadge()
        XCTAssertEqual(mock.lastBadgeCount, 0)
    }

    func testMockReset() async {
        let mock = MockAlertNotifier()
        let rule = AlertRule(name: "Test", metric: .cpuUsage, condition: .greaterThan, threshold: 90)
        let event = AlertEvent(rule: rule, metricValue: 95, message: "Test")

        await mock.deliver(event: event)
        _ = await mock.requestPermission()
        await mock.updateBadge(count: 3)

        mock.reset()

        XCTAssertTrue(mock.deliveredEvents.isEmpty)
        XCTAssertFalse(mock.permissionRequested)
        XCTAssertEqual(mock.lastBadgeCount, 0)
    }
}
