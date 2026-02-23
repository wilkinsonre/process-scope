import XCTest
@testable import ProcessScope

final class StorageCollectorTests: XCTestCase {

    // MARK: - VolumeSnapshot Tests

    func testVolumeSnapshotUsageCalculation() {
        let volume = VolumeSnapshot(
            name: "Macintosh HD",
            mountPoint: "/",
            totalBytes: 1_000_000_000_000, // 1 TB
            freeBytes: 250_000_000_000,    // 250 GB
            fileSystemType: "apfs",
            interfaceType: .nvmeInternal,
            isRemovable: false,
            isNetwork: false,
            isBootVolume: true,
            isEncrypted: true,
            smartStatus: .healthy,
            isEjectable: false,
            bsdName: "disk3s1"
        )

        XCTAssertEqual(volume.usedBytes, 750_000_000_000)
        XCTAssertEqual(volume.usageFraction, 0.75, accuracy: 0.001)
    }

    func testVolumeSnapshotZeroCapacity() {
        let volume = VolumeSnapshot(
            name: "Empty",
            mountPoint: "/empty",
            totalBytes: 0,
            freeBytes: 0,
            fileSystemType: "devfs",
            interfaceType: .unknown,
            isRemovable: false,
            isNetwork: false,
            isBootVolume: false,
            isEncrypted: false,
            smartStatus: .unknown,
            isEjectable: false,
            bsdName: nil
        )

        XCTAssertEqual(volume.usedBytes, 0)
        XCTAssertEqual(volume.usageFraction, 0)
    }

    func testVolumeSnapshotIdentifiable() {
        let volume1 = VolumeSnapshot(
            name: "Volume 1",
            mountPoint: "/Volumes/Vol1",
            totalBytes: 500_000_000_000,
            freeBytes: 100_000_000_000,
            fileSystemType: "apfs",
            interfaceType: .usb,
            isRemovable: true,
            isNetwork: false,
            isBootVolume: false,
            isEncrypted: false,
            smartStatus: .healthy,
            isEjectable: true,
            bsdName: "disk4s1"
        )

        let volume2 = VolumeSnapshot(
            name: "Volume 2",
            mountPoint: "/Volumes/Vol2",
            totalBytes: 500_000_000_000,
            freeBytes: 200_000_000_000,
            fileSystemType: "exfat",
            interfaceType: .usb,
            isRemovable: true,
            isNetwork: false,
            isBootVolume: false,
            isEncrypted: false,
            smartStatus: .unknown,
            isEjectable: true,
            bsdName: "disk5s1"
        )

        // id is mountPoint, so they should differ
        XCTAssertNotEqual(volume1.id, volume2.id)
        XCTAssertEqual(volume1.id, "/Volumes/Vol1")
    }

    // MARK: - SMART Status Tests

    func testSMARTStatusEnum() {
        XCTAssertEqual(SMARTStatus.healthy.rawValue, "healthy")
        XCTAssertEqual(SMARTStatus.failing.rawValue, "failing")
        XCTAssertEqual(SMARTStatus.unknown.rawValue, "unknown")
    }

    func testSMARTStatusCodable() throws {
        let statuses: [SMARTStatus] = [.healthy, .failing, .unknown]
        for status in statuses {
            let encoded = try JSONEncoder().encode(status)
            let decoded = try JSONDecoder().decode(SMARTStatus.self, from: encoded)
            XCTAssertEqual(decoded, status)
        }
    }

    // MARK: - Storage Interface Type Tests

    func testStorageInterfaceSymbolNames() {
        XCTAssertEqual(StorageInterfaceType.nvmeInternal.symbolName, "internaldrive.fill")
        XCTAssertEqual(StorageInterfaceType.usb.symbolName, "cable.connector")
        XCTAssertEqual(StorageInterfaceType.thunderbolt.symbolName, "bolt.horizontal.fill")
        XCTAssertEqual(StorageInterfaceType.sata.symbolName, "internaldrive")
        XCTAssertEqual(StorageInterfaceType.network.symbolName, "externaldrive.connected.to.line.below")
    }

    func testStorageInterfaceBandwidth() {
        XCTAssertNotNil(StorageInterfaceType.nvmeInternal.theoreticalBandwidth)
        XCTAssertNotNil(StorageInterfaceType.usb.theoreticalBandwidth)
        XCTAssertNotNil(StorageInterfaceType.thunderbolt.theoreticalBandwidth)
        XCTAssertNil(StorageInterfaceType.network.theoreticalBandwidth)
        XCTAssertNil(StorageInterfaceType.unknown.theoreticalBandwidth)

        // NVMe should be faster than USB
        let nvme = StorageInterfaceType.nvmeInternal.theoreticalBandwidth!
        let usb = StorageInterfaceType.usb.theoreticalBandwidth!
        XCTAssertGreaterThan(nvme, usb)
    }

    // MARK: - Time Machine Status Tests

    func testTimeMachineBackingUpParsing() async {
        let collector = StorageCollector()
        await collector.activate()

        let output = """
        {
            BackupPhase = Copying;
            DateOfStateChange = "2024-12-15 10:30:00 +0000";
            DestinationID = "XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX";
            DestinationMountPoint = "/Volumes/BackupDrive";
            Percent = 0.45;
            Progress = {
                TimeRemaining = 1200;
                bytes = 50000000000;
                totalBytes = 100000000000;
            };
            Running = 1;
            Stopping = 0;
        }
        """

        let state = await collector.parseTimeMachineOutput(output)

        switch state {
        case .backingUp(let percent):
            XCTAssertEqual(percent, 0.45, accuracy: 0.01)
        default:
            XCTFail("Expected .backingUp state, got \(state)")
        }
    }

    func testTimeMachineIdleParsing() async {
        let collector = StorageCollector()
        await collector.activate()

        let output = """
        {
            Running = 0;
            Stopping = 0;
        }
        """

        let state = await collector.parseTimeMachineOutput(output)

        switch state {
        case .idle:
            break // Expected
        default:
            XCTFail("Expected .idle state, got \(state)")
        }
    }

    func testTimeMachineStateCodable() throws {
        let states: [TimeMachineState] = [
            .idle(lastBackup: Date(timeIntervalSince1970: 1700000000)),
            .idle(lastBackup: nil),
            .backingUp(percent: 0.75),
            .unavailable,
        ]

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for state in states {
            let data = try encoder.encode(state)
            let decoded = try decoder.decode(TimeMachineState.self, from: data)
            XCTAssertEqual(decoded, state)
        }
    }

    // MARK: - Storage Snapshot Tests

    func testStorageSnapshotCodable() throws {
        let snapshot = StorageSnapshot(
            volumes: [
                VolumeSnapshot(
                    name: "Test Volume",
                    mountPoint: "/Volumes/Test",
                    totalBytes: 500_000_000_000,
                    freeBytes: 200_000_000_000,
                    fileSystemType: "apfs",
                    interfaceType: .nvmeInternal,
                    isRemovable: false,
                    isNetwork: false,
                    isBootVolume: true,
                    isEncrypted: true,
                    smartStatus: .healthy,
                    isEjectable: false,
                    bsdName: "disk3s1"
                )
            ],
            timeMachineState: .idle(lastBackup: nil),
            timestamp: Date()
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(StorageSnapshot.self, from: data)

        XCTAssertEqual(decoded.volumes.count, 1)
        XCTAssertEqual(decoded.volumes[0].name, "Test Volume")
        XCTAssertEqual(decoded.volumes[0].interfaceType, .nvmeInternal)
    }

    // MARK: - Network Volume Tests

    func testNetworkVolumeSnapshotIdentifiable() {
        let volume = NetworkVolumeSnapshot(
            server: "nas.local",
            shareName: "data",
            protocolType: .smb,
            mountPoint: "/Volumes/data",
            isConnected: true,
            displayName: "Data",
            latencyMs: 2.5,
            totalBytes: 4_000_000_000_000,
            freeBytes: 1_000_000_000_000
        )

        XCTAssertEqual(volume.id, "/Volumes/data")
        XCTAssertEqual(volume.usedBytes, 3_000_000_000_000)
    }

    func testNetworkVolumeProtocolSymbols() {
        XCTAssertEqual(NetworkVolumeProtocol.smb.symbolName, "server.rack")
        XCTAssertEqual(NetworkVolumeProtocol.nfs.symbolName, "externaldrive.connected.to.line.below")
        XCTAssertEqual(NetworkVolumeProtocol.afp.symbolName, "apple.logo")
        XCTAssertEqual(NetworkVolumeProtocol.webdav.symbolName, "globe")
    }

    func testNetworkVolumeSnapshotCodable() throws {
        let snapshot = NetworkVolumeCollectionSnapshot(
            volumes: [
                NetworkVolumeSnapshot(
                    server: "fileserver.company.com",
                    shareName: "projects",
                    protocolType: .smb,
                    mountPoint: "/Volumes/projects",
                    isConnected: true,
                    displayName: "Projects",
                    latencyMs: 5.2,
                    totalBytes: 10_000_000_000_000,
                    freeBytes: 3_000_000_000_000
                ),
                NetworkVolumeSnapshot(
                    server: "nfs-host",
                    shareName: "/exports/home",
                    protocolType: .nfs,
                    mountPoint: "/home",
                    isConnected: false,
                    displayName: "Home",
                    latencyMs: nil,
                    totalBytes: 0,
                    freeBytes: 0
                ),
            ],
            timestamp: Date()
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(NetworkVolumeCollectionSnapshot.self, from: data)

        XCTAssertEqual(decoded.volumes.count, 2)
        XCTAssertEqual(decoded.volumes[0].protocolType, .smb)
        XCTAssertEqual(decoded.volumes[1].protocolType, .nfs)
        XCTAssertFalse(decoded.volumes[1].isConnected)
    }

    // MARK: - Mock Collector Tests

    func testMockStorageCollectorActivation() async {
        let mockVolume = VolumeSnapshot(
            name: "Mock Volume",
            mountPoint: "/Volumes/Mock",
            totalBytes: 1_000_000_000,
            freeBytes: 500_000_000,
            fileSystemType: "apfs",
            interfaceType: .usb,
            isRemovable: true,
            isNetwork: false,
            isBootVolume: false,
            isEncrypted: false,
            smartStatus: .healthy,
            isEjectable: true,
            bsdName: "disk99s1"
        )

        let mockSnapshot = StorageSnapshot(
            volumes: [mockVolume],
            timeMachineState: .idle(lastBackup: nil),
            timestamp: Date()
        )

        let collector = MockStorageCollector(snapshot: mockSnapshot)

        // Before activation, should return empty
        let emptyResult = await collector.collect()
        XCTAssertTrue(emptyResult.volumes.isEmpty)

        // After activation, should return mock data
        await collector.activate()
        let result = await collector.collect()
        XCTAssertEqual(result.volumes.count, 1)
        XCTAssertEqual(result.volumes[0].name, "Mock Volume")
    }

    func testMockStorageCollectorDeactivation() async {
        let mockSnapshot = StorageSnapshot(
            volumes: [
                VolumeSnapshot(
                    name: "V1", mountPoint: "/V1", totalBytes: 100, freeBytes: 50,
                    fileSystemType: "apfs", interfaceType: .nvmeInternal,
                    isRemovable: false, isNetwork: false, isBootVolume: true,
                    isEncrypted: false, smartStatus: .healthy, isEjectable: false,
                    bsdName: "disk0"
                )
            ],
            timeMachineState: .unavailable,
            timestamp: Date()
        )

        let collector = MockStorageCollector(snapshot: mockSnapshot)
        await collector.activate()

        var result = await collector.collect()
        XCTAssertEqual(result.volumes.count, 1)

        // After deactivation, should return empty (zero overhead)
        await collector.deactivate()
        result = await collector.collect()
        XCTAssertTrue(result.volumes.isEmpty)
    }

    func testMockNetworkVolumeCollector() async {
        let mockSnapshot = NetworkVolumeCollectionSnapshot(
            volumes: [
                NetworkVolumeSnapshot(
                    server: "test-server",
                    shareName: "share1",
                    protocolType: .smb,
                    mountPoint: "/Volumes/share1",
                    isConnected: true,
                    displayName: "Share 1",
                    latencyMs: 3.0,
                    totalBytes: 1_000_000,
                    freeBytes: 500_000
                )
            ],
            timestamp: Date()
        )

        let collector = MockNetworkVolumeCollector(snapshot: mockSnapshot)

        // Before activation
        let emptyResult = await collector.collect()
        XCTAssertTrue(emptyResult.volumes.isEmpty)

        // After activation
        await collector.activate()
        let result = await collector.collect()
        XCTAssertEqual(result.volumes.count, 1)
        XCTAssertEqual(result.volumes[0].server, "test-server")
        XCTAssertEqual(result.volumes[0].protocolType, .smb)
    }

    // MARK: - Live Collector Tests

    func testStorageCollectorCollectsBootVolume() async {
        let collector = StorageCollector()
        await collector.activate()

        let snapshot = await collector.collect()

        // Should always find the boot volume
        XCTAssertFalse(snapshot.volumes.isEmpty, "Should detect at least the boot volume")

        let bootVolume = snapshot.volumes.first { $0.isBootVolume }
        XCTAssertNotNil(bootVolume, "Should identify the boot volume")

        if let boot = bootVolume {
            XCTAssertEqual(boot.mountPoint, "/")
            XCTAssertGreaterThan(boot.totalBytes, 0)
            XCTAssertGreaterThan(boot.freeBytes, 0)
            XCTAssertFalse(boot.fileSystemType.isEmpty)
        }
    }

    func testStorageCollectorInactiveReturnsEmpty() async {
        let collector = StorageCollector()
        // Do NOT activate

        let snapshot = await collector.collect()
        XCTAssertTrue(snapshot.volumes.isEmpty)
        XCTAssertEqual(snapshot.timeMachineState, .unavailable)
    }

    func testNetworkVolumeCollectorInactiveReturnsEmpty() async {
        let collector = NetworkVolumeCollector()
        // Do NOT activate

        let snapshot = await collector.collect()
        XCTAssertTrue(snapshot.volumes.isEmpty)
    }

    // MARK: - Eject Readiness / Interface Type Tests

    func testVolumeEjectableFlag() {
        let removable = VolumeSnapshot(
            name: "USB Drive",
            mountPoint: "/Volumes/USB",
            totalBytes: 32_000_000_000,
            freeBytes: 16_000_000_000,
            fileSystemType: "exfat",
            interfaceType: .usb,
            isRemovable: true,
            isNetwork: false,
            isBootVolume: false,
            isEncrypted: false,
            smartStatus: .unknown,
            isEjectable: true,
            bsdName: "disk6s1"
        )

        XCTAssertTrue(removable.isEjectable)
        XCTAssertTrue(removable.isRemovable)

        let internal_ = VolumeSnapshot(
            name: "Macintosh HD",
            mountPoint: "/",
            totalBytes: 1_000_000_000_000,
            freeBytes: 500_000_000_000,
            fileSystemType: "apfs",
            interfaceType: .nvmeInternal,
            isRemovable: false,
            isNetwork: false,
            isBootVolume: true,
            isEncrypted: true,
            smartStatus: .healthy,
            isEjectable: false,
            bsdName: "disk3s1"
        )

        XCTAssertFalse(internal_.isEjectable)
        XCTAssertFalse(internal_.isRemovable)
    }

    // MARK: - Storage Module Registration Tests

    @MainActor
    func testStorageModuleRegistration() {
        let registry = ModuleRegistry()
        let module = StorageModule()
        registry.register(module)

        XCTAssertEqual(registry.modules.count, 1)
        XCTAssertEqual(registry.modules.first?.id, "storage")
        XCTAssertEqual(module.collectors.count, 2)
    }

    @MainActor
    func testStorageModulePollingTiers() {
        let module = StorageModule()
        XCTAssertTrue(module.pollingSubscriptions.contains(.slow))
        XCTAssertTrue(module.pollingSubscriptions.contains(.infrequent))
        XCTAssertFalse(module.pollingSubscriptions.contains(.critical))
    }

    @MainActor
    func testStorageModuleActivateDeactivate() async {
        let module = StorageModule()
        await module.activate()
        // Should not crash
        await module.deactivate()
        // Should not crash
    }
}
