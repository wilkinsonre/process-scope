# ProcessScope — Native macOS System Monitor

## Project Overview
ProcessScope is a native macOS system monitoring app with deep process introspection + action control surface. Shows *what* processes are doing, not just resource consumption. Built with Swift 6 + SwiftUI for macOS 15.0+ (Sequoia), targeting Apple Silicon.

**Two components:**
- `ProcessScope.app` — SwiftUI dashboard + menu bar UI (standard user)
- `ProcessScope Helper` — Privileged data collection + action execution LaunchDaemon (root via `SMAppService`)
- IPC via `NSXPCConnection` with bidirectional audit-token validation

**12 Modules (independently toggle-able):**
CPU, Memory, GPU & Neural Engine, Processes, Storage, Network, Bluetooth, Power & Thermal, Audio, Display, Security, Developer

**Action Layer:** Process kill/suspend, drive eject, Docker management, network actions, system actions — all off by default, confirmation-gated, audit-logged.

## Build & Run
```bash
xcodebuild -project ProcessScope.xcodeproj -scheme ProcessScope -configuration Debug build
xcodebuild -project ProcessScope.xcodeproj -scheme ProcessScopeTests test
xcodebuild -project ProcessScope.xcodeproj -scheme ProcessScope -configuration Release build
./Scripts/create-dmg.sh
./Scripts/notarize.sh
```

## Code Style
- Swift 6 strict concurrency — `@Sendable`, `actor`, `async/await` everywhere
- All collectors behind protocols for testability and graceful degradation
- `Swift Concurrency` over GCD except `DispatchSourceTimer` in polling layer
- `@MainActor` for all SwiftUI view models
- SF Symbols for all icons — no custom icon assets except app icon
- System colors only — no hardcoded hex values
- 4-space indentation, no trailing whitespace
- DocC comments on all public types and functions
- `// MARK: - Section Name` to organize file sections

## Architecture Rules
- **NEVER** use private Apple frameworks directly — wrap IOReport in `IOKitWrapper.swift`
- **ALWAYS** protocol-wrap collectors — if an API fails, UI shows "unavailable" not crash
- Helper daemon caches data internally; app polls helper, never makes direct syscalls for privileged data
- All C interop lives in `Sources/Utilities/CInterop/` — no raw C calls elsewhere
- XPC protocol defined once in `Sources/Core/XPC/PSHelperProtocol.swift`, shared by both targets
- Process enrichment rules loaded from YAML — built-in defaults in `Resources/DefaultEnrichmentRules.yaml`
- **Module Registry** — every module registers via `ModuleRegistry` protocol. Disabled modules have ZERO overhead (no polling, no history buffers, no XPC subscriptions)
- **Action Safety** — ALL destructive actions gated behind ConfirmationDialog. ALL actions audit-logged to `~/.processscope/actions.log`. Helper-required actions show "Install helper to enable" when helper absent
- **Alert Engine** — YAML-configured threshold rules evaluated per polling tick. Delivery via `UNUserNotificationCenter`

## Performance Budget (HARD GATES)
| Metric | Default Modules | All Modules |
|--------|----------------|-------------|
| CPU (dashboard visible) | < 2% | < 3% |
| CPU (menu bar only) | < 0.5% | < 0.5% |
| RSS memory | < 80 MB | < 120 MB |
| Helper daemon RSS | < 15 MB | < 25 MB |
| Launch to first data | < 1.5s | < 1.5s |
| Energy impact | "Low" | "Moderate" OK |

## Polling Tiers
| Tier | Interval | Data |
|------|----------|------|
| Critical | 500ms | System CPU, memory pressure, GPU util, power draw, thermal |
| Standard | 1s | Process list, per-process CPU/mem, disk I/O, audio routing, BT battery |
| Extended | 3s | Network connections, process args, Docker, SSH, VPN/Tailscale, listening ports, builds |
| Slow | 10s | Full tree rebuild, ANE, external drives, WiFi, firewall, Bonjour, security |
| Infrequent | 60s | Speed test (if auto), Time Machine, battery health, TCC refresh |

Adaptive: window hidden → 2× intervals. On battery → all tiers double.

## Testing Strategy
- Unit tests for enrichment rules, tree builder, project grouper, alert engine, action confirmations
- Mock protocols for ALL collectors — test without root access
- Integration tests for XPC roundtrip (requires helper installed)
- Docker API action tests with mock socket
- Performance tests with Instruments profiles saved as baselines
- 24-hour soak test with >300 processes before release

## Key API Notes
- `KERN_PROCARGS2` returns null-separated: executable path, then args, then env vars
- `proc_pidinfo` with `PROC_PIDVNODEPATHINFO` for working directory
- `IOServiceGetMatchingServices` with `IOAccelerator` for GPU stats
- Docker socket at `/var/run/docker.sock` — also check Colima/OrbStack paths
- `SMAppService` for helper registration (macOS 13+ replacement for `SMJobBless`)
- `DiskArbitration` framework for eject/unmount operations
- CoreWLAN `CWWiFiClient` for WiFi details (no private APIs)
- IOBluetooth framework for device enumeration + battery
- CoreAudio `AudioObject*` for audio routing + privacy indicators
- Tailscale local API at `http://100.100.100.100/localapi/v0/status` (no auth from localhost)
- `UNUserNotificationCenter` for alert delivery

## When Compacting
Preserve: current milestone progress, list of completed files, performance budget numbers, architecture rules, polling tier intervals, module list, action safety rules, and any failing test information.

## Git Workflow
- Main branch: `main`
- Feature branches: `feature/{milestone}-{description}` (e.g., `feature/m5-action-layer`)
- Atomic commits per logical unit
- Run `xcodebuild test` before every commit
- No force pushes

## Distribution
- GitHub Releases as notarized `.dmg`
- Sparkle for auto-updates
- MIT License
