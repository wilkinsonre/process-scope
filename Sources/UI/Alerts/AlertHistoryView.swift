import SwiftUI

// MARK: - Alert History View

/// Standalone view for displaying alert history
///
/// Can be used both in the Settings sheet and as a standalone window/panel.
/// Shows a chronological list of fired alerts with severity indicators,
/// timestamps, and acknowledgment status.
struct AlertHistoryView: View {
    @EnvironmentObject var alertViewModel: AlertSettingsViewModel
    @State private var severityFilter: AlertSeverity?
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            // MARK: Toolbar
            HStack(spacing: 12) {
                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search alerts", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(6)
                .background(.background.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .frame(maxWidth: 200)

                // Severity filter
                Picker("Severity", selection: $severityFilter) {
                    Text("All").tag(nil as AlertSeverity?)
                    ForEach(AlertSeverity.allCases) { s in
                        Label(s.displayName, systemImage: s.symbolName).tag(s as AlertSeverity?)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 250)

                Spacer()

                // Stats
                Text("\(filteredEvents.count) alerts")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if alertViewModel.unacknowledgedCount > 0 {
                    Button("Acknowledge All") {
                        alertViewModel.acknowledgeAll()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // MARK: Content
            if filteredEvents.isEmpty {
                emptyState
            } else {
                List(filteredEvents) { event in
                    AlertHistoryEventRow(event: event)
                }
                .listStyle(.inset)
            }

            Divider()

            // MARK: Footer
            HStack {
                if !alertViewModel.alertHistory.isEmpty {
                    Button(role: .destructive) {
                        alertViewModel.clearHistory()
                    } label: {
                        Label("Clear All", systemImage: "trash")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }

                Spacer()

                if !alertViewModel.alertHistory.isEmpty {
                    Button {
                        exportHistory()
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Computed

    private var filteredEvents: [AlertEvent] {
        var events = alertViewModel.alertHistory

        if let filter = severityFilter {
            events = events.filter { $0.rule.severity == filter }
        }

        if !searchText.isEmpty {
            let search = searchText.lowercased()
            events = events.filter {
                $0.rule.name.lowercased().contains(search) ||
                $0.message.lowercased().contains(search)
            }
        }

        return events
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bell.slash")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No Alert History")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Alerts will appear here when rules are triggered.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Export

    private func exportHistory() {
        let lines = alertViewModel.alertHistory.map { event in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            let ts = formatter.string(from: event.timestamp)
            return "[\(ts)] [\(event.rule.severity.rawValue)] [\(event.rule.name)] \(event.message)"
        }
        let text = lines.joined(separator: "\n")

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "alert-history.log"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? text.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}

// MARK: - Alert History Event Row

/// A row in the alert history list
struct AlertHistoryEventRow: View {
    let event: AlertEvent

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .medium
        return f
    }()

    var body: some View {
        HStack(spacing: 10) {
            // Severity indicator
            Circle()
                .fill(severityColor)
                .frame(width: 8, height: 8)

            Image(systemName: event.rule.severity.symbolName)
                .foregroundStyle(severityColor)
                .frame(width: 20)

            // Content
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(event.rule.name)
                        .fontWeight(.medium)
                    if event.isAcknowledged {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption2)
                    }
                }
                Text(event.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            // Timestamp
            VStack(alignment: .trailing, spacing: 1) {
                Text(Self.timeFormatter.string(from: event.timestamp))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            // Metric value badge
            Text(formatValue(event.metricValue, metric: event.rule.metric))
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(severityColor.opacity(0.12))
                .foregroundStyle(severityColor)
                .clipShape(Capsule())
        }
        .padding(.vertical, 2)
    }

    private var severityColor: Color {
        switch event.rule.severity {
        case .info: .blue
        case .warning: .orange
        case .critical: .red
        }
    }

    private func formatValue(_ value: Double, metric: AlertMetric) -> String {
        if value == value.rounded() && value < 10000 {
            return String(format: "%.0f", value) + metric.unitSuffix
        }
        return String(format: "%.1f", value) + metric.unitSuffix
    }
}
