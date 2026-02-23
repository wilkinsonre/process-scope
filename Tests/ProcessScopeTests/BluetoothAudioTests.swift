import XCTest
@testable import ProcessScope

final class BluetoothAudioTests: XCTestCase {

    // MARK: - Bluetooth Device Classification Tests

    func testClassifyHeadphones() {
        // Major class 0x04 (Audio/Video), minor class 0x01 (Wearable headset)
        let classOfDevice: UInt32 = (0x04 << 8) | (0x01 << 2)
        let deviceType = BluetoothCollector.classifyDevice(classOfDevice: classOfDevice)
        XCTAssertEqual(deviceType, .headphones)
    }

    func testClassifyHeadphonesMinor06() {
        // Major class 0x04 (Audio/Video), minor class 0x06 (Headphones)
        let classOfDevice: UInt32 = (0x04 << 8) | (0x06 << 2)
        let deviceType = BluetoothCollector.classifyDevice(classOfDevice: classOfDevice)
        XCTAssertEqual(deviceType, .headphones)
    }

    func testClassifySpeaker() {
        // Major class 0x04 (Audio/Video), minor class 0x04 (Loudspeaker)
        let classOfDevice: UInt32 = (0x04 << 8) | (0x04 << 2)
        let deviceType = BluetoothCollector.classifyDevice(classOfDevice: classOfDevice)
        XCTAssertEqual(deviceType, .speaker)
    }

    func testClassifyKeyboard() {
        // Major class 0x05 (Peripheral), minor class 0x01 (Keyboard)
        // Note: minor class bits 0-3 are the subtype, bits 4-5 are the type
        let classOfDevice: UInt32 = (0x05 << 8) | (0x01 << 2)
        let deviceType = BluetoothCollector.classifyDevice(classOfDevice: classOfDevice)
        XCTAssertEqual(deviceType, .keyboard)
    }

    func testClassifyMouse() {
        // Major class 0x05 (Peripheral), minor class 0x02 (Pointing device)
        let classOfDevice: UInt32 = (0x05 << 8) | (0x02 << 2)
        let deviceType = BluetoothCollector.classifyDevice(classOfDevice: classOfDevice)
        XCTAssertEqual(deviceType, .mouse)
    }

    func testClassifyTrackpad() {
        // Major class 0x05 (Peripheral), minor class 0x03 (Combo)
        let classOfDevice: UInt32 = (0x05 << 8) | (0x03 << 2)
        let deviceType = BluetoothCollector.classifyDevice(classOfDevice: classOfDevice)
        XCTAssertEqual(deviceType, .trackpad)
    }

    func testClassifyUnknownMajorClass() {
        // Major class 0x01 (Computer) — should be .other
        let classOfDevice: UInt32 = (0x01 << 8) | (0x00 << 2)
        let deviceType = BluetoothCollector.classifyDevice(classOfDevice: classOfDevice)
        XCTAssertEqual(deviceType, .other)
    }

    func testClassifyByNameAirPods() {
        // When CoD is ambiguous but name contains "AirPods"
        let deviceType = BluetoothCollector.classifyDevice(classOfDevice: 0, name: "AirPods Pro")
        XCTAssertEqual(deviceType, .headphones)
    }

    func testClassifyByNameMagicMouse() {
        let deviceType = BluetoothCollector.classifyDevice(classOfDevice: 0, name: "Magic Mouse")
        XCTAssertEqual(deviceType, .mouse)
    }

    func testClassifyByNameMagicKeyboard() {
        let deviceType = BluetoothCollector.classifyDevice(classOfDevice: 0, name: "Magic Keyboard")
        XCTAssertEqual(deviceType, .keyboard)
    }

    func testClassifyByNameMagicTrackpad() {
        let deviceType = BluetoothCollector.classifyDevice(classOfDevice: 0, name: "Magic Trackpad")
        XCTAssertEqual(deviceType, .trackpad)
    }

    func testClassifyByNameBeats() {
        let deviceType = BluetoothCollector.classifyDevice(classOfDevice: 0, name: "Beats Studio3")
        XCTAssertEqual(deviceType, .headphones)
    }

    // MARK: - AirPods Battery Detail Tests

    func testAirPodsDetailAllBatteries() {
        let detail = AirPodsDetail(leftBattery: 85, rightBattery: 90, caseBattery: 50)
        XCTAssertEqual(detail.leftBattery, 85)
        XCTAssertEqual(detail.rightBattery, 90)
        XCTAssertEqual(detail.caseBattery, 50)
    }

    func testAirPodsDetailPartialBatteries() {
        let detail = AirPodsDetail(leftBattery: 85, rightBattery: nil, caseBattery: nil)
        XCTAssertEqual(detail.leftBattery, 85)
        XCTAssertNil(detail.rightBattery)
        XCTAssertNil(detail.caseBattery)
    }

    func testAirPodsDetailNoBatteries() {
        let detail = AirPodsDetail(leftBattery: nil, rightBattery: nil, caseBattery: nil)
        XCTAssertNil(detail.leftBattery)
        XCTAssertNil(detail.rightBattery)
        XCTAssertNil(detail.caseBattery)
    }

    func testAirPodsDetailEquality() {
        let a = AirPodsDetail(leftBattery: 85, rightBattery: 90, caseBattery: 50)
        let b = AirPodsDetail(leftBattery: 85, rightBattery: 90, caseBattery: 50)
        XCTAssertEqual(a, b)
    }

    // MARK: - BluetoothDevice Tests

    func testBluetoothDeviceIdentity() {
        let device = BluetoothDevice(
            name: "AirPods Pro",
            address: "AA-BB-CC-DD-EE-FF",
            deviceClass: 0,
            deviceType: .headphones,
            batteryLevel: 85,
            rssi: -45,
            isConnected: true,
            isPaired: true,
            airPodsDetail: AirPodsDetail(leftBattery: 85, rightBattery: 90, caseBattery: 50)
        )

        XCTAssertEqual(device.id, "AA-BB-CC-DD-EE-FF")
        XCTAssertEqual(device.name, "AirPods Pro")
        XCTAssertEqual(device.deviceType, .headphones)
        XCTAssertEqual(device.batteryLevel, 85)
        XCTAssertTrue(device.isConnected)
        XCTAssertTrue(device.isPaired)
        XCTAssertNotNil(device.airPodsDetail)
    }

    func testBluetoothDeviceEquality() {
        let a = BluetoothDevice(
            name: "Mouse", address: "11-22-33-44-55-66",
            deviceClass: 0, deviceType: .mouse,
            batteryLevel: 75, rssi: nil,
            isConnected: false, isPaired: true,
            airPodsDetail: nil
        )
        let b = BluetoothDevice(
            name: "Mouse", address: "11-22-33-44-55-66",
            deviceClass: 0, deviceType: .mouse,
            batteryLevel: 75, rssi: nil,
            isConnected: false, isPaired: true,
            airPodsDetail: nil
        )
        XCTAssertEqual(a, b)
    }

    // MARK: - BluetoothSnapshot Tests

    func testBluetoothSnapshotEmpty() {
        let snapshot = BluetoothSnapshot()
        XCTAssertTrue(snapshot.connectedDevices.isEmpty)
        XCTAssertTrue(snapshot.pairedDisconnectedDevices.isEmpty)
        XCTAssertFalse(snapshot.isBluetoothEnabled)
    }

    func testBluetoothSnapshotWithDevices() {
        let connected = BluetoothDevice(
            name: "AirPods", address: "AA-BB-CC-DD-EE-FF",
            deviceClass: 0, deviceType: .headphones,
            batteryLevel: 85, rssi: -45,
            isConnected: true, isPaired: true,
            airPodsDetail: nil
        )
        let disconnected = BluetoothDevice(
            name: "Mouse", address: "11-22-33-44-55-66",
            deviceClass: 0, deviceType: .mouse,
            batteryLevel: nil, rssi: nil,
            isConnected: false, isPaired: true,
            airPodsDetail: nil
        )

        let snapshot = BluetoothSnapshot(
            connectedDevices: [connected],
            pairedDisconnectedDevices: [disconnected],
            isBluetoothEnabled: true
        )

        XCTAssertEqual(snapshot.connectedDevices.count, 1)
        XCTAssertEqual(snapshot.pairedDisconnectedDevices.count, 1)
        XCTAssertTrue(snapshot.isBluetoothEnabled)
    }

    // MARK: - BluetoothDeviceType Symbol Tests

    func testDeviceTypeSymbolNames() {
        XCTAssertEqual(BluetoothDeviceType.headphones.symbolName, "headphones")
        XCTAssertEqual(BluetoothDeviceType.speaker.symbolName, "hifispeaker")
        XCTAssertEqual(BluetoothDeviceType.mouse.symbolName, "computermouse")
        XCTAssertEqual(BluetoothDeviceType.keyboard.symbolName, "keyboard")
        XCTAssertEqual(BluetoothDeviceType.trackpad.symbolName, "trackpad")
        XCTAssertEqual(BluetoothDeviceType.gamepad.symbolName, "gamecontroller")
        XCTAssertEqual(BluetoothDeviceType.other.symbolName, "wave.3.right")
    }

    // MARK: - Mock Bluetooth Collector Tests

    func testMockBluetoothCollector() async {
        let mock = MockBluetoothCollector()
        XCTAssertEqual(mock.activateCount, 0)

        await mock.activate()
        XCTAssertEqual(mock.activateCount, 1)

        let snapshot = await mock.collect()
        XCTAssertTrue(snapshot.connectedDevices.isEmpty)

        // Set a mock snapshot
        let device = BluetoothDevice(
            name: "Test Device", address: "FF-FF-FF-FF-FF-FF",
            deviceClass: 0, deviceType: .other,
            batteryLevel: 50, rssi: nil,
            isConnected: true, isPaired: true,
            airPodsDetail: nil
        )
        mock.mockSnapshot = BluetoothSnapshot(
            connectedDevices: [device],
            isBluetoothEnabled: true
        )
        let updated = await mock.collect()
        XCTAssertEqual(updated.connectedDevices.count, 1)

        await mock.deactivate()
        XCTAssertEqual(mock.deactivateCount, 1)
    }

    // MARK: - AudioDevice Tests

    func testAudioDeviceCreation() {
        let device = AudioDevice(
            id: "BuiltInSpeaker",
            name: "MacBook Pro Speakers",
            uid: "BuiltInSpeaker",
            isInput: false,
            isOutput: true,
            sampleRate: 48000,
            bufferSize: 512,
            bitDepth: 32
        )

        XCTAssertEqual(device.id, "BuiltInSpeaker")
        XCTAssertEqual(device.name, "MacBook Pro Speakers")
        XCTAssertFalse(device.isInput)
        XCTAssertTrue(device.isOutput)
        XCTAssertEqual(device.sampleRate, 48000)
        XCTAssertEqual(device.bufferSize, 512)
        XCTAssertEqual(device.bitDepth, 32)
    }

    func testAudioDeviceEquality() {
        let a = AudioDevice(
            id: "mic1", name: "Built-in Mic", uid: "mic1",
            isInput: true, isOutput: false,
            sampleRate: 44100, bufferSize: 256, bitDepth: 24
        )
        let b = AudioDevice(
            id: "mic1", name: "Built-in Mic", uid: "mic1",
            isInput: true, isOutput: false,
            sampleRate: 44100, bufferSize: 256, bitDepth: 24
        )
        XCTAssertEqual(a, b)
    }

    // MARK: - AudioSnapshot Tests

    func testAudioSnapshotEmpty() {
        let snapshot = AudioSnapshot()
        XCTAssertNil(snapshot.defaultInput)
        XCTAssertNil(snapshot.defaultOutput)
        XCTAssertEqual(snapshot.volume, 0)
        XCTAssertFalse(snapshot.isMuted)
        XCTAssertTrue(snapshot.allDevices.isEmpty)
        XCTAssertTrue(snapshot.micInUseBy.isEmpty)
        XCTAssertFalse(snapshot.cameraInUse)
        XCTAssertFalse(snapshot.micInUse)
    }

    func testAudioSnapshotMicInUse() {
        let snapshot = AudioSnapshot(
            micInUseBy: ["zoom.us"],
            cameraInUse: false
        )
        XCTAssertTrue(snapshot.micInUse)
        XCTAssertEqual(snapshot.micInUseBy, ["zoom.us"])
    }

    func testAudioSnapshotCameraInUse() {
        let snapshot = AudioSnapshot(
            cameraInUse: true
        )
        XCTAssertTrue(snapshot.cameraInUse)
        XCTAssertFalse(snapshot.micInUse)
    }

    func testAudioSnapshotBothPrivacyIndicators() {
        let snapshot = AudioSnapshot(
            micInUseBy: ["FaceTime"],
            cameraInUse: true
        )
        XCTAssertTrue(snapshot.micInUse)
        XCTAssertTrue(snapshot.cameraInUse)
    }

    func testAudioSnapshotWithDevices() {
        let output = AudioDevice(
            id: "speaker", name: "Built-in Speaker", uid: "speaker",
            isInput: false, isOutput: true,
            sampleRate: 48000, bufferSize: 512, bitDepth: 32
        )
        let input = AudioDevice(
            id: "mic", name: "Built-in Mic", uid: "mic",
            isInput: true, isOutput: false,
            sampleRate: 44100, bufferSize: 256, bitDepth: 24
        )

        let snapshot = AudioSnapshot(
            defaultInput: input,
            defaultOutput: output,
            volume: 0.75,
            isMuted: false,
            allDevices: [output, input]
        )

        XCTAssertEqual(snapshot.defaultOutput?.name, "Built-in Speaker")
        XCTAssertEqual(snapshot.defaultInput?.name, "Built-in Mic")
        XCTAssertEqual(snapshot.volume, 0.75, accuracy: 0.001)
        XCTAssertFalse(snapshot.isMuted)
        XCTAssertEqual(snapshot.allDevices.count, 2)
    }

    func testAudioSnapshotMuted() {
        let snapshot = AudioSnapshot(
            volume: 0.5,
            isMuted: true
        )
        XCTAssertTrue(snapshot.isMuted)
        XCTAssertEqual(snapshot.volume, 0.5, accuracy: 0.001)
    }

    // MARK: - Mock Audio Collector Tests

    func testMockAudioCollector() async {
        let mock = MockAudioCollector()
        XCTAssertEqual(mock.activateCount, 0)

        await mock.activate()
        XCTAssertEqual(mock.activateCount, 1)

        let snapshot = await mock.collect()
        XCTAssertNil(snapshot.defaultOutput)

        mock.mockSnapshot = AudioSnapshot(
            volume: 0.8,
            isMuted: false,
            micInUseBy: ["Zoom"],
            cameraInUse: true
        )
        let updated = await mock.collect()
        XCTAssertEqual(updated.volume, 0.8, accuracy: 0.001)
        XCTAssertTrue(updated.micInUse)
        XCTAssertTrue(updated.cameraInUse)

        await mock.deactivate()
        XCTAssertEqual(mock.deactivateCount, 1)
    }

    // MARK: - Graceful Degradation Tests

    func testBluetoothSnapshotCodable() throws {
        let device = BluetoothDevice(
            name: "Test", address: "AA-BB-CC-DD-EE-FF",
            deviceClass: 1024, deviceType: .headphones,
            batteryLevel: 85, rssi: -50,
            isConnected: true, isPaired: true,
            airPodsDetail: AirPodsDetail(leftBattery: 80, rightBattery: 90, caseBattery: 55)
        )
        let snapshot = BluetoothSnapshot(
            connectedDevices: [device],
            isBluetoothEnabled: true
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(BluetoothSnapshot.self, from: data)

        XCTAssertEqual(decoded.connectedDevices.count, 1)
        XCTAssertEqual(decoded.connectedDevices.first?.name, "Test")
        XCTAssertEqual(decoded.connectedDevices.first?.airPodsDetail?.leftBattery, 80)
        XCTAssertTrue(decoded.isBluetoothEnabled)
    }

    func testAudioSnapshotCodable() throws {
        let device = AudioDevice(
            id: "test", name: "Test Device", uid: "test-uid",
            isInput: true, isOutput: false,
            sampleRate: 44100, bufferSize: 256, bitDepth: 24
        )
        let snapshot = AudioSnapshot(
            defaultInput: device,
            volume: 0.65,
            isMuted: false,
            allDevices: [device],
            micInUseBy: ["Safari"]
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(AudioSnapshot.self, from: data)

        XCTAssertEqual(decoded.defaultInput?.name, "Test Device")
        XCTAssertEqual(decoded.volume, 0.65, accuracy: 0.001)
        XCTAssertEqual(decoded.micInUseBy, ["Safari"])
    }

    // MARK: - Module Registration Tests

    @MainActor
    func testBluetoothModuleRegistration() {
        let registry = ModuleRegistry()
        let module = BluetoothModule()
        registry.register(module)

        XCTAssertEqual(registry.modules.count, 1)
        XCTAssertEqual(registry.modules.first?.id, "bluetooth")
        XCTAssertEqual(registry.modules.first?.symbolName, "bluetooth")
        XCTAssertEqual(registry.modules.first?.category, .peripherals)
        XCTAssertFalse(module.collectors.isEmpty)
    }

    @MainActor
    func testAudioModuleRegistration() {
        let registry = ModuleRegistry()
        let module = AudioModule()
        registry.register(module)

        XCTAssertEqual(registry.modules.count, 1)
        XCTAssertEqual(registry.modules.first?.id, "audio")
        XCTAssertEqual(registry.modules.first?.symbolName, "speaker.wave.2")
        XCTAssertEqual(registry.modules.first?.category, .peripherals)
        XCTAssertFalse(module.collectors.isEmpty)
    }

    @MainActor
    func testBluetoothModulePollingTier() {
        let module = BluetoothModule()
        XCTAssertTrue(module.pollingSubscriptions.contains(.standard))
    }

    @MainActor
    func testAudioModulePollingTier() {
        let module = AudioModule()
        XCTAssertTrue(module.pollingSubscriptions.contains(.standard))
    }

    @MainActor
    func testBluetoothModuleActivateDeactivate() async {
        let module = BluetoothModule()
        // Should not crash even if IOBluetooth is unavailable
        await module.activate()
        await module.deactivate()
    }

    @MainActor
    func testAudioModuleActivateDeactivate() async {
        let module = AudioModule()
        await module.activate()
        await module.deactivate()
    }

    // MARK: - Privacy Indicator Logic Tests

    func testMicInUseIsDerivedFromMicInUseBy() {
        let noMic = AudioSnapshot(micInUseBy: [])
        XCTAssertFalse(noMic.micInUse)

        let withMic = AudioSnapshot(micInUseBy: ["Discord"])
        XCTAssertTrue(withMic.micInUse)

        let multipleProcesses = AudioSnapshot(micInUseBy: ["Zoom", "Chrome"])
        XCTAssertTrue(multipleProcesses.micInUse)
        XCTAssertEqual(multipleProcesses.micInUseBy.count, 2)
    }

    func testCameraInUseIndependent() {
        let cameraOnly = AudioSnapshot(cameraInUse: true)
        XCTAssertTrue(cameraOnly.cameraInUse)
        XCTAssertFalse(cameraOnly.micInUse)

        let neither = AudioSnapshot()
        XCTAssertFalse(neither.cameraInUse)
        XCTAssertFalse(neither.micInUse)
    }
}
