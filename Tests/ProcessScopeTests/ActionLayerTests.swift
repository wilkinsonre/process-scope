import XCTest
@testable import ProcessScope

// MARK: - ActionConfiguration Tests

final class ActionConfigurationTests: XCTestCase {

    /// Reset all AppStorage keys used by ActionConfiguration before each test
    /// so that values set during one test do not leak into another.
    override func setUp() {
        let keys = [
            "action.process.kill",
            "action.process.forceKill",
            "action.process.suspend",
            "action.process.renice",
            "action.storage.eject",
            "action.storage.forceEject",
            "action.clipboard.copy",
            "action.docker.lifecycle",
            "action.docker.remove",
            "action.network.enabled",
            "action.network.sshTerminal",
            "action.network.pingTrace",
            "action.network.dnsFlush",
            "action.network.dnsLookup",
            "action.system.enabled",
            "action.system.purge",
            "action.system.restartServices",
            "action.system.power",
            "action.confirm.destructive",
            "action.confirm.skipReversible",
        ]
        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    @MainActor
    func testAllActionsDisabledByDefault() {
        let config = ActionConfiguration()
        XCTAssertFalse(config.processKillEnabled, "processKillEnabled should default to false")
        XCTAssertFalse(config.processForceKillEnabled, "processForceKillEnabled should default to false")
        XCTAssertFalse(config.processSuspendEnabled, "processSuspendEnabled should default to false")
        XCTAssertFalse(config.processReniceEnabled, "processReniceEnabled should default to false")
        XCTAssertFalse(config.storageEjectEnabled, "storageEjectEnabled should default to false")
        XCTAssertFalse(config.storageForceEjectEnabled, "storageForceEjectEnabled should default to false")
    }

    @MainActor
    func testClipboardEnabledByDefault() {
        let config = ActionConfiguration()
        XCTAssertTrue(config.clipboardCopyEnabled, "clipboardCopyEnabled should default to true")
    }

    @MainActor
    func testActionAllowedWhenEnabled() {
        let config = ActionConfiguration()
        config.processKillEnabled = true
        XCTAssertTrue(config.isActionAllowed(.killProcess), "killProcess should be allowed when processKillEnabled is true")
    }

    @MainActor
    func testActionBlockedWhenDisabled() {
        let config = ActionConfiguration()
        // processKillEnabled defaults to false
        XCTAssertFalse(config.isActionAllowed(.killProcess), "killProcess should be blocked when processKillEnabled is false")
    }

    @MainActor
    func testHelperRequiredActions() {
        let config = ActionConfiguration()
        let required = config.helperRequiredActions
        // These actions require the helper per ActionType.requiresHelper
        XCTAssertTrue(required.contains(ActionType.forceEjectVolume.rawValue), "forceEjectVolume should require helper")
        XCTAssertTrue(required.contains(ActionType.flushDNS.rawValue), "flushDNS should require helper")
        XCTAssertTrue(required.contains(ActionType.purgeMemory.rawValue), "purgeMemory should require helper")
        XCTAssertTrue(required.contains(ActionType.networkKillConnection.rawValue), "networkKillConnection should require helper")
        XCTAssertTrue(required.contains(ActionType.reniceProcess.rawValue), "reniceProcess should require helper")
        // copyToClipboard should NOT require helper
        XCTAssertFalse(required.contains(ActionType.copyToClipboard.rawValue), "copyToClipboard should not require helper")
    }

    @MainActor
    func testIsBlockedByMissingHelper() {
        let config = ActionConfiguration()
        // forceEjectVolume requires helper -- blocked when helper is not installed
        XCTAssertTrue(config.isBlockedByMissingHelper(.forceEjectVolume, helperInstalled: false))
        // Not blocked when helper is installed
        XCTAssertFalse(config.isBlockedByMissingHelper(.forceEjectVolume, helperInstalled: true))
        // copyToClipboard does not require helper -- never blocked
        XCTAssertFalse(config.isBlockedByMissingHelper(.copyToClipboard, helperInstalled: false))
    }

    @MainActor
    func testActionAllowedForEachCategoryWhenEnabled() {
        let config = ActionConfiguration()

        // Process actions
        config.processKillEnabled = true
        XCTAssertTrue(config.isActionAllowed(.killProcess))
        XCTAssertTrue(config.isActionAllowed(.killProcessGroup))

        config.processForceKillEnabled = true
        XCTAssertTrue(config.isActionAllowed(.forceKillProcess))
        XCTAssertTrue(config.isActionAllowed(.forceQuitApp))

        config.processSuspendEnabled = true
        XCTAssertTrue(config.isActionAllowed(.suspendProcess))
        XCTAssertTrue(config.isActionAllowed(.resumeProcess))

        config.processReniceEnabled = true
        XCTAssertTrue(config.isActionAllowed(.reniceProcess))

        // Storage actions
        config.storageEjectEnabled = true
        XCTAssertTrue(config.isActionAllowed(.ejectVolume))

        config.storageForceEjectEnabled = true
        XCTAssertTrue(config.isActionAllowed(.forceEjectVolume))
        XCTAssertTrue(config.isActionAllowed(.unmountVolume))

        // Clipboard actions (enabled by default)
        XCTAssertTrue(config.isActionAllowed(.copyToClipboard))
        XCTAssertTrue(config.isActionAllowed(.revealInFinder))

        // Docker actions
        config.dockerLifecycleEnabled = true
        XCTAssertTrue(config.isActionAllowed(.dockerStop))
        XCTAssertTrue(config.isActionAllowed(.dockerStart))
        XCTAssertTrue(config.isActionAllowed(.dockerRestart))
        XCTAssertTrue(config.isActionAllowed(.dockerPause))
        XCTAssertTrue(config.isActionAllowed(.dockerUnpause))
        // dockerRemove requires both lifecycle AND remove toggles
        config.dockerRemoveEnabled = true
        XCTAssertTrue(config.isActionAllowed(.dockerRemove))

        // Network actions
        config.networkActionsEnabled = true
        config.sshTerminalEnabled = true
        config.pingTraceEnabled = true
        config.dnsFlushEnabled = true
        config.dnsLookupEnabled = true
        XCTAssertTrue(config.isActionAllowed(.flushDNS))
        XCTAssertTrue(config.isActionAllowed(.networkKillConnection))
        XCTAssertTrue(config.isActionAllowed(.sshToTerminal))
        XCTAssertTrue(config.isActionAllowed(.pingHost))
        XCTAssertTrue(config.isActionAllowed(.traceRoute))
        XCTAssertTrue(config.isActionAllowed(.dnsLookup))

        // System actions
        config.systemActionsEnabled = true
        config.purgeEnabled = true
        config.restartServicesEnabled = true
        config.powerActionsEnabled = true
        XCTAssertTrue(config.isActionAllowed(.purgeMemory))
        XCTAssertTrue(config.isActionAllowed(.restartFinder))
        XCTAssertTrue(config.isActionAllowed(.restartDock))
        XCTAssertTrue(config.isActionAllowed(.lockScreen))
    }

    @MainActor
    func testRequiresConfirmationForDestructive() {
        let config = ActionConfiguration()
        config.alwaysConfirmDestructive = true
        XCTAssertTrue(config.requiresConfirmation(.killProcess), "Destructive actions should require confirmation when alwaysConfirmDestructive is true")
        XCTAssertTrue(config.requiresConfirmation(.forceKillProcess))
    }

    @MainActor
    func testSkipConfirmReversible() {
        let config = ActionConfiguration()
        config.alwaysConfirmDestructive = false
        config.skipConfirmReversible = true
        // resumeProcess is not destructive, so with skipConfirmReversible it should be skipped
        XCTAssertFalse(config.requiresConfirmation(.resumeProcess))
        XCTAssertFalse(config.requiresConfirmation(.copyToClipboard))
    }

    @MainActor
    func testEjectEnabledAlias() {
        let config = ActionConfiguration()
        config.ejectEnabled = true
        XCTAssertTrue(config.storageEjectEnabled, "ejectEnabled alias should write through to storageEjectEnabled")
        config.storageEjectEnabled = false
        XCTAssertFalse(config.ejectEnabled, "ejectEnabled alias should read from storageEjectEnabled")
    }

    @MainActor
    func testForceEjectEnabledAlias() {
        let config = ActionConfiguration()
        config.forceEjectEnabled = true
        XCTAssertTrue(config.storageForceEjectEnabled, "forceEjectEnabled alias should write through to storageForceEjectEnabled")
    }

    @MainActor
    func testCopyEnabledAlias() {
        let config = ActionConfiguration()
        config.copyEnabled = false
        XCTAssertFalse(config.clipboardCopyEnabled, "copyEnabled alias should write through to clipboardCopyEnabled")
    }
}

// MARK: - AuditTrail Tests

final class AuditTrailTests: XCTestCase {
    private var tempDir: String!
    private var auditTrail: AuditTrail!

    override func setUp() async throws {
        // Create a unique temporary directory for each test
        let baseTempDir = NSTemporaryDirectory()
        tempDir = baseTempDir + "processscope-test-\(UUID().uuidString)"
        auditTrail = AuditTrail(directory: tempDir)
    }

    override func tearDown() async throws {
        // Clean up the temporary directory
        if let dir = tempDir {
            try? FileManager.default.removeItem(atPath: dir)
        }
        tempDir = nil
        auditTrail = nil
    }

    func testLogEntry() async {
        await auditTrail.log(
            action: .killProcess,
            target: "TestProcess | PID 1234",
            result: .success,
            userConfirmed: true
        )

        let entries = await auditTrail.recentEntries(limit: 10)
        XCTAssertEqual(entries.count, 1, "Should have exactly one entry after logging one action")
        XCTAssertEqual(entries.first?.actionType, .killProcess)
        XCTAssertEqual(entries.first?.targetDescription, "TestProcess | PID 1234")
        XCTAssertEqual(entries.first?.result, .success)
        XCTAssertTrue(entries.first?.wasConfirmed ?? false)
    }

    func testLogFormat() async {
        let beforeLog = Date()

        await auditTrail.log(
            action: .ejectVolume,
            target: "/Volumes/TestDrive",
            result: .failure,
            userConfirmed: false
        )

        let entries = await auditTrail.recentEntries(limit: 10)
        XCTAssertEqual(entries.count, 1)

        let entry = entries[0]
        XCTAssertEqual(entry.actionType, .ejectVolume)
        XCTAssertEqual(entry.targetDescription, "/Volumes/TestDrive")
        XCTAssertEqual(entry.result, .failure)
        XCTAssertFalse(entry.wasConfirmed)
        // Timestamp should be recent (within a few seconds of when we logged)
        XCTAssertGreaterThanOrEqual(entry.timestamp, beforeLog.addingTimeInterval(-1))
        XCTAssertLessThanOrEqual(entry.timestamp, Date().addingTimeInterval(1))
    }

    func testRecentEntriesLimit() async {
        // Log 10 entries
        for i in 0..<10 {
            await auditTrail.log(
                action: .killProcess,
                target: "Process-\(i)",
                result: .success,
                userConfirmed: true
            )
        }

        let limited = await auditTrail.recentEntries(limit: 5)
        XCTAssertEqual(limited.count, 5, "Should return exactly 5 entries when limit is 5")

        // The entries should be the most recent ones (newest first)
        // recentEntries returns newest first, so the first entry should be Process-9
        XCTAssertEqual(limited.first?.targetDescription, "Process-9")
    }

    func testAllEntries() async {
        for i in 0..<3 {
            await auditTrail.log(
                action: .suspendProcess,
                target: "Proc-\(i)",
                result: .success,
                userConfirmed: false
            )
        }

        let all = await auditTrail.allEntries()
        XCTAssertEqual(all.count, 3)
        // allEntries returns oldest first
        XCTAssertEqual(all.first?.targetDescription, "Proc-0")
        XCTAssertEqual(all.last?.targetDescription, "Proc-2")
    }

    func testClearAll() async {
        await auditTrail.log(
            action: .killProcess,
            target: "SomeProcess",
            result: .success,
            userConfirmed: true
        )

        let beforeClear = await auditTrail.recentEntries(limit: 10)
        XCTAssertEqual(beforeClear.count, 1)

        await auditTrail.clearAll()

        let afterClear = await auditTrail.recentEntries(limit: 10)
        XCTAssertEqual(afterClear.count, 0, "After clearAll, there should be no entries")
    }

    func testEmptyLogReturnsEmptyArray() async {
        let entries = await auditTrail.recentEntries(limit: 10)
        XCTAssertTrue(entries.isEmpty, "A fresh audit trail should have no entries")
    }

    func testMultipleActionTypes() async {
        await auditTrail.log(action: .killProcess, target: "A", result: .success, userConfirmed: true)
        await auditTrail.log(action: .ejectVolume, target: "B", result: .failure, userConfirmed: false)
        await auditTrail.log(action: .copyToClipboard, target: "C", result: .success, userConfirmed: false)

        let entries = await auditTrail.recentEntries(limit: 10)
        XCTAssertEqual(entries.count, 3)
        // Newest first
        XCTAssertEqual(entries[0].actionType, .copyToClipboard)
        XCTAssertEqual(entries[1].actionType, .ejectVolume)
        XCTAssertEqual(entries[2].actionType, .killProcess)
    }
}

// MARK: - AuditEntry Parse/Format Tests

final class AuditEntryTests: XCTestCase {

    func testLogLineRoundTrip() {
        let original = AuditEntry(
            actionType: .forceKillProcess,
            targetDescription: "TestApp | PID 9999 | /usr/bin/testapp",
            result: .success,
            wasConfirmed: true
        )

        let line = original.logLine
        let parsed = AuditEntry.parse(from: line)

        XCTAssertNotNil(parsed, "Should be able to parse back a formatted log line")
        XCTAssertEqual(parsed?.actionType, .forceKillProcess)
        XCTAssertEqual(parsed?.targetDescription, "TestApp | PID 9999 | /usr/bin/testapp")
        XCTAssertEqual(parsed?.result, .success)
        XCTAssertTrue(parsed?.wasConfirmed ?? false)
    }

    func testLogLineFormat() {
        let entry = AuditEntry(
            actionType: .killProcess,
            targetDescription: "Safari",
            result: .failure,
            wasConfirmed: false
        )

        let line = entry.logLine
        // Verify the line contains expected bracketed segments
        XCTAssertTrue(line.contains("[killProcess]"), "Log line should contain action type")
        XCTAssertTrue(line.contains("[Safari]"), "Log line should contain target description")
        XCTAssertTrue(line.contains("[failure]"), "Log line should contain result")
        XCTAssertTrue(line.contains("[USER_CONFIRMED: no]"), "Log line should contain confirmation status")
    }

    func testParseInvalidLineReturnsNil() {
        let badLine = "this is not a valid log line"
        XCTAssertNil(AuditEntry.parse(from: badLine), "Invalid log lines should return nil")
    }

    func testParseEmptyLineReturnsNil() {
        XCTAssertNil(AuditEntry.parse(from: ""), "Empty string should return nil")
    }

    func testConfirmedYes() {
        let entry = AuditEntry(
            actionType: .suspendProcess,
            targetDescription: "node",
            result: .success,
            wasConfirmed: true
        )
        let parsed = AuditEntry.parse(from: entry.logLine)
        XCTAssertTrue(parsed?.wasConfirmed ?? false)
    }

    func testConfirmedNo() {
        let entry = AuditEntry(
            actionType: .copyToClipboard,
            targetDescription: "data",
            result: .success,
            wasConfirmed: false
        )
        let parsed = AuditEntry.parse(from: entry.logLine)
        XCTAssertFalse(parsed?.wasConfirmed ?? true)
    }

    func testCancelledResult() {
        let entry = AuditEntry(
            actionType: .killProcess,
            targetDescription: "vim",
            result: .cancelled,
            wasConfirmed: false
        )
        let parsed = AuditEntry.parse(from: entry.logLine)
        XCTAssertEqual(parsed?.result, .cancelled)
    }
}

// MARK: - ActionType Tests

final class ActionTypeTests: XCTestCase {

    func testDestructiveActions() {
        XCTAssertTrue(ActionType.forceKillProcess.isDestructive, "forceKillProcess should be destructive")
        XCTAssertTrue(ActionType.killProcess.isDestructive, "killProcess should be destructive")
        XCTAssertTrue(ActionType.killProcessGroup.isDestructive, "killProcessGroup should be destructive")
        XCTAssertTrue(ActionType.forceQuitApp.isDestructive, "forceQuitApp should be destructive")
        XCTAssertTrue(ActionType.forceEjectVolume.isDestructive, "forceEjectVolume should be destructive")
        XCTAssertTrue(ActionType.unmountVolume.isDestructive, "unmountVolume should be destructive")
        XCTAssertTrue(ActionType.dockerRemove.isDestructive, "dockerRemove should be destructive")
        XCTAssertTrue(ActionType.networkKillConnection.isDestructive, "networkKillConnection should be destructive")
    }

    func testNonDestructiveActions() {
        XCTAssertFalse(ActionType.copyToClipboard.isDestructive, "copyToClipboard should not be destructive")
        XCTAssertFalse(ActionType.revealInFinder.isDestructive, "revealInFinder should not be destructive")
        XCTAssertFalse(ActionType.resumeProcess.isDestructive, "resumeProcess should not be destructive")
        XCTAssertFalse(ActionType.dockerStop.isDestructive, "dockerStop should not be destructive")
        XCTAssertFalse(ActionType.dockerStart.isDestructive, "dockerStart should not be destructive")
        XCTAssertFalse(ActionType.dockerRestart.isDestructive, "dockerRestart should not be destructive")
        XCTAssertFalse(ActionType.dockerPause.isDestructive, "dockerPause should not be destructive")
        XCTAssertFalse(ActionType.dockerUnpause.isDestructive, "dockerUnpause should not be destructive")
    }

    func testActionCategories() {
        // Process category
        XCTAssertEqual(ActionType.killProcess.category, .process)
        XCTAssertEqual(ActionType.forceKillProcess.category, .process)
        XCTAssertEqual(ActionType.suspendProcess.category, .process)
        XCTAssertEqual(ActionType.resumeProcess.category, .process)
        XCTAssertEqual(ActionType.killProcessGroup.category, .process)
        XCTAssertEqual(ActionType.reniceProcess.category, .process)
        XCTAssertEqual(ActionType.forceQuitApp.category, .process)

        // Storage category
        XCTAssertEqual(ActionType.ejectVolume.category, .storage)
        XCTAssertEqual(ActionType.forceEjectVolume.category, .storage)
        XCTAssertEqual(ActionType.unmountVolume.category, .storage)

        // Clipboard category
        XCTAssertEqual(ActionType.copyToClipboard.category, .clipboard)
        XCTAssertEqual(ActionType.revealInFinder.category, .clipboard)

        // Docker category
        XCTAssertEqual(ActionType.dockerStop.category, .docker)
        XCTAssertEqual(ActionType.dockerStart.category, .docker)
        XCTAssertEqual(ActionType.dockerRestart.category, .docker)
        XCTAssertEqual(ActionType.dockerPause.category, .docker)
        XCTAssertEqual(ActionType.dockerUnpause.category, .docker)
        XCTAssertEqual(ActionType.dockerRemove.category, .docker)

        // Network category
        XCTAssertEqual(ActionType.flushDNS.category, .network)
        XCTAssertEqual(ActionType.networkKillConnection.category, .network)

        // System category
        XCTAssertEqual(ActionType.purgeMemory.category, .system)
        XCTAssertEqual(ActionType.restartFinder.category, .system)
        XCTAssertEqual(ActionType.restartDock.category, .system)
    }

    func testHelperRequirement() {
        // Actions that require the helper
        XCTAssertTrue(ActionType.forceEjectVolume.requiresHelper, "forceEjectVolume should require helper")
        XCTAssertTrue(ActionType.flushDNS.requiresHelper, "flushDNS should require helper")
        XCTAssertTrue(ActionType.purgeMemory.requiresHelper, "purgeMemory should require helper")
        XCTAssertTrue(ActionType.networkKillConnection.requiresHelper, "networkKillConnection should require helper")
        XCTAssertTrue(ActionType.reniceProcess.requiresHelper, "reniceProcess should require helper")

        // Actions that do NOT require the helper
        XCTAssertFalse(ActionType.copyToClipboard.requiresHelper, "copyToClipboard should not require helper")
        XCTAssertFalse(ActionType.revealInFinder.requiresHelper, "revealInFinder should not require helper")
        XCTAssertFalse(ActionType.killProcess.requiresHelper, "killProcess should not require helper")
        XCTAssertFalse(ActionType.forceKillProcess.requiresHelper, "forceKillProcess should not require helper")
        XCTAssertFalse(ActionType.suspendProcess.requiresHelper, "suspendProcess should not require helper")
        XCTAssertFalse(ActionType.ejectVolume.requiresHelper, "ejectVolume should not require helper")
    }

    func testUndoActions() {
        XCTAssertEqual(ActionType.suspendProcess.undoAction, .resumeProcess)
        XCTAssertEqual(ActionType.resumeProcess.undoAction, .suspendProcess)
        XCTAssertEqual(ActionType.dockerStop.undoAction, .dockerStart)
        XCTAssertEqual(ActionType.dockerStart.undoAction, .dockerStop)
        XCTAssertEqual(ActionType.dockerPause.undoAction, .dockerUnpause)
        XCTAssertEqual(ActionType.dockerUnpause.undoAction, .dockerPause)

        // Actions without undo
        XCTAssertNil(ActionType.killProcess.undoAction)
        XCTAssertNil(ActionType.forceKillProcess.undoAction)
        XCTAssertNil(ActionType.copyToClipboard.undoAction)
    }

    func testDisplayNames() {
        XCTAssertEqual(ActionType.killProcess.displayName, "Kill Process")
        XCTAssertEqual(ActionType.forceKillProcess.displayName, "Force Kill Process")
        XCTAssertEqual(ActionType.copyToClipboard.displayName, "Copy to Clipboard")
        XCTAssertEqual(ActionType.ejectVolume.displayName, "Eject Volume")
        XCTAssertEqual(ActionType.dockerStop.displayName, "Stop Container")
        XCTAssertEqual(ActionType.flushDNS.displayName, "Flush DNS Cache")
        XCTAssertEqual(ActionType.purgeMemory.displayName, "Purge Memory")
    }

    func testSymbolNames() {
        // Verify all actions have non-empty SF Symbol names
        for action in ActionType.allCases {
            XCTAssertFalse(action.symbolName.isEmpty, "\(action.rawValue) should have a non-empty symbolName")
        }
    }

    func testAllCasesCount() {
        // Verify we have all expected action types (7 process + 3 storage + 2 clipboard + 6 docker + 6 network + 9 system = 33)
        XCTAssertEqual(ActionType.allCases.count, 33, "Should have 33 action types total")
    }
}

// MARK: - ActionTarget Tests

final class ActionTargetTests: XCTestCase {

    func testAuditDescriptionWithAllFields() {
        let target = ActionTarget(
            pid: 1234,
            name: "TestProcess",
            path: "/usr/bin/test",
            volumePath: nil,
            containerID: nil,
            bundleIdentifier: nil
        )
        let desc = target.auditDescription
        XCTAssertTrue(desc.contains("TestProcess"))
        XCTAssertTrue(desc.contains("PID 1234"))
        XCTAssertTrue(desc.contains("/usr/bin/test"))
    }

    func testAuditDescriptionNameOnly() {
        let target = ActionTarget(name: "SimpleTarget")
        XCTAssertEqual(target.auditDescription, "SimpleTarget")
    }

    func testAuditDescriptionWithVolume() {
        let target = ActionTarget(name: "MyDrive", volumePath: "/Volumes/MyDrive")
        let desc = target.auditDescription
        XCTAssertTrue(desc.contains("MyDrive"))
        XCTAssertTrue(desc.contains("/Volumes/MyDrive"))
    }

    func testAuditDescriptionWithContainer() {
        let target = ActionTarget(name: "web-app", containerID: "abc123def456")
        let desc = target.auditDescription
        XCTAssertTrue(desc.contains("web-app"))
        XCTAssertTrue(desc.contains("abc123def456"))
    }

    func testEquality() {
        let a = ActionTarget(pid: 100, name: "A", path: "/bin/a")
        let b = ActionTarget(pid: 100, name: "A", path: "/bin/a")
        let c = ActionTarget(pid: 200, name: "A", path: "/bin/a")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}

// MARK: - ActionResult Tests

final class ActionResultTests: XCTestCase {

    func testDisplayNames() {
        XCTAssertEqual(ActionResult.success.displayName, "Success")
        XCTAssertEqual(ActionResult.failure.displayName, "Failed")
        XCTAssertEqual(ActionResult.cancelled.displayName, "Cancelled")
    }

    func testCodable() throws {
        let original = ActionResult.success
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ActionResult.self, from: data)
        XCTAssertEqual(original, decoded)
    }
}

// MARK: - ActionCategory Tests

final class ActionCategoryTests: XCTestCase {

    func testAllCategoriesHaveSymbolNames() {
        for category in ActionCategory.allCases {
            XCTAssertFalse(category.symbolName.isEmpty, "\(category.rawValue) should have a symbol name")
        }
    }

    func testDisplayNames() {
        XCTAssertEqual(ActionCategory.process.displayName, "Process")
        XCTAssertEqual(ActionCategory.storage.displayName, "Storage")
        XCTAssertEqual(ActionCategory.clipboard.displayName, "Clipboard")
        XCTAssertEqual(ActionCategory.docker.displayName, "Docker")
        XCTAssertEqual(ActionCategory.network.displayName, "Network")
        XCTAssertEqual(ActionCategory.system.displayName, "System")
    }

    func testAllCategoriesCovered() {
        XCTAssertEqual(ActionCategory.allCases.count, 6)
    }
}

// MARK: - ActionError Tests

final class ActionErrorTests: XCTestCase {

    func testActionNotAllowedDescription() {
        let error = ActionError.actionNotAllowed(.killProcess)
        let desc = error.localizedDescription
        XCTAssertTrue(desc.contains("Kill Process"), "Error should mention the action display name")
        XCTAssertTrue(desc.contains("not enabled"), "Error should mention the action is not enabled")
    }

    func testHelperRequiredDescription() {
        let error = ActionError.helperRequired(.forceEjectVolume)
        let desc = error.localizedDescription
        XCTAssertTrue(desc.contains("Force Eject Volume"), "Error should mention the action display name")
        XCTAssertTrue(desc.contains("helper"), "Error should mention the helper daemon")
    }

    func testSignalFailedDescription() {
        let error = ActionError.signalFailed(1234, SIGTERM, 1)
        let desc = error.localizedDescription
        XCTAssertTrue(desc.contains("1234"), "Error should mention the PID")
        XCTAssertTrue(desc.contains("errno"), "Error should mention errno")
    }

    func testProcessNotFoundDescription() {
        let error = ActionError.processNotFound(9999)
        let desc = error.localizedDescription
        XCTAssertTrue(desc.contains("9999"), "Error should mention the PID")
    }

    func testVolumeNotFoundDescription() {
        let error = ActionError.volumeNotFound("/Volumes/Ghost")
        let desc = error.localizedDescription
        XCTAssertTrue(desc.contains("/Volumes/Ghost"), "Error should mention the volume path")
    }

    func testExecutionFailedDescription() {
        let error = ActionError.executionFailed("Something went wrong")
        XCTAssertEqual(error.localizedDescription, "Something went wrong")
    }
}

// MARK: - PendingAction Tests

final class PendingActionTests: XCTestCase {

    func testPendingActionCreation() {
        let target = ActionTarget(pid: 42, name: "TestApp", path: "/usr/bin/testapp")
        let pending = PendingAction(
            actionType: .killProcess,
            target: target,
            title: "Kill Process?",
            detail: "This will terminate the process.",
            confirmLabel: "Kill",
            isDestructive: true,
            affectedItems: ["child1", "child2"]
        )

        XCTAssertEqual(pending.actionType, .killProcess)
        XCTAssertEqual(pending.target.pid, 42)
        XCTAssertEqual(pending.title, "Kill Process?")
        XCTAssertEqual(pending.detail, "This will terminate the process.")
        XCTAssertEqual(pending.confirmLabel, "Kill")
        XCTAssertTrue(pending.isDestructive)
        XCTAssertEqual(pending.affectedItems, ["child1", "child2"])
        XCTAssertNotNil(pending.id)
        // Timestamp should be recent
        XCTAssertLessThan(Date().timeIntervalSince(pending.timestamp), 5.0)
    }

    func testPendingActionDefaultAffectedItems() {
        let target = ActionTarget(name: "Test")
        let pending = PendingAction(
            actionType: .copyToClipboard,
            target: target,
            title: "Copy?",
            detail: "Copy data.",
            confirmLabel: "Copy",
            isDestructive: false
        )
        XCTAssertTrue(pending.affectedItems.isEmpty)
    }

    func testPendingActionUniqueIDs() {
        let target = ActionTarget(name: "Test")
        let a = PendingAction(actionType: .killProcess, target: target, title: "A", detail: "", confirmLabel: "A", isDestructive: true)
        let b = PendingAction(actionType: .killProcess, target: target, title: "B", detail: "", confirmLabel: "B", isDestructive: true)
        XCTAssertNotEqual(a.id, b.id, "Each PendingAction should have a unique ID")
    }
}

// MARK: - ActionViewModel Tests

final class ActionViewModelTests: XCTestCase {
    private var tempDir: String!

    /// Reset all AppStorage keys used by ActionConfiguration before each test.
    private static let appStorageKeys = [
        "action.process.kill",
        "action.process.forceKill",
        "action.process.suspend",
        "action.process.renice",
        "action.storage.eject",
        "action.storage.forceEject",
        "action.clipboard.copy",
        "action.docker.lifecycle",
        "action.docker.remove",
        "action.network.enabled",
        "action.network.sshTerminal",
        "action.network.pingTrace",
        "action.network.dnsFlush",
        "action.network.dnsLookup",
        "action.system.enabled",
        "action.system.purge",
        "action.system.restartServices",
        "action.system.power",
        "action.confirm.destructive",
        "action.confirm.skipReversible",
    ]

    override func setUp() async throws {
        for key in Self.appStorageKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        let baseTempDir = NSTemporaryDirectory()
        tempDir = baseTempDir + "processscope-vm-test-\(UUID().uuidString)"
    }

    override func tearDown() async throws {
        if let dir = tempDir {
            try? FileManager.default.removeItem(atPath: dir)
        }
        tempDir = nil
    }

    @MainActor
    func testRequestBlockedActionLogsFailure() async {
        let auditTrail = AuditTrail(directory: tempDir)
        let config = ActionConfiguration()
        // processKillEnabled defaults to false
        let vm = ActionViewModel(
            configuration: config,
            auditTrail: auditTrail,
            isHelperInstalled: false
        )

        let target = ActionTarget(pid: 100, name: "TestProc")
        await vm.requestAction(.killProcess, target: target)

        // Should have logged a failure because the action is not enabled
        let entries = await auditTrail.recentEntries(limit: 10)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.result, .failure)
        XCTAssertEqual(entries.first?.actionType, .killProcess)
        XCTAssertNotNil(vm.lastErrorMessage, "Should set an error message when action is blocked")
    }

    @MainActor
    func testRequestHelperBlockedActionLogsFailure() async {
        let auditTrail = AuditTrail(directory: tempDir)
        let config = ActionConfiguration()
        config.storageForceEjectEnabled = true  // Enable the action
        // But helper is NOT installed
        let vm = ActionViewModel(
            configuration: config,
            auditTrail: auditTrail,
            isHelperInstalled: false
        )

        let target = ActionTarget(name: "MyDrive", volumePath: "/Volumes/MyDrive")
        await vm.requestAction(.forceEjectVolume, target: target)

        let entries = await auditTrail.recentEntries(limit: 10)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.result, .failure)
        XCTAssertEqual(entries.first?.actionType, .forceEjectVolume)
        XCTAssertNotNil(vm.lastErrorMessage)
        XCTAssertTrue(vm.lastErrorMessage?.contains("helper") ?? false)
    }

    @MainActor
    func testDestructiveActionShowsConfirmation() async {
        let auditTrail = AuditTrail(directory: tempDir)
        let config = ActionConfiguration()
        config.processKillEnabled = true
        config.alwaysConfirmDestructive = true
        let vm = ActionViewModel(
            configuration: config,
            auditTrail: auditTrail,
            isHelperInstalled: false
        )

        let target = ActionTarget(pid: 555, name: "VictimProcess")
        await vm.requestAction(.killProcess, target: target)

        // Should show confirmation dialog rather than executing immediately
        XCTAssertTrue(vm.showConfirmation, "Should show confirmation for destructive action")
        XCTAssertNotNil(vm.pendingAction, "Should have a pending action")
        XCTAssertEqual(vm.pendingAction?.actionType, .killProcess)
        XCTAssertEqual(vm.pendingAction?.target.pid, 555)

        // No audit entry yet because the action has not been confirmed or cancelled
        let entries = await auditTrail.recentEntries(limit: 10)
        XCTAssertEqual(entries.count, 0)
    }

    @MainActor
    func testCancelActionLogsCancel() async {
        let auditTrail = AuditTrail(directory: tempDir)
        let config = ActionConfiguration()
        config.processKillEnabled = true
        config.alwaysConfirmDestructive = true
        let vm = ActionViewModel(
            configuration: config,
            auditTrail: auditTrail,
            isHelperInstalled: false
        )

        let target = ActionTarget(pid: 555, name: "VictimProcess")
        await vm.requestAction(.killProcess, target: target)
        XCTAssertNotNil(vm.pendingAction)

        vm.cancelAction()

        XCTAssertNil(vm.pendingAction, "Pending action should be cleared after cancel")
        XCTAssertFalse(vm.showConfirmation, "Confirmation dialog should be dismissed")
        XCTAssertEqual(vm.lastResult, .cancelled)

        // Wait briefly for the audit log task to complete
        try? await Task.sleep(for: .milliseconds(100))

        let entries = await auditTrail.recentEntries(limit: 10)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.result, .cancelled)
        XCTAssertFalse(entries.first?.wasConfirmed ?? true)
    }

    @MainActor
    func testClipboardActionSkipsConfirmation() async {
        let auditTrail = AuditTrail(directory: tempDir)
        let config = ActionConfiguration()
        // clipboardCopyEnabled defaults to true
        let vm = ActionViewModel(
            configuration: config,
            auditTrail: auditTrail,
            isHelperInstalled: false
        )

        let target = ActionTarget(name: "some text", path: nil)
        await vm.requestAction(.copyToClipboard, target: target)

        // Clipboard actions should not show a confirmation dialog
        XCTAssertFalse(vm.showConfirmation, "Clipboard actions should not show confirmation")
        XCTAssertNil(vm.pendingAction)
    }

    @MainActor
    func testInitialState() {
        let vm = ActionViewModel(
            configuration: ActionConfiguration(),
            auditTrail: AuditTrail(directory: tempDir)
        )
        XCTAssertNil(vm.pendingAction)
        XCTAssertFalse(vm.isExecuting)
        XCTAssertNil(vm.lastResult)
        XCTAssertNil(vm.lastErrorMessage)
        XCTAssertFalse(vm.showConfirmation)
        XCTAssertFalse(vm.isHelperInstalled)
    }
}

// MARK: - ClipboardService Tests

final class ClipboardServiceTests: XCTestCase {

    func testFormatProcess() {
        let result = ClipboardService.formatProcess(
            name: "python3",
            pid: 1234,
            path: "/usr/bin/python3",
            arguments: ["python3", "-m", "uvicorn"]
        )
        XCTAssertTrue(result.contains("python3 (PID 1234)"))
        XCTAssertTrue(result.contains("/usr/bin/python3"))
        XCTAssertTrue(result.contains("python3 -m uvicorn"))
    }

    func testFormatProcessMinimal() {
        let result = ClipboardService.formatProcess(name: "test", pid: 1)
        XCTAssertEqual(result, "test (PID 1)")
    }

    func testFormatConnection() {
        let result = ClipboardService.formatConnection(
            localAddress: "127.0.0.1",
            localPort: 8080,
            remoteAddress: "10.0.0.1",
            remotePort: 443,
            protocolType: "tcp"
        )
        XCTAssertEqual(result, "tcp 127.0.0.1:8080 -> 10.0.0.1:443")
    }

    func testFormatVolume() {
        let result = ClipboardService.formatVolume(name: "Backup", mountPoint: "/Volumes/Backup")
        XCTAssertEqual(result, "Backup (/Volumes/Backup)")
    }

    func testFormatVolumeWithCapacity() {
        let result = ClipboardService.formatVolume(
            name: "Backup",
            mountPoint: "/Volumes/Backup",
            capacity: 1_000_000_000  // ~1 GB
        )
        XCTAssertTrue(result.contains("Backup (/Volumes/Backup)"))
        // ByteCountFormatter will produce something like "1 GB"
        XCTAssertTrue(result.contains("GB") || result.contains("MB"),
                       "Should include a human-readable byte count")
    }
}
