import SwiftUI
import AppKit
import os

// MARK: - KeyboardShortcutManager

/// Manages local keyboard shortcuts for common actions in the process explorer.
///
/// Registers event monitors for key combinations like Cmd+Delete (kill process),
/// Cmd+Shift+Delete (force kill), Cmd+C (copy process info), and Cmd+I (inspect).
/// Monitors are installed when the process explorer is visible and removed when hidden.
@MainActor
final class KeyboardShortcutManager: ObservableObject {
    private static let logger = Logger(subsystem: "com.processscope", category: "KeyboardShortcutManager")

    /// The currently selected process PID, if any.
    @Published var selectedPID: pid_t?

    /// Reference to the local event monitor. Stored to allow removal on deactivation.
    private var eventMonitor: Any?

    /// Callback invoked when the user presses Cmd+Delete on a selected process.
    var onKillRequested: ((pid_t) -> Void)?

    /// Callback invoked when the user presses Cmd+Shift+Delete on a selected process.
    var onForceKillRequested: ((pid_t) -> Void)?

    /// Callback invoked when the user presses Cmd+C on a selected process.
    var onCopyRequested: ((pid_t) -> Void)?

    /// Callback invoked when the user presses Cmd+I on a selected process.
    var onInspectRequested: ((pid_t) -> Void)?

    // MARK: - Lifecycle

    /// Installs the local key event monitor.
    ///
    /// Call this when the process explorer view appears. The monitor only handles
    /// events while the app window is key. Local monitors run on the main thread,
    /// which matches our `@MainActor` isolation.
    func activate() {
        guard eventMonitor == nil else { return }

        // Local event monitors always dispatch on the main thread, so accessing
        // @MainActor state from the closure is safe via MainActor.assumeIsolated.
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Local monitors always run on the main thread. We extract the
            // key properties before crossing isolation boundaries to avoid
            // the NSEvent non-Sendable constraint in Swift 6.
            let keyCode = event.keyCode
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let handled = MainActor.assumeIsolated {
                guard let self, let pid = self.selectedPID else { return false }
                return self.handleKeyCode(keyCode, flags: flags, pid: pid)
            }
            return handled ? nil : event
        }

        Self.logger.debug("Keyboard shortcut monitor activated")
    }

    /// Removes the local key event monitor.
    ///
    /// Call this when the process explorer view disappears. Must be called before
    /// the manager is deallocated to ensure proper cleanup.
    func deactivate() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        Self.logger.debug("Keyboard shortcut monitor deactivated")
    }

    // MARK: - Event Handling

    /// Processes extracted key event data and dispatches to the appropriate callback.
    ///
    /// Uses scalar values (keyCode, flags) rather than NSEvent directly to avoid
    /// Swift 6 Sendable constraints on NSEvent within MainActor.assumeIsolated.
    ///
    /// - Parameters:
    ///   - keyCode: The virtual key code from the event.
    ///   - flags: The device-independent modifier flags.
    ///   - pid: The currently selected process PID.
    /// - Returns: `true` if the key combination was handled, `false` to pass through.
    private func handleKeyCode(_ keyCode: UInt16, flags: NSEvent.ModifierFlags, pid: pid_t) -> Bool {
        switch (keyCode, flags) {
        // Cmd+Delete: Kill process
        case (51, [.command]):
            onKillRequested?(pid)
            return true

        // Cmd+Shift+Delete: Force kill process
        case (51, [.command, .shift]):
            onForceKillRequested?(pid)
            return true

        // Cmd+C: Copy process info (only when not in a text field)
        case (8, [.command]):
            if NSApp.keyWindow?.firstResponder is NSTextView {
                return false
            }
            onCopyRequested?(pid)
            return true

        // Cmd+I: Inspect process
        case (34, [.command]):
            onInspectRequested?(pid)
            return true

        default:
            return false
        }
    }
}

// MARK: - KeyboardShortcutLabel

/// A view that displays a keyboard shortcut hint label.
///
/// Used in context menus and tooltips to show the key combination for an action.
struct KeyboardShortcutLabel: View {
    /// The human-readable shortcut text (e.g. "Cmd+Delete").
    let shortcut: String
    /// Description of the action.
    let action: String

    var body: some View {
        HStack {
            Text(action)
            Spacer()
            Text(shortcut)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
        }
    }
}
