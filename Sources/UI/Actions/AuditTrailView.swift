import SwiftUI
import AppKit

// MARK: - AuditTrailView

/// Shows the audit trail of executed actions.
///
/// Displays a searchable, sortable table of every action that has been confirmed
/// (or cancelled) through the action layer. Each entry records the action type,
/// target, result, timestamp, and whether confirmation was obtained.
@MainActor
struct AuditTrailView: View {
    /// The list of audit entries loaded from the ``AuditTrail`` actor.
    @State private var entries: [AuditEntry] = []
    /// Current search text for filtering entries.
    @State private var searchText = ""
    /// Whether the view is currently loading entries.
    @State private var isLoading = false
    /// Sort order for the table.
    @State private var sortOrder = [KeyPathComparator(\AuditEntry.timestamp, order: .reverse)]

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header

            headerBar

            Divider()

            // MARK: - Table

            if isLoading {
                ProgressView("Loading audit trail\u{2026}")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredEntries.isEmpty {
                emptyState
            } else {
                auditTable
            }

            Divider()

            // MARK: - Footer

            footerBar
        }
        .frame(minWidth: 650, minHeight: 400)
        .task {
            await loadEntries()
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(.secondary)
            Text("Action Audit Trail")
                .font(.headline)

            Spacer()

            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter\u{2026}", text: $searchText)
                    .textFieldStyle(.plain)
                    .frame(width: 180)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    // MARK: - Audit Table

    private var auditTable: some View {
        Table(filteredEntries, sortOrder: $sortOrder) {
            TableColumn("Timestamp", value: \.timestamp) { entry in
                Text(entry.timestamp.formatted(date: .abbreviated, time: .standard))
                    .font(.caption.monospacedDigit())
                    .help(entry.timestamp.formatted(.iso8601))
                    .contextMenu {
                        Button("Copy Timestamp") {
                            copyToPasteboard(entry.timestamp.formatted(.iso8601))
                        }
                    }
            }
            .width(min: 140, ideal: 160)

            TableColumn("Action") { entry in
                Label(entry.actionType.displayName, systemImage: entry.actionType.symbolName)
                    .font(.caption)
                    .contextMenu {
                        Button("Copy Action") {
                            copyToPasteboard(entry.actionType.displayName)
                        }
                    }
            }
            .width(min: 100, ideal: 120)

            TableColumn("Target") { entry in
                Text(entry.targetDescription)
                    .font(.caption)
                    .lineLimit(1)
                    .help(entry.targetDescription)
                    .contextMenu {
                        Button("Copy Target") {
                            copyToPasteboard(entry.targetDescription)
                        }
                    }
            }
            .width(min: 120, ideal: 180)

            TableColumn("Result") { entry in
                resultBadge(for: entry.result)
                    .contextMenu {
                        Button("Copy Result") {
                            copyToPasteboard(entry.result.displayName)
                        }
                    }
            }
            .width(min: 80, ideal: 90)

            TableColumn("Confirmed") { entry in
                Image(systemName: entry.wasConfirmed ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(entry.wasConfirmed ? .green : .secondary)
                    .accessibilityLabel(entry.wasConfirmed ? "Confirmed" : "Not confirmed")
            }
            .width(min: 70, ideal: 80)
        }
        .onChange(of: sortOrder) { _, newOrder in
            entries.sort(using: newOrder)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("No Actions Recorded")
                .font(.headline)
                .foregroundStyle(.secondary)
            if searchText.isEmpty {
                Text("Actions will appear here after they are executed.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Text("No entries match the current filter.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer Bar

    private var footerBar: some View {
        HStack {
            Text("\(filteredEntries.count) entries")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                revealLogFile()
            } label: {
                Label("Open Log File", systemImage: "doc.text")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Open audit log file in Finder")

            Button(role: .destructive) {
                Task { await clearLog() }
            } label: {
                Label("Clear Log", systemImage: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Clear all audit log entries")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }

    // MARK: - Result Badge

    private func resultBadge(for result: ActionResult) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(resultColor(for: result))
                .frame(width: 8, height: 8)
            Text(result.displayName)
                .font(.caption)
        }
    }

    private func resultColor(for result: ActionResult) -> Color {
        switch result {
        case .success:
            return .green
        case .failure:
            return .red
        case .cancelled:
            return .secondary
        }
    }

    // MARK: - Filtering

    private var filteredEntries: [AuditEntry] {
        guard !searchText.isEmpty else { return entries }
        let query = searchText.lowercased()
        return entries.filter { entry in
            entry.actionType.displayName.lowercased().contains(query) ||
            entry.targetDescription.lowercased().contains(query) ||
            entry.result.displayName.lowercased().contains(query)
        }
    }

    // MARK: - Data Loading

    private func loadEntries() async {
        isLoading = true
        entries = await AuditTrail.shared.allEntries()
        entries.sort(using: sortOrder)
        isLoading = false
    }

    private func clearLog() async {
        await AuditTrail.shared.clearAll()
        entries = []
    }

    // MARK: - Helpers

    private func revealLogFile() {
        let logPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".processscope")
            .appendingPathComponent("actions.log")
        if FileManager.default.fileExists(atPath: logPath.path) {
            NSWorkspace.shared.activateFileViewerSelecting([logPath])
        } else {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath:
                logPath.deletingLastPathComponent().path)
        }
    }

    private func copyToPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
