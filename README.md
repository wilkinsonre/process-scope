# ProcessScope — Claude Code Scaffold (Full Scope)

> Companion documentation package for building ProcessScope with Claude Code.
> Covers PRD v1.0 + Amendment A — 100% feature coverage across 13 milestones.

## What's Included

```
processscope-scaffold/
├── CLAUDE.md                          # Always-on project context (~100 lines)
├── ONESHOT_PROMPT.md                  # Master build prompt (M1–M13, 5 phases)
├── README.md                          # This file
└── .claude/
    ├── post-compact-context.md        # Re-injected after /compact via hook
    ├── settings.json                  # Permissions, hooks, notifications
    ├── agents/
    │   ├── core-systems.md            # M1–M3: XPC, collectors, enrichment
    │   ├── ui-builder.md              # All milestones: SwiftUI views, 12 modules
    │   ├── expanded-collectors.md     # M7–M10: storage, network, BT, audio, power
    │   ├── action-builder.md          # M5, M11, M12: action layer, Docker, network
    │   ├── alert-builder.md           # M13: threshold engine, notifications
    │   └── tester.md                  # All milestones: tests, verification
    ├── rules/
    │   ├── swift-style.md             # Path-scoped: Sources/**/*.swift
    │   ├── c-interop.md               # Path-scoped: CInterop/**/*.swift
    │   └── action-safety.md           # Path-scoped: Sources/Actions/**/*.swift
    └── skills/
        ├── iokit-interop/SKILL.md     # C interop: libproc, sysctl, IOKit, IOReport
        ├── xpc-helper/SKILL.md        # XPC protocol, SMAppService, helper daemon
        ├── process-enrichment/SKILL.md # Enrichment engine, rules, tree building
        ├── swift-macos/SKILL.md       # Swift 6 concurrency, Xcode targets, Charts
        ├── swiftui-dashboard/SKILL.md # All 12 modules, action UI, settings tabs
        ├── storage-network/SKILL.md   # DiskArbitration, SSH, Tailscale, WiFi, speed
        ├── peripheral-systems/SKILL.md # Bluetooth, Audio, Display, Security, DevMetrics
        ├── action-layer/SKILL.md      # Signals, Docker API, eject, audit trail
        └── modular-settings/SKILL.md  # ModuleRegistry, alert engine, notifications
```

## File Counts

| Category | Files | Purpose |
|----------|-------|---------|
| CLAUDE.md | 1 | Always-on context (~102 lines, ~1,500 tokens) |
| Skills | 9 | On-demand domain knowledge |
| Subagents | 6 | Isolated execution contexts |
| Rules | 3 | Path-scoped code style enforcement |
| Settings | 1 | Permissions + hooks |
| Support | 3 | Post-compact context, README, oneshot prompt |
| **Total** | **23** | |

## How to Use

### 1. Place files in your project root
```bash
tar xzf processscope-scaffold.tar.gz -C /path/to/ProcessScope/
```

### 2. Add PRD documents
Place `PRD.md` (base PRD v1.0) and `PRD-AMENDMENT-A.md` in the project root.

### 3. Open Claude Code and paste the oneshot prompt
```bash
cd /path/to/ProcessScope
claude
```
Then paste the contents of `ONESHOT_PROMPT.md`.

### 4. Context management during build
The prompt is organized into 5 phases with `/compact` between each:
- **Phase A** (M1–M3): Foundation + Core Intelligence
- **Phase B** (M4–M5): Full Dashboard + Action Layer v1
- **Phase C** (M6): Polish + Release Prep → **v0.1.0 tag**
- **Phase D** (M7–M10): Expanded Observation Modules
- **Phase E** (M11–M13): Control Actions + Alert Engine → **v0.3.0 tag**

The `PostCompact` hook in settings.json automatically re-injects critical architecture context after each compaction.

## Architecture Overview

### Token Budget
| Component | Est. Tokens | Loaded |
|-----------|-------------|--------|
| CLAUDE.md | ~1,500 | Every session |
| Post-compact context | ~600 | After compaction |
| Each skill (avg) | ~2,000 | On demand |
| Each subagent | ~500 | When delegated to |
| Each rule | ~200 | When editing matching paths |

### Subagent Delegation Map
| Subagent | Milestones | Domain |
|----------|-----------|--------|
| core-systems | M1, M2, M3 | XPC, collectors, CInterop, enrichment |
| ui-builder | M1–M13 (UI parts) | SwiftUI, settings, action UI |
| expanded-collectors | M7, M8, M9, M10 | New module collectors |
| action-builder | M5, M11, M12 | Process/Docker/network/system actions |
| alert-builder | M13 | Alert engine, notifications |
| tester | M1–M13 (after each) | Tests, verification |

### Skill Loading Map
| Skill | Used By | Key Content |
|-------|---------|-------------|
| iokit-interop | core-systems, expanded-collectors | libproc, sysctl, IOKit code patterns |
| xpc-helper | core-systems, action-builder | XPC protocol, SMAppService, helper |
| process-enrichment | core-systems | Rule engine, templates, tree building |
| swift-macos | ui-builder | Swift 6 patterns, Xcode targets |
| swiftui-dashboard | ui-builder | 12 module views, settings, actions UI |
| storage-network | expanded-collectors | DiskArbitration, SSH, Tailscale, WiFi |
| peripheral-systems | expanded-collectors | Bluetooth, Audio, Display, Security |
| action-layer | action-builder | Signals, Docker API, audit trail |
| modular-settings | alert-builder | ModuleRegistry, alert engine, UNNotification |

## Changes from v1 Scaffold

| Aspect | v1 (Base PRD) | v2 (Full Scope) |
|--------|---------------|-----------------|
| Milestones | M1–M4 (M5–M6 deferred) | M1–M13 (100% coverage) |
| Skills | 5 | 9 (+storage-network, peripheral-systems, action-layer, modular-settings) |
| Subagents | 3 | 6 (+expanded-collectors, action-builder, alert-builder) |
| Rules | 2 | 3 (+action-safety) |
| CLAUDE.md | ~90 lines | ~102 lines (added module list, action rules, polling tier 5) |
| Polling tiers | 4 | 5 (added Infrequent/60s) |
| Performance budget | Single target | Dual target (default modules vs all modules) |
| Phases | 1 phase | 5 phases with compaction strategy |
| Settings | 4 tabs | 7 tabs (added Modules, Actions, Alerts) |
| Sidebar | Hardcoded enum | Dynamic ModuleRegistry-driven |
