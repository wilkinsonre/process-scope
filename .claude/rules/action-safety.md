---
paths:
  - "Sources/Actions/**/*.swift"
  - "Sources/Core/XPC/**/*.swift"
---

# Action Safety Rules

- EVERY destructive action (kill, force eject, remove container, purge, restart service) MUST show a ConfirmationDialog before executing
- EVERY action MUST be logged to AuditTrail with timestamp, target, and outcome
- EVERY action category MUST check its ActionConfiguration toggle before executing — disabled actions are no-ops
- Actions requiring root MUST route through the XPC helper protocol — never shell out with sudo
- If helper is not installed, show "Install helper to enable" in the UI — never error silently
- Use `kill(pid, signal)` for own-user processes, `helperConnection.killProcess(pid:signal:)` for others
- Docker actions use the Docker Engine API over Unix socket — never shell out to `docker` CLI
- Keyboard shortcuts use NSEvent.addLocalMonitorForEvents — not SwiftUI .keyboardShortcut (limited support for modifier combos)
- Clipboard copy MUST use NSPasteboard.general — set both .string and .utf8PlainText types
- PendingAction confirmation dialog MUST list affected items (child processes, open file handles, etc.)
