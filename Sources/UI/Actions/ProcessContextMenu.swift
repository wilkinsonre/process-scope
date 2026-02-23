import SwiftUI
import AppKit

// MARK: - ProcessContextMenu

/// Context menu for process rows in the tree/list.
///
/// Provides clipboard copy actions, Finder reveal, process control (kill, suspend,
/// resume), and inspector access. Destructive actions are gated by ``ActionConfiguration``
/// and require confirmation through ``ActionConfirmationDialog``.
struct ProcessContextMenu: ViewModifier {
    /// The process record to act on.
    let process: ProcessRecord
    /// The tree node for this process (provides hierarchy context).
    let node: ProcessTreeNode

    @EnvironmentObject private var actionVM: ActionViewModel

    func body(content: Content) -> some View {
        content.contextMenu {
            // MARK: - Process Control

            processControlSection

            Divider()

            // MARK: - Clipboard

            clipboardSection

            Divider()

            // MARK: - Navigation

            navigationSection
        }
    }

    // MARK: - Process Control Section

    @ViewBuilder
    private var processControlSection: some View {
        if actionVM.configuration.processKillEnabled {
            Button {
                actionVM.requestKill(process: process, force: false)
            } label: {
                Label("Kill Process", systemImage: "xmark.circle")
            }
            .accessibilityLabel("Kill process \(process.name)")

            Button {
                actionVM.requestKill(process: process, force: true)
            } label: {
                Label("Force Kill", systemImage: "xmark.circle.fill")
            }
            .accessibilityLabel("Force kill process \(process.name)")
        }

        if actionVM.configuration.processSuspendEnabled {
            if process.status == .stopped {
                Button {
                    actionVM.requestResume(process: process)
                } label: {
                    Label("Resume", systemImage: "play.circle")
                }
                .accessibilityLabel("Resume process \(process.name)")
            } else {
                Button {
                    actionVM.requestSuspend(process: process)
                } label: {
                    Label("Suspend", systemImage: "pause.circle")
                }
                .accessibilityLabel("Suspend process \(process.name)")
            }
        }
    }

    // MARK: - Clipboard Section

    @ViewBuilder
    private var clipboardSection: some View {
        Button {
            copyToPasteboard("\(process.pid)")
        } label: {
            Label("Copy PID", systemImage: "doc.on.doc")
        }
        .accessibilityLabel("Copy process ID")

        Button {
            copyToPasteboard(process.name)
        } label: {
            Label("Copy Process Name", systemImage: "doc.on.doc")
        }
        .accessibilityLabel("Copy process name")

        if let path = process.executablePath {
            Button {
                copyToPasteboard(path)
            } label: {
                Label("Copy Full Path", systemImage: "doc.on.doc")
            }
            .accessibilityLabel("Copy executable path")
        }

        if !process.arguments.isEmpty {
            Button {
                let commandLine = process.arguments.joined(separator: " ")
                copyToPasteboard(commandLine)
            } label: {
                Label("Copy Command Line", systemImage: "doc.on.doc")
            }
            .accessibilityLabel("Copy full command line")
        }
    }

    // MARK: - Navigation Section

    @ViewBuilder
    private var navigationSection: some View {
        if let path = process.executablePath {
            Button {
                let url = URL(fileURLWithPath: path)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }
            .accessibilityLabel("Reveal executable in Finder")
        }

        Divider()

        Button {
            actionVM.requestInspect(process: process)
        } label: {
            Label("Inspect\u{2026}", systemImage: "info.circle")
        }
        .accessibilityLabel("Inspect process \(process.name)")
    }

    // MARK: - Helpers

    private func copyToPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

// MARK: - View Extension

extension View {
    /// Adds a process context menu to this view.
    ///
    /// - Parameters:
    ///   - process: The process record associated with this view.
    ///   - node: The tree node for this process.
    func processContextMenu(process: ProcessRecord, node: ProcessTreeNode) -> some View {
        modifier(ProcessContextMenu(process: process, node: node))
    }
}
