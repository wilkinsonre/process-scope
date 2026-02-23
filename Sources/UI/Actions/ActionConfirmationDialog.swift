import SwiftUI

// MARK: - ActionConfirmationDialog

/// Confirmation dialog shown before executing any destructive action.
///
/// Displays a warning icon, message text, and confirm/cancel buttons.
/// Destructive actions render the confirm button in red. All actions
/// in ProcessScope must pass through this dialog before execution.
@MainActor
struct ActionConfirmationDialog: View {
    /// Title displayed at the top of the dialog (e.g. "Kill Process").
    let title: String
    /// Descriptive message explaining the action (e.g. "Are you sure you want to kill 'Safari' (PID 1234)?").
    let message: String
    /// Label for the confirm button (e.g. "Kill").
    let actionLabel: String
    /// Whether this action is destructive. When true, the icon and confirm button use `.red`.
    let isDestructive: Bool
    /// Called when the user confirms the action.
    let onConfirm: () -> Void
    /// Called when the user cancels the action.
    let onCancel: () -> Void

    /// Optional list of affected items shown in a grouped box.
    var affectedItems: [String] = []

    var body: some View {
        VStack(spacing: 16) {
            // Warning icon
            Image(systemName: isDestructive ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(isDestructive ? .red : .blue)
                .accessibilityLabel(isDestructive ? "Warning" : "Information")

            // Title
            Text(title)
                .font(.headline)

            // Message
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // Affected items list
            if !affectedItems.isEmpty {
                GroupBox {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(affectedItems.enumerated()), id: \.offset) { _, item in
                            HStack(spacing: 4) {
                                Text("\u{2022}")
                                    .foregroundStyle(.secondary)
                                Text(item)
                                    .font(.caption)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Text("Affected")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Buttons
            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Cancel action")

                Button(actionLabel, role: isDestructive ? .destructive : nil) {
                    onConfirm()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel("Confirm \(actionLabel)")
            }
        }
        .padding(24)
        .frame(width: 350)
    }
}

// MARK: - Convenience Initializer for PendingAction

extension ActionConfirmationDialog {
    /// Creates a confirmation dialog from a ``PendingAction``.
    ///
    /// - Parameters:
    ///   - action: The pending action to confirm.
    ///   - onConfirm: Closure invoked when the user confirms.
    ///   - onCancel: Closure invoked when the user cancels.
    init(action: PendingAction, onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.title = action.title
        self.message = action.detail
        self.actionLabel = action.confirmLabel
        self.isDestructive = action.isDestructive
        self.affectedItems = action.affectedItems
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }
}

// MARK: - View Modifier

/// A view modifier that presents an ``ActionConfirmationDialog`` as a sheet.
///
/// Attach this to any view that may trigger a destructive action. The dialog
/// is displayed when `pendingAction` is non-nil and dismissed on confirm or cancel.
struct ActionConfirmationModifier: ViewModifier {
    @Binding var pendingAction: PendingAction?
    let onConfirm: (PendingAction) -> Void

    func body(content: Content) -> some View {
        content
            .sheet(item: $pendingAction) { action in
                ActionConfirmationDialog(
                    action: action,
                    onConfirm: {
                        onConfirm(action)
                        pendingAction = nil
                    },
                    onCancel: {
                        pendingAction = nil
                    }
                )
            }
    }
}

// MARK: - View Extension

extension View {
    /// Presents a confirmation dialog for a pending action.
    ///
    /// - Parameters:
    ///   - pendingAction: Binding to the action awaiting confirmation. Set to `nil` to dismiss.
    ///   - onConfirm: Called with the confirmed action when the user proceeds.
    func actionConfirmation(
        _ pendingAction: Binding<PendingAction?>,
        onConfirm: @escaping (PendingAction) -> Void
    ) -> some View {
        modifier(ActionConfirmationModifier(pendingAction: pendingAction, onConfirm: onConfirm))
    }
}
