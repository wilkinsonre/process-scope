import SwiftUI

// MARK: - Alert Settings View

/// Settings tab for managing alert rules
///
/// Displays all configured alert rules with enable/disable toggles,
/// provides add/edit/delete functionality, and offers reset-to-defaults
/// and test notification capabilities.
struct AlertSettingsView: View {
    @EnvironmentObject var alertViewModel: AlertSettingsViewModel

    @State private var showingAddSheet = false
    @State private var showingEditSheet = false
    @State private var editingRule: AlertRule?
    @State private var showingResetConfirmation = false
    @State private var showingHistory = false
    @State private var showingImportExport = false

    var body: some View {
        Form {
            // MARK: Rules List
            Section("Alert Rules") {
                if alertViewModel.rules.isEmpty {
                    Text("No alert rules configured.")
                        .foregroundStyle(.secondary)
                        .italic()
                } else {
                    ForEach(alertViewModel.rules) { rule in
                        AlertRuleRow(
                            rule: rule,
                            onToggle: { enabled in
                                alertViewModel.toggleRule(id: rule.id, enabled: enabled)
                            },
                            onEdit: {
                                editingRule = rule
                                showingEditSheet = true
                            },
                            onDelete: {
                                alertViewModel.deleteRule(id: rule.id)
                            }
                        )
                    }
                }
            }

            // MARK: Actions
            Section {
                HStack {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Label("Add Rule", systemImage: "plus.circle")
                    }

                    Spacer()

                    Button {
                        alertViewModel.sendTestNotification()
                    } label: {
                        Label("Test Alert", systemImage: "bell.badge")
                    }
                }

                HStack {
                    Button {
                        showingHistory = true
                    } label: {
                        Label("Alert History", systemImage: "clock.arrow.circlepath")
                    }

                    Spacer()

                    Button(role: .destructive) {
                        showingResetConfirmation = true
                    } label: {
                        Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                    }
                }
            }

            // MARK: Badge Info
            Section {
                HStack {
                    Image(systemName: "app.badge")
                        .foregroundStyle(.secondary)
                    Text("Unacknowledged alerts: \(alertViewModel.unacknowledgedCount)")
                    Spacer()
                    if alertViewModel.unacknowledgedCount > 0 {
                        Button("Clear Badge") {
                            alertViewModel.acknowledgeAll()
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            // MARK: Footer
            HStack {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text("Alerts are evaluated on each polling tick. Duration-based rules require the condition to persist continuously.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .sheet(isPresented: $showingAddSheet) {
            AlertRuleEditorSheet(mode: .add) { rule in
                alertViewModel.addRule(rule)
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            if let rule = editingRule {
                AlertRuleEditorSheet(mode: .edit(rule)) { updatedRule in
                    alertViewModel.updateRule(updatedRule)
                }
            }
        }
        .sheet(isPresented: $showingHistory) {
            AlertHistorySheet(viewModel: alertViewModel)
        }
        .confirmationDialog(
            "Reset Alert Rules?",
            isPresented: $showingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset to Defaults", role: .destructive) {
                alertViewModel.resetToDefaults()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will replace all custom rules with the built-in defaults.")
        }
        .onAppear {
            alertViewModel.refresh()
        }
    }
}

// MARK: - Alert Rule Row

/// A single row in the rules list showing the rule name, condition, and toggle
struct AlertRuleRow: View {
    let rule: AlertRule
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Severity icon
            Image(systemName: rule.severity.symbolName)
                .foregroundStyle(severityColor)
                .font(.body)
                .frame(width: 20)

            // Rule info
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name)
                    .fontWeight(.medium)
                Text(rule.conditionDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if rule.duration > 0 {
                    Text("Sustained for \(Int(rule.duration))s")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Sound indicator
            if rule.soundEnabled {
                Image(systemName: "speaker.wave.2")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Enable toggle
            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { onToggle($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button {
                onEdit()
            } label: {
                Label("Edit Rule", systemImage: "pencil")
            }

            Divider()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete Rule", systemImage: "trash")
            }
        }
    }

    private var severityColor: Color {
        switch rule.severity {
        case .info: .blue
        case .warning: .orange
        case .critical: .red
        }
    }
}

// MARK: - Alert Rule Editor Sheet

/// Sheet for adding or editing an alert rule
struct AlertRuleEditorSheet: View {
    enum Mode {
        case add
        case edit(AlertRule)
    }

    let mode: Mode
    let onSave: (AlertRule) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var metric: AlertMetric = .cpuUsage
    @State private var condition: AlertCondition = .greaterThan
    @State private var threshold: Double = 90
    @State private var duration: Double = 0
    @State private var cooldown: Double = 60
    @State private var severity: AlertSeverity = .warning
    @State private var soundEnabled: Bool = false
    @State private var message: String = ""

    private var existingID: UUID?

    init(mode: Mode, onSave: @escaping (AlertRule) -> Void) {
        self.mode = mode
        self.onSave = onSave

        switch mode {
        case .add:
            existingID = nil
        case .edit(let rule):
            existingID = rule.id
            _name = State(initialValue: rule.name)
            _metric = State(initialValue: rule.metric)
            _condition = State(initialValue: rule.condition)
            _threshold = State(initialValue: rule.threshold)
            _duration = State(initialValue: rule.duration)
            _cooldown = State(initialValue: rule.cooldown)
            _severity = State(initialValue: rule.severity)
            _soundEnabled = State(initialValue: rule.soundEnabled)
            _message = State(initialValue: rule.message ?? "")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isEditing ? "Edit Alert Rule" : "New Alert Rule")
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            // Form
            Form {
                Section("Rule") {
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                Section("Condition") {
                    Picker("Metric", selection: $metric) {
                        ForEach(AlertMetric.allCases) { m in
                            Label(m.displayName, systemImage: m.symbolName)
                                .tag(m)
                        }
                    }

                    Picker("Condition", selection: $condition) {
                        ForEach(AlertCondition.allCases) { c in
                            Text(c.displayName).tag(c)
                        }
                    }

                    HStack {
                        Text("Threshold:")
                        TextField("Value", value: $threshold, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                        Text(metric.unitSuffix)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Timing") {
                    HStack {
                        Text("Duration:")
                        TextField("Seconds", value: $duration, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Text("seconds")
                            .foregroundStyle(.secondary)
                    }
                    Text("How long the condition must persist before firing. Set to 0 for immediate.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    HStack {
                        Text("Cooldown:")
                        TextField("Seconds", value: $cooldown, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Text("seconds")
                            .foregroundStyle(.secondary)
                    }
                    Text("Minimum time between repeated alerts for this rule.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Section("Presentation") {
                    Picker("Severity", selection: $severity) {
                        ForEach(AlertSeverity.allCases) { s in
                            Label(s.displayName, systemImage: s.symbolName)
                                .tag(s)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle("Play Sound", isOn: $soundEnabled)

                    TextField("Custom Message (optional)", text: $message)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .formStyle(.grouped)

            Divider()

            // Buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(isEditing ? "Save" : "Add Rule") {
                    let rule = AlertRule(
                        id: existingID ?? UUID(),
                        name: name,
                        metric: metric,
                        condition: condition,
                        threshold: threshold,
                        duration: duration,
                        cooldown: cooldown,
                        isEnabled: true,
                        severity: severity,
                        soundEnabled: soundEnabled,
                        message: message.isEmpty ? nil : message
                    )
                    onSave(rule)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty)
            }
            .padding()
        }
        .frame(width: 480, height: 580)
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }
}

// MARK: - Alert History Sheet

/// Sheet displaying the alert history with filtering and clear functionality
struct AlertHistorySheet: View {
    @ObservedObject var viewModel: AlertSettingsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var severityFilter: AlertSeverity?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Alert History")
                    .font(.headline)
                Spacer()

                // Severity filter
                Picker("Filter", selection: $severityFilter) {
                    Text("All").tag(nil as AlertSeverity?)
                    ForEach(AlertSeverity.allCases) { s in
                        Label(s.displayName, systemImage: s.symbolName).tag(s as AlertSeverity?)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 250)
            }
            .padding()

            Divider()

            // History list
            if filteredHistory.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bell.slash")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No alerts in history")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredHistory) { event in
                    AlertHistoryRow(event: event)
                }
            }

            Divider()

            // Footer
            HStack {
                if !viewModel.alertHistory.isEmpty {
                    Button(role: .destructive) {
                        viewModel.clearHistory()
                    } label: {
                        Label("Clear History", systemImage: "trash")
                    }
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .frame(minWidth: 600, minHeight: 400)
    }

    private var filteredHistory: [AlertEvent] {
        if let filter = severityFilter {
            return viewModel.alertHistory.filter { $0.rule.severity == filter }
        }
        return viewModel.alertHistory
    }
}

// MARK: - Alert History Row

/// A single row in the alert history list
struct AlertHistoryRow: View {
    let event: AlertEvent

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: event.rule.severity.symbolName)
                .foregroundStyle(severityColor)
                .font(.body)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.rule.name)
                    .fontWeight(.medium)
                Text(event.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(event.timestamp, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(event.timestamp, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if event.isAcknowledged {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
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
}
