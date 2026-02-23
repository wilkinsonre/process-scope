# ProcessScope — Master Build Prompt (Full Scope)

> **Covers:** PRD v1.0 + Amendment A — 100% feature coverage across 13 milestones
> **Estimated context cycles:** 5 phases with compaction between each
> Paste this into Claude Code at the project root after placing .claude/ and CLAUDE.md.

---

## Context Management Strategy

This build is large (13 milestones, ~15K+ lines of Swift). To prevent context exhaustion:

1. **Execute in 5 phases** with `/compact` between each phase
2. **Delegate to subagents** for domain-specific implementation (keeps main context clean)
3. **Verify after each milestone** using the `tester` subagent
4. **Git commit after each milestone** — commits are checkpoints
5. **After each `/compact`**, the post-compact hook re-injects critical context

**Phase execution order:**
- **Phase A** (M1–M3): Foundation + Core Intelligence
- **Phase B** (M4–M5): Full Dashboard + Action Layer v1
- **Phase C** (M6): Polish + Release Prep
- **Phase D** (M7–M10): Expanded Observation Modules
- **Phase E** (M11–M13): Control Actions + Alert Engine

---

## Prompt

Build ProcessScope, a native macOS system monitoring and control application. Execute all 13 milestones across 5 phases. The full PRD is in `PRD.md` and Amendment A is in `PRD-AMENDMENT-A.md`. Use subagents for domain-specific implementation. Commit after each milestone. Compact between phases.

---

## PHASE A: Foundation + Core Intelligence (M1–M3)

### M1: Scaffold (commit: "feat: M1 — project scaffold, XPC helper, process list")

**Delegate to `core-systems` subagent:**

1. Create the Xcode project structure. Two targets:
   - `ProcessScope` (macOS App, Swift 6, deployment target 15.0)
   - `ProcessScopeHelper` (Command Line Tool, runs as LaunchDaemon)
2. Implement the shared XPC protocol (`PSHelperProtocol.swift`) with:
   - `getProcessSnapshot(reply:)` → Codable `ProcessSnapshot` as Data
   - `getSystemMetrics(reply:)` → Codable `SystemMetricsSnapshot` as Data
   - `getNetworkConnections(reply:)` → Codable `NetworkSnapshot` as Data
   - `getHelperVersion(reply:)` → String
   - Action methods (stubs for now): `killProcess`, `purgeMemory`, `flushDNS`, `forceEjectVolume`, `reconnectNetworkVolume`, `setProcessPriority`
3. Implement C interop wrappers in `Sources/Utilities/CInterop/`:
   - `SysctlWrapper.swift` — `allProcesses()` via KERN_PROC, `processArguments(for:)` via KERN_PROCARGS2
   - `LibProc.swift` — `processPath(for:)`, `workingDirectory(for:)`, `processResourceUsage(for:)`, `socketInfo(for:)`
   - `IOKitWrapper.swift` — stub for GPU/IOReport (returns nil gracefully)
4. Implement `ProcessCollector` behind `SystemCollector` protocol
5. Create the helper daemon entry point (`Helper/main.swift`, `HelperTool.swift`)

**Delegate to `ui-builder` subagent (parallel with above):**

6. Create the app entry point with a minimal SwiftUI window showing a flat process table
7. Create `SidebarItem` structure (dynamic, driven by `ModuleRegistry`)

**Delegate to `core-systems` subagent:**

8. Implement `ProcessTreeBuilder` — converts flat process list into parent-child tree
9. Implement `ModuleRegistry` protocol and base infrastructure
10. Implement `PollingCoordinator` with five tiers (500ms/1s/3s/10s/60s) and `AdaptivePollPolicy`

**Delegate to `tester` subagent:**

11. Write `ProcessTreeBuilderTests` with mock data
12. Write `ModuleRegistryTests` — enable/disable, zero-overhead verification

**After verification:** `git add -A && git commit -m "feat: M1 — project scaffold, XPC helper, process list, module registry"`

---

### M2: Core Metrics (commit: "feat: M2 — collectors, polling coordinator, dashboard overview")

**Delegate to `core-systems` subagent:**

1. Implement all base collectors behind `SystemCollector` protocol:
   - `CPUCollector` — `host_processor_info` for per-core, total CPU
   - `MemoryCollector` — `vm_statistics64` for segmented memory
   - `GPUCollector` — IOKit `IOAccelerator` for utilization %
   - `DiskCollector` — per-process I/O via `proc_pidinfo`
   - `NetworkCollector` — socket enumeration via `proc_pidinfo` PROC_PIDLISTFDS
   - `ThermalCollector` — `ProcessInfo.thermalState` + IOReport stub

**Delegate to `ui-builder` subagent (parallel):**

2. Build the Dashboard Overview panel:
   - `DashboardView` with dynamic sidebar from `ModuleRegistry`
   - `OverviewPanel` with 6 widget cards in adaptive grid
   - `RingGauge`, `SparklineView`, `SegmentedBar`, `HeatmapStrip` components
3. Wire up `MetricsViewModel` consuming polling coordinator

**Delegate to `tester` subagent:**

4. Write `CPUCollectorTests`, `MemoryCollectorTests` with mocks

**Commit:** `git commit -m "feat: M2 — collectors, polling coordinator, dashboard overview"`

---

### M3: Process Intelligence (commit: "feat: M3 — enrichment engine, enriched tree UI")

**Delegate to `core-systems` subagent:**

1. Implement `ProcessEnricher`:
   - Parse KERN_PROCARGS2 output into exec path + arguments
   - Rule engine matching: processName, argvContains, argvRegex
   - Template resolution: `{argv_after:X|first}`, `{argv_value:--flag|default:Y}`, `{argv_match_basename}`, `{cwd_basename}`, `{port}`
2. Create `DefaultEnrichmentRules.yaml` with all 15+ rules from PRD Section 6.3.2
3. Implement YAML parser for enrichment rules
4. Implement port detection — scan socket FDs for LISTEN state

**Delegate to `ui-builder` subagent:**

5. Build `ProcessTreeView` with `OutlineGroup` showing enriched labels
6. Build `ProcessRowView` with icon, enriched label, working directory, CPU%, memory
7. Build `ProcessInspectorView` — full args, env, open files, parent chain
8. Build `ProjectGroupingView` — processes grouped by project directory

**Delegate to `tester` subagent:**

9. Write `ProcessEnricherTests` covering all 15+ built-in rules + edge cases

**Commit:** `git commit -m "feat: M3 — enrichment engine, enriched tree UI, project grouping"`

---

### ⚡ COMPACT NOW

Run `/compact Focus on Phase B. Preserve: completed milestones M1-M3, file structure, architecture rules, performance budget, module registry pattern, enrichment engine status.`

---

## PHASE B: Full Dashboard + Action Layer v1 (M4–M5)

### M4: Full Dashboard (commit: "feat: M4 — all detail views, menu bar, settings")

**Delegate to `ui-builder` subagent:**

1. Implement all base detail views:
   - `CPUDetailView` — cluster view (E/P cores), per-core heatmap, frequency, load average, top processes, 60s sparklines
   - `MemoryDetailView` — pressure gauge, swap, top consumers, compression ratio
   - `GPUDetailView` — utilization ring, frequency, power, ANE, temperature
   - `NetworkDetailView` — interface list, sparklines, per-process connections, top talkers
   - `DiskDetailView` — per-volume usage, I/O sparklines, top I/O processes
2. Implement menu bar widget:
   - `MenuBarView` with three modes: mini, compact, sparkline
   - Menu bar popover vs window toggle
3. Implement `SettingsView` with 7 tabs:
   - General (launch at login, appearance, units, helper status)
   - Modules (drag-to-reorder, master toggle + sub-feature toggles)
   - Actions (category toggles, helper requirement badges) — UI only, actions in M5
   - Alerts (rule list, add/edit/delete) — UI only, engine in M13
   - Menu Bar (mode selection, metric reorder)
   - Advanced (polling overrides, enrichment rules, project directories)
   - About
4. Wire adaptive polling: visibility detection, battery mode

**Delegate to `tester` subagent:**

5. Verify all views compile, sidebar navigation works, settings persist

**Commit:** `git commit -m "feat: M4 — all detail views, menu bar, modular settings"`

---

### M5: Action Layer v1 (commit: "feat: M5 — process actions, eject, clipboard")

**Delegate to `action-builder` subagent:**

1. Implement `ActionConfiguration` — @AppStorage toggles for all action categories
2. Implement `AuditTrail` — append-only log at `~/.processscope/actions.log`
3. Implement `ActionViewModel` — confirmation flow, pending action queue
4. Implement process actions:
   - Kill (SIGTERM), Force Kill (SIGKILL), Suspend (SIGSTOP), Resume (SIGCONT)
   - Kill process group (SIGTERM to group)
   - Kill project processes (iterate grouped PIDs)
   - Renice (setpriority)
   - Force quit application (NSRunningApplication.forceTerminate)
5. Implement storage actions:
   - Eject (DADiskEject), Force eject, Unmount
   - Open in Finder, Open in Disk Utility
   - Eject readiness check (open file handle scan)
6. Implement clipboard actions:
   - Context-sensitive copy on every data element
   - Reveal in Finder
7. Implement keyboard shortcuts via NSEvent.addLocalMonitorForEvents
8. Extend PSHelperProtocol with action methods (killProcess, forceEjectVolume, setProcessPriority)

**Delegate to `ui-builder` subagent (parallel):**

9. Add `ProcessContextMenu` to process tree rows
10. Add `ActionConfirmationDialog` view
11. Wire actions into Settings → Actions tab

**Delegate to `tester` subagent:**

12. Test audit trail logging
13. Test confirmation flow
14. Test action configuration toggles

**Commit:** `git commit -m "feat: M5 — process actions, eject, clipboard, audit trail"`

---

### ⚡ COMPACT NOW

Run `/compact Focus on Phase C. Preserve: completed M1-M5, file structure, all module/action/settings patterns, performance budget.`

---

## PHASE C: Polish + Release Prep (M6)

### M6: Polish (commit: "feat: M6 — performance optimization, packaging, release prep")

1. Performance optimization:
   - Profile with Instruments — verify CPU <2% with default modules
   - Profile memory — verify RSS <80MB with default modules
   - Optimize list rendering (LazyVStack, background prefetch)
   - Verify disabled modules = zero polling subscriptions
2. Helper install onboarding flow:
   - First-launch dialog explaining helper purpose
   - `HelperInstaller` with SMAppService register/unregister
   - Settings → General shows helper status
3. Sparkle auto-updater integration:
   - Add Sparkle SPM dependency
   - Configure appcast URL
   - Add "Check for Updates" menu item
4. Distribution:
   - Code signing configuration (Developer ID)
   - Notarization script (`Scripts/notarize.sh`)
   - DMG creation script (`Scripts/create-dmg.sh`)
   - App icon (placeholder — system gauge symbol)
   - README.md with screenshots, feature list, install instructions
5. Final test suite run — all tests must pass

**Commit:** `git commit -m "feat: M6 — performance optimization, Sparkle, notarization, v0.1.0 release prep"`

**Tag:** `git tag -a v0.1.0 -m "ProcessScope v0.1.0 — Foundation + Core Intelligence + Actions v1"`

---

### ⚡ COMPACT NOW

Run `/compact Focus on Phase D. Preserve: v0.1.0 tag, file structure, ModuleRegistry pattern, SystemCollector protocol, PollingCoordinator tier subscription pattern, expanded-collectors agent instructions.`

---

## PHASE D: Expanded Observation Modules (M7–M10)

### M7: Storage Expansion (commit: "feat: M7 — external drives, SMART, network volumes, Time Machine")

**Delegate to `expanded-collectors` subagent:**

1. Implement `StorageModule` registered with `ModuleRegistry`
2. Implement `StorageCollector`:
   - Volume discovery via `statfs`/`getmntinfo`
   - Connection interface detection via IOKit registry traversal (USB/TB/NVMe)
   - Theoretical bandwidth from interface type
   - Real-time R/W speed from `IOBlockStorageDriver` statistics
   - SMART status via IOKit (helper for external SSDs)
   - Disk temperature from SMC/SMART
   - Encryption status from `diskutil apfs list`
   - Time Machine status from `tmutil status`
   - Eject readiness — open file handle check
3. Network volume details:
   - SMB: `smbutil statshares` for protocol version, signing, authentication
   - NFS: `nfsstat` for mount options and latency
   - Connection status via socket state
4. Subscribe to Slow tier (10s) for drive details, Infrequent (60s) for Time Machine

**Delegate to `ui-builder` subagent:**

5. Build `StorageDetailView` with per-volume cards
6. Build `VolumeCardView` with usage bar, connection type, eject button
7. Build `NetworkVolumeRow` with server/protocol/latency

**Delegate to `tester` subagent:**

8. Test volume parsing, SMART status, Time Machine status parsing

**Commit:** `git commit -m "feat: M7 — storage module, external drives, SMART, network volumes, Time Machine"`

---

### M8: Network Intelligence (commit: "feat: M8 — SSH, VPN/Tailscale, WiFi, listening ports, speed test")

**Delegate to `expanded-collectors` subagent:**

1. Implement `NetworkModule` (replaces base network collector, registered with ModuleRegistry)
2. Sub-collectors (each behind own toggle):
   - `InterfaceCollector` — `SCNetworkInterface`, `getifaddrs`, external IP fetch, DNS latency
   - `SSHSessionCollector` — process inspection, argv parsing, socket byte counters
   - `TailscaleCollector` — local API at 100.100.100.100, peer status, DERP relay
   - `WiFiCollector` — CoreWLAN CWWiFiClient, RSSI/SNR, on-demand scan
   - `SpeedTestRunner` — `networkQuality -v -c`, background execution, JSON parsing
   - `ListeningPortsCollector` — proc_pidinfo socket enumeration, cross-ref enrichment
   - `BonjourCollector` — NSNetServiceBrowser (disabled by default)
   - `FirewallCollector` — socketfilterfw + pfctl status (disabled by default)
3. Subscribe to appropriate tiers: Extended (3s) for SSH/VPN/ports, Slow (10s) for WiFi/firewall, Infrequent (60s) for speed test

**Delegate to `ui-builder` subagent:**

4. Build `NetworkDetailView` with sub-panels:
   - Interfaces tab with IP/MAC/DNS
   - SSH Sessions tab with `SSHSessionRow`
   - VPN/Tailscale tab with peer list
   - WiFi tab with signal bars, SNR, nearby networks
   - Listening Ports tab with enriched process names, exposure warning
   - Speed Test card with download/upload/RPM results
5. Wire sub-feature toggles to show/hide sub-panels

**Delegate to `tester` subagent:**

6. Test SSH argument parsing, Tailscale JSON decoding, WiFi snapshot, speed test output parsing

**Commit:** `git commit -m "feat: M8 — network intelligence, SSH, VPN/Tailscale, WiFi, listening ports, speed test"`

---

### M9: Power & Thermal (commit: "feat: M9 — per-component power, battery health, throttle detection")

**Delegate to `expanded-collectors` subagent:**

1. Implement `PowerThermalModule` registered with ModuleRegistry
2. Expand `IOKitWrapper.swift` with per-component power:
   - CPU package, E-core cluster, P-core cluster, GPU, ANE, DRAM watts
   - Total system power (sum)
   - Throttle detection (compare current vs max frequency)
   - CPU/GPU die temperature from IOReport/SMC
3. Battery details via IOKit `AppleSmartBattery`:
   - Charge level, charging state, charge rate, time remaining
   - Cycle count, battery health (MaxCapacity/DesignCapacity)
   - Temperature, optimized charging status
4. Subscribe: Critical (500ms) for power/thermal, Infrequent (60s) for battery health

**Delegate to `ui-builder` subagent:**

5. Build `PowerDetailView` with:
   - Total power sparkline (60s history)
   - Per-component breakdown (horizontal stacked bars)
   - Battery card (when applicable) with health/cycles/temperature
   - Thermal status with throttle indicator
6. Add power/thermal data to Overview panel (ThermalPill, power number)

**Delegate to `tester` subagent:**

7. Test IOReport wrapper mocks, battery parsing, throttle detection logic

**Commit:** `git commit -m "feat: M9 — power & thermal module, per-component breakdown, battery health, throttle detection"`

---

### M10: Bluetooth + Audio (commit: "feat: M10 — Bluetooth devices, audio routing, privacy indicators")

**Delegate to `expanded-collectors` subagent:**

1. Implement `BluetoothModule`:
   - `BluetoothCollector` via IOBluetooth framework
   - Device enumeration (connected + paired disconnected)
   - Battery level from IOKit `BatteryPercent`
   - Device classification (headphones, mouse, keyboard, trackpad, gamepad)
   - AirPods L/R/Case battery (Apple-specific IOKit keys)
   - RSSI for connected devices
2. Implement `AudioModule`:
   - `AudioCollector` via CoreAudio AudioObject APIs
   - Default input/output device name, sample rate, buffer size, bit depth
   - Volume level, mute state
   - Processes using microphone (coreaudiod client inspection)
   - Camera/mic privacy indicator correlation
3. Subscribe: Standard (1s) for audio/BT battery

**Delegate to `ui-builder` subagent:**

4. Build `BluetoothDetailView` with device cards (`BluetoothDeviceCard`)
5. Build `AudioDetailView` with input/output devices, privacy indicators
6. Add privacy indicator row to Overview (orange dot = mic, green dot = camera, show which process)

**Delegate to `tester` subagent:**

7. Test Bluetooth device classification, audio device parsing

**Commit:** `git commit -m "feat: M10 — Bluetooth module, audio routing, privacy indicators"`

---

### ⚡ COMPACT NOW

Run `/compact Focus on Phase E. Preserve: completed M1-M10, action-builder agent instructions, alert-builder agent instructions, Docker API patterns, network action list, all Settings panel structure.`

---

## PHASE E: Control Actions + Alert Engine (M11–M13)

### M11: Docker Actions (commit: "feat: M11 — Docker lifecycle, logs, exec-to-terminal")

**Delegate to `action-builder` subagent:**

1. Implement `DockerActionService`:
   - Stop/Start/Restart/Pause/Unpause via Docker Engine API (`POST /containers/{id}/...`)
   - Container logs (`GET /containers/{id}/logs?tail=100`) displayed in sheet
   - Exec shell → opens Terminal with `docker exec -it {id} sh`
   - Remove stopped container (`DELETE /containers/{id}`)
   - Pull latest image (`POST /images/create?fromImage={image}`)
   - Inspect container detail (`GET /containers/{id}/json`)
2. All actions gated behind `ActionConfiguration.dockerLifecycleEnabled` etc.
3. Confirmation dialogs for stop, restart, remove, pull
4. Audit trail entries for all Docker actions

**Delegate to `ui-builder` subagent:**

5. Add context menus to Docker container rows in Process Tree
6. Build container log viewer sheet
7. Build container inspect detail sheet

**Delegate to `tester` subagent:**

8. Test Docker API service with mock responses

**Commit:** `git commit -m "feat: M11 — Docker container lifecycle actions, logs, exec-to-terminal"`

---

### M12: Network + System Actions (commit: "feat: M12 — SSH-to-terminal, DNS flush, ping, system actions")

**Delegate to `action-builder` subagent:**

1. Network actions:
   - SSH to host → opens Terminal with `ssh user@host -p port`
   - DNS flush → `dscacheutil -flushcache` + `killall -HUP mDNSResponder` via helper
   - WiFi toggle → `CWInterface.setPower()`
   - Speed test on demand → `SpeedTestRunner.run()`
   - Ping host → background ICMP with results display
   - Traceroute → background `traceroute` with hop display
   - Kill connection → `shutdown(fd, SHUT_RDWR)` via helper
   - Copy Tailscale IP → pasteboard
2. System actions:
   - Purge memory → `sudo purge` via helper
   - Restart Finder → `killall Finder`
   - Restart Dock → `killall Dock`
   - Restart WindowServer → `killall -HUP WindowServer` via helper
   - Empty Trash → NSWorkspace
   - Sleep/Restart/Shutdown → AppleScript via System Events
3. All gated behind ActionConfiguration toggles
4. Confirmation for all destructive actions
5. Audit trail for everything

**Delegate to `ui-builder` subagent:**

6. Add context menus to SSH session rows, network connection rows
7. Add ping/traceroute result display views
8. Add system actions section to a "Quick Actions" panel or toolbar

**Delegate to `tester` subagent:**

9. Test network action configuration toggles, confirmation flows

**Commit:** `git commit -m "feat: M12 — network actions, system actions, SSH-to-terminal, DNS flush"`

---

### M13: Alert Engine (commit: "feat: M13 — threshold alerts, rule editor, notifications")

**Delegate to `alert-builder` subagent:**

1. Implement `AlertEngine`:
   - Evaluate rules each polling tick
   - Track sustained conditions (duration-based alerts)
   - Debounce: same alert max once per 60 seconds
   - Support conditions: cpuAbove, memoryPressure, diskFreeBelow, thermalState, processRSSAbove, volumeUnsafeDisconnect
2. Implement YAML alert configuration:
   - Load from `~/.processscope/alerts.yaml`
   - Fallback to built-in defaults
   - Save custom rules
3. Implement notification delivery:
   - `UNUserNotificationCenter` with permission request on first alert
   - Optional sound per rule
   - Dock badge count for unacknowledged alerts
4. Built-in default rules (5):
   - CPU >90% for 30s
   - Memory pressure critical
   - Disk <5% free
   - Thermal throttling critical
   - Process >50% CPU for 60s

**Delegate to `ui-builder` subagent:**

5. Wire Settings → Alerts tab:
   - Rule list with enable/disable toggles
   - Add/Edit/Delete rules
   - Alert delivery settings (notifications, sound, badge)
   - Alert history view with "View Log" button
6. Add badge count to dock icon

**Delegate to `tester` subagent:**

7. Test sustained condition tracking, debounce logic, rule evaluation
8. Test built-in rules produce correct alerts

**Commit:** `git commit -m "feat: M13 — alert engine, threshold rules, notification delivery"`

**Tag:** `git tag -a v0.3.0 -m "ProcessScope v0.3.0 — Full PRD + Amendment A coverage"`

---

## Constraints Throughout ALL Milestones

### Architecture
- Read CLAUDE.md before starting — it has build commands, code style, architecture rules
- Every collector MUST be protocol-wrapped with a mock
- Every C API call MUST check return values and handle errors gracefully
- ALL C interop code MUST live in Sources/Utilities/CInterop/
- NO private frameworks — IOReport wrapped in single swappable file
- Module Registry drives everything — sidebar, polling subscriptions, settings
- Disabled modules = zero overhead (verified by tests)

### Subagent Delegation
- `core-systems` for Sources/Core/, Sources/Utilities/, Helper/
- `ui-builder` for Sources/UI/, Sources/App/
- `expanded-collectors` for M7-M10 module collectors
- `action-builder` for M5, M11, M12 action layer
- `alert-builder` for M13 alert engine
- `tester` after each milestone

### Quality Gates
- SF Symbols only, system colors only, no hardcoded hex values
- Swift 6 strict concurrency — actors, @Sendable, @MainActor
- `xcodebuild test` before each commit
- Git commit after each milestone with specified message
- `/compact` between phases (after M3, M5, M6, M10)

### Context Management
- After each phase, compact with specific preservation instructions
- Post-compact hook will re-inject critical architecture context
- If context feels crowded mid-phase, delegate more aggressively to subagents
- Check `git log --oneline -5` after compaction to verify progress awareness

### PRD Reference
The full PRD is in `PRD.md`. Amendment A is in `PRD-AMENDMENT-A.md`. Key sections:
- §5: Architecture (runtime model, IPC, data collection layer, polling)
- §6: Feature spec (menu bar, dashboard, process explorer, enrichment rules)
- §7: Technical stack (project structure, build & distribution)
- §9: Performance budget (hard gates)
- A1: New dashboard modules (storage, network intelligence, BT, power, audio, display, security, developer, VM)
- A2: Action layer (process, storage, network, Docker, system, clipboard, alerts)
- A3: Modular settings architecture (module registry, drag-reorder, alert rules)
- A5: Revised polling tiers (5 tiers including new Infrequent/60s)
- A6: Revised performance budget (default vs all-modules targets)
