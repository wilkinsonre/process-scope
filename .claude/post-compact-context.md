## Post-Compaction Context — ProcessScope (Full Scope)

### What You're Building
ProcessScope: native macOS system monitor + control surface with deep process introspection. Two components: SwiftUI app + privileged helper daemon (XPC). 12 independently toggleable modules. Action layer (off by default). Alert engine with notification delivery.

### Critical Architecture Rules
- ALL C interop in `Sources/Utilities/CInterop/` — nowhere else
- ALL IOReport access in `IOKitWrapper.swift` — the only semi-private API touchpoint
- Every collector behind a protocol — graceful degradation, never crash
- Helper daemon serves cached snapshots; app polls helper via XPC
- XPC protocol uses `@objc` with `Data` (Codable serialization), not raw Swift types
- Swift 6 strict concurrency: actors for shared state, @MainActor on ViewModels
- **Module Registry**: disabled modules = ZERO overhead (no polling, no buffers, no XPC)
- **Action Safety**: ALL destructive actions need ConfirmationDialog, ALL logged to AuditTrail
- **Sidebar is dynamic** — driven by ModuleRegistry, not hardcoded enum

### Performance Budget (HARD GATES)
- CPU <2% default modules, <3% all modules (dashboard visible)
- CPU <0.5% (menu bar only)
- RSS <80MB default, <120MB all modules
- Helper <25MB RSS
- Launch to first data <1.5s

### Polling Tiers
- Critical: 500ms (CPU, memory, GPU, power, thermal)
- Standard: 1s (process list, per-process, disk I/O, audio, BT battery)
- Extended: 3s (network, Docker, SSH, VPN/Tailscale, listening ports, builds)
- Slow: 10s (full tree rebuild, ANE, external drives, WiFi, firewall, security)
- Infrequent: 60s (speed test, Time Machine, battery health, TCC refresh)

### 12 Modules
CPU, Memory, GPU & Neural Engine, Processes, Storage, Network, Bluetooth, Power & Thermal, Audio, Display, Security, Developer

### Subagents Available
- `core-systems` — Sources/Core/, CInterop/, Helper/
- `ui-builder` — Sources/UI/, Sources/App/
- `expanded-collectors` — M7-M10 new module collectors
- `action-builder` — M5, M11, M12 action layer
- `alert-builder` — M13 alert engine
- `tester` — verification after each milestone

### Current Progress
Check `git log --oneline -15` and `git diff --stat` to see what's been completed.

### Verification
- `xcodebuild -scheme ProcessScopeTests test` — must pass
- No force unwraps outside tests
- SF Symbols only, system colors only
- Disabled modules = zero polling subscriptions
- All actions logged to audit trail
