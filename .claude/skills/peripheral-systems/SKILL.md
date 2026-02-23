---
name: peripheral-systems
description: Peripheral and system-level collectors for ProcessScope Amendment A. Use when implementing Bluetooth device monitoring (IOBluetooth), audio routing (CoreAudio), display/graphics details (CoreGraphics), security posture (SIP/FileVault/TCC), developer metrics (build detection, LSP), or virtualization detection (Docker/Parallels/UTM/VMware).
---

# Peripheral & System Collectors

## Bluetooth (IOBluetooth Framework)

```swift
import IOBluetooth

actor BluetoothCollector: SystemCollector {
    typealias Snapshot = BluetoothSnapshot
    
    func collect() async throws -> BluetoothSnapshot {
        var devices: [BluetoothDevice] = []
        
        guard let pairedDevices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return BluetoothSnapshot(devices: [])
        }
        
        for device in pairedDevices {
            var batteryLevel: Int?
            
            // Battery level from IOKit properties
            if let ioService = findIOService(for: device) {
                var properties: Unmanaged<CFMutableDictionary>?
                if IORegistryEntryCreateCFProperties(ioService, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                   let dict = properties?.takeRetainedValue() as? [String: Any] {
                    batteryLevel = dict["BatteryPercent"] as? Int
                }
                IOObjectRelease(ioService)
            }
            
            // AirPods detection via device class + name heuristics
            let airPodsDetail = detectAirPods(device: device)
            
            devices.append(BluetoothDevice(
                name: device.name ?? "Unknown",
                address: device.addressString ?? "",
                isConnected: device.isConnected(),
                deviceType: classifyDevice(device),
                batteryLevel: batteryLevel,
                airPodsDetail: airPodsDetail,
                rssi: device.isConnected() ? readRSSI(device) : nil,
                firmwareVersion: readFirmware(device)
            ))
        }
        
        return BluetoothSnapshot(devices: devices)
    }
    
    private func classifyDevice(_ device: IOBluetoothDevice) -> BluetoothDeviceType {
        let classOfDevice = device.classOfDevice
        let majorClass = (classOfDevice >> 8) & 0x1F
        let minorClass = (classOfDevice >> 2) & 0x3F
        
        switch majorClass {
        case 0x04: // Audio/Video
            if minorClass == 0x01 || minorClass == 0x02 { return .headphones }
            return .speaker
        case 0x05: // Peripheral
            if minorClass == 0x01 { return .keyboard }
            if minorClass == 0x02 { return .mouse }
            if minorClass == 0x03 { return .trackpad }
            return .gamepad
        default: return .other
        }
    }
    
    /// AirPods expose L/R/Case battery via IOKit
    private func detectAirPods(device: IOBluetoothDevice) -> AirPodsDetail? {
        guard let name = device.name, name.contains("AirPods") else { return nil }
        // Read from IOKit: BatteryPercentCombined, BatteryPercentCase, etc.
        // Apple-specific keys — degrade gracefully if not present
        return nil // Implement with IOKit registry read
    }
}

enum BluetoothDeviceType: String, Codable {
    case headphones, speaker, mouse, keyboard, trackpad, gamepad, other
    
    var icon: String {
        switch self {
        case .headphones: return "headphones"
        case .speaker: return "hifispeaker"
        case .mouse: return "computermouse"
        case .keyboard: return "keyboard"
        case .trackpad: return "trackpad"
        case .gamepad: return "gamecontroller"
        case .other: return "wave.3.right"
        }
    }
}
```

## Audio Routing (CoreAudio)

```swift
import CoreAudio
import AudioToolbox

actor AudioCollector: SystemCollector {
    typealias Snapshot = AudioSnapshot
    
    func collect() async throws -> AudioSnapshot {
        let defaultOutput = try defaultDevice(for: kAudioHardwarePropertyDefaultOutputDevice)
        let defaultInput = try defaultDevice(for: kAudioHardwarePropertyDefaultInputDevice)
        
        return AudioSnapshot(
            outputDevice: defaultOutput,
            inputDevice: defaultInput,
            volume: try systemVolume(),
            isMuted: try isSystemMuted(),
            micInUseBy: microphoneUsers(),
            audioProducers: audioProducers()
        )
    }
    
    private func defaultDevice(for property: AudioObjectPropertySelector) throws -> AudioDeviceInfo {
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: property,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceID
        )
        guard status == noErr else { throw CollectorError.unavailable("CoreAudio") }
        
        return AudioDeviceInfo(
            id: deviceID,
            name: try deviceName(deviceID),
            sampleRate: try sampleRate(deviceID),
            bufferSize: try bufferSize(deviceID)
        )
    }
    
    private func deviceName(_ id: AudioDeviceID) throws -> String {
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name)
        guard status == noErr else { throw CollectorError.unavailable("Device name") }
        return name as String
    }
    
    /// Detect which processes are using the microphone
    /// Correlates with macOS privacy indicator (orange dot)
    func microphoneUsers() -> [ProcessAudioInfo] {
        // Check for processes that have opened audio input
        // TCC database approach (requires FDA) or process inspection for coreaudiod clients
        var results: [ProcessAudioInfo] = []
        // Implementation: enumerate coreaudiod's clients via AudioObject APIs
        return results
    }
}
```

## Display & Graphics (CoreGraphics)

```swift
import CoreGraphics
import AppKit

actor DisplayCollector: SystemCollector {
    typealias Snapshot = DisplaySnapshot
    
    func collect() async throws -> DisplaySnapshot {
        var displays: [DisplayInfo] = []
        
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: 16)
        var displayCount: UInt32 = 0
        CGGetActiveDisplayList(16, &displayIDs, &displayCount)
        
        for i in 0..<Int(displayCount) {
            let id = displayIDs[i]
            guard let mode = CGDisplayCopyDisplayMode(id) else { continue }
            
            let screen = NSScreen.screens.first { screen in
                let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
                return screenNumber == id
            }
            
            displays.append(DisplayInfo(
                id: id,
                name: displayName(id),
                isBuiltIn: CGDisplayIsBuiltin(id) != 0,
                width: mode.width,
                height: mode.height,
                pixelWidth: mode.pixelWidth,
                pixelHeight: mode.pixelHeight,
                refreshRate: mode.refreshRate,
                isHDR: screen?.maximumExtendedDynamicRangeColorComponentValue ?? 1.0 > 1.0,
                connectionType: connectionType(id),
                colorProfile: colorProfileName(id)
            ))
        }
        
        return DisplaySnapshot(displays: displays)
    }
    
    private func connectionType(_ displayID: CGDirectDisplayID) -> String {
        // IOKit registry traversal from CGDisplay → IOFramebuffer → parent transport
        if CGDisplayIsBuiltin(displayID) != 0 { return "Built-in" }
        // Check IOKit for HDMI, DisplayPort, USB-C
        return "External"
    }
}
```

## Security Posture

```swift
actor SecurityCollector: SystemCollector {
    typealias Snapshot = SecuritySnapshot
    
    func collect() async throws -> SecuritySnapshot {
        return SecuritySnapshot(
            sipEnabled: checkSIP(),
            fileVaultEnabled: checkFileVault(),
            gatekeeperEnabled: checkGatekeeper(),
            firewallEnabled: checkFirewall(),
            cameraInUse: detectCameraUse(),
            micInUse: detectMicUse(),
            loginItems: enumerateLoginItems(),
            launchAgents: enumerateLaunchAgents(),
            tccPermissions: readTCCPermissions()  // Requires FDA
        )
    }
    
    private func checkSIP() -> Bool {
        let output = shellOutput("/usr/bin/csrutil", args: ["status"])
        return output.contains("enabled")
    }
    
    private func checkFileVault() -> Bool {
        let output = shellOutput("/usr/bin/fdesetup", args: ["status"])
        return output.contains("FileVault is On")
    }
    
    private func checkGatekeeper() -> Bool {
        let output = shellOutput("/usr/sbin/spctl", args: ["--status"])
        return output.contains("assessments enabled")
    }
    
    /// Camera in use: detect VDCAssistant or AppleCameraAssistant process
    private func detectCameraUse() -> ProcessAudioInfo? {
        let procs = SysctlWrapper.allProcesses()
        for proc in procs {
            let name = processName(for: proc.kp_proc.p_pid)
            if name == "VDCAssistant" || name == "AppleCameraAssistant" {
                // Find the client process that triggered the camera
                // by checking the parent chain
                return ProcessAudioInfo(pid: proc.kp_proc.p_pid, name: name)
            }
        }
        return nil
    }
    
    /// TCC database read — requires Full Disk Access
    private func readTCCPermissions() -> [TCCPermission]? {
        let tccPath = "/Library/Application Support/com.apple.TCC/TCC.db"
        guard FileManager.default.isReadableFile(atPath: tccPath) else {
            return nil  // No FDA — degrade gracefully
        }
        // SQLite query: SELECT client, service, auth_value FROM access
        // Returns which apps have which permissions
        return nil // Implement with SQLite3 C API
    }
    
    private func enumerateLoginItems() -> [LoginItem] {
        // SMAppService.mainApp.status for the app itself
        // ~/Library/LaunchAgents/ enumeration
        let agentsPath = NSHomeDirectory() + "/Library/LaunchAgents"
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: agentsPath) else { return [] }
        return files.filter { $0.hasSuffix(".plist") }.map { LoginItem(label: $0, path: agentsPath + "/" + $0) }
    }
    
    private func enumerateLaunchAgents() -> [LaunchAgent] {
        // /Library/LaunchDaemons/ + ~/Library/LaunchAgents/
        var agents: [LaunchAgent] = []
        let paths = ["/Library/LaunchDaemons", NSHomeDirectory() + "/Library/LaunchAgents"]
        for basePath in paths {
            guard let files = try? FileManager.default.contentsOfDirectory(atPath: basePath) else { continue }
            for file in files where file.hasSuffix(".plist") {
                agents.append(LaunchAgent(label: file, path: basePath + "/" + file, scope: basePath.hasPrefix("/Library") ? .system : .user))
            }
        }
        return agents
    }
}
```

## Developer Metrics

```swift
actor DeveloperMetricsCollector {
    func collect() async -> DeveloperSnapshot {
        return DeveloperSnapshot(
            activeBuilds: detectBuilds(),
            localServers: checkLocalServers(),
            languageServers: detectLSPs(),
            gitOperations: detectGitOps()
        )
    }
    
    private func detectBuilds() -> [BuildInfo] {
        var builds: [BuildInfo] = []
        let procs = SysctlWrapper.allProcesses()
        
        for proc in procs {
            let pid = proc.kp_proc.p_pid
            let name = processName(for: pid)
            
            switch name {
            case "xcodebuild", "XCBBuildService":
                let phase = detectXcodeBuildPhase(pid)
                builds.append(BuildInfo(tool: "Xcode", phase: phase, pid: pid,
                    startTime: Date(timeIntervalSince1970: TimeInterval(proc.kp_proc.p_starttime.tv_sec))))
                
            case "swiftc" where hasParent(pid, named: "swift-build"):
                builds.append(BuildInfo(tool: "Swift Package", phase: "compiling", pid: pid,
                    startTime: Date(timeIntervalSince1970: TimeInterval(proc.kp_proc.p_starttime.tv_sec))))
                
            case "cargo" where argvContains(pid, "build"):
                builds.append(BuildInfo(tool: "Cargo", phase: "building", pid: pid,
                    startTime: Date(timeIntervalSince1970: TimeInterval(proc.kp_proc.p_starttime.tv_sec))))
                
            case "go" where argvContains(pid, "build"):
                builds.append(BuildInfo(tool: "Go", phase: "building", pid: pid,
                    startTime: Date(timeIntervalSince1970: TimeInterval(proc.kp_proc.p_starttime.tv_sec))))
                
            default: continue
            }
        }
        return builds
    }
    
    private func detectXcodeBuildPhase(_ pid: pid_t) -> String {
        // Check child processes: clang → compiling, ld → linking, codesign → signing
        let children = SysctlWrapper.allProcesses().filter { $0.kp_eproc.e_ppid == pid }
        for child in children {
            let name = processName(for: child.kp_proc.p_pid)
            switch name {
            case "clang", "swiftc": return "compiling"
            case "ld", "ld64": return "linking"
            case "codesign": return "signing"
            default: continue
            }
        }
        return "building"
    }
    
    private func checkLocalServers() -> [LocalServerHealth] {
        // HTTP GET to each detected listening port on localhost
        var results: [LocalServerHealth] = []
        let ports = listeningPorts().filter { $0.bindAddress == "127.0.0.1" || $0.bindAddress == "0.0.0.0" }
        
        for port in ports {
            // Quick health check — 1 second timeout
            let url = URL(string: "http://127.0.0.1:\(port.port)/")!
            var request = URLRequest(url: url, timeoutInterval: 1.0)
            request.httpMethod = "HEAD"
            
            // Fire-and-forget style check, collect results asynchronously
            results.append(LocalServerHealth(
                port: port.port,
                processName: port.processName,
                status: .checking
            ))
        }
        return results
    }
    
    private func detectLSPs() -> [LSPInfo] {
        let lspNames = ["sourcekit-lsp", "typescript-language-server", "pyright", 
                        "rust-analyzer", "gopls", "clangd", "lua-language-server"]
        var active: [LSPInfo] = []
        let procs = SysctlWrapper.allProcesses()
        for proc in procs {
            let name = processName(for: proc.kp_proc.p_pid)
            if lspNames.contains(name) {
                active.append(LSPInfo(name: name, pid: proc.kp_proc.p_pid))
            }
        }
        return active
    }
}
```

## Virtualization Detection

```swift
actor VirtualizationCollector {
    func collect() async -> VirtualizationSnapshot {
        return VirtualizationSnapshot(
            docker: await detectDocker(),
            vms: detectVMs()
        )
    }
    
    private func detectVMs() -> [VMInfo] {
        var vms: [VMInfo] = []
        let procs = SysctlWrapper.allProcesses()
        
        for proc in procs {
            let pid = proc.kp_proc.p_pid
            let name = processName(for: pid)
            
            switch name {
            case "prl_vm_app":  // Parallels
                vms.append(VMInfo(platform: .parallels, name: vmName(pid), pid: pid))
            case _ where name.hasPrefix("qemu-system"):  // UTM/QEMU
                vms.append(VMInfo(platform: .utm, name: vmName(pid), pid: pid))
            case "vmware-vmx":  // VMware Fusion
                vms.append(VMInfo(platform: .vmwareFusion, name: vmName(pid), pid: pid))
            default: continue
            }
        }
        
        // Check Lima
        if let limaOutput = try? shellOutputJSON("/usr/local/bin/limactl", args: ["list", "--json"]) {
            // Parse Lima VMs
        }
        
        return vms
    }
}
```
