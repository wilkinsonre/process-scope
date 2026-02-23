import AppKit

// MARK: - Clipboard Service

/// Provides clipboard and Finder integration actions
///
/// This is a stateless utility with no side effects beyond the system
/// pasteboard. Clipboard copy is the only action category enabled by
/// default because it cannot cause data loss or system instability.
public enum ClipboardService {

    // MARK: - Copy to Clipboard

    /// Copies a string to the system clipboard
    /// - Parameter text: The text to place on the pasteboard
    @MainActor
    public static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Reveal in Finder

    /// Selects and reveals a file or directory in Finder
    /// - Parameter path: The absolute path to reveal
    @MainActor
    public static func revealInFinder(path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Convenience Formatters

    /// Formats a process for clipboard copy
    ///
    /// Produces a single-line summary including the display name, PID,
    /// executable path, and command-line arguments.
    /// - Parameters:
    ///   - name: Display name or enriched label
    ///   - pid: Process ID
    ///   - path: Executable path (optional)
    ///   - arguments: Command-line arguments (optional)
    /// - Returns: Formatted string suitable for pasting
    public static func formatProcess(
        name: String,
        pid: pid_t,
        path: String? = nil,
        arguments: [String] = []
    ) -> String {
        var parts: [String] = ["\(name) (PID \(pid))"]
        if let path { parts.append(path) }
        if !arguments.isEmpty {
            parts.append(arguments.joined(separator: " "))
        }
        return parts.joined(separator: " — ")
    }

    /// Formats a network connection for clipboard copy
    /// - Parameters:
    ///   - localAddress: Local address string
    ///   - localPort: Local port number
    ///   - remoteAddress: Remote address string
    ///   - remotePort: Remote port number
    ///   - protocolType: Protocol (tcp/udp)
    /// - Returns: Formatted string suitable for pasting
    public static func formatConnection(
        localAddress: String,
        localPort: UInt16,
        remoteAddress: String,
        remotePort: UInt16,
        protocolType: String
    ) -> String {
        "\(protocolType) \(localAddress):\(localPort) -> \(remoteAddress):\(remotePort)"
    }

    /// Formats a volume for clipboard copy
    /// - Parameters:
    ///   - name: Volume display name
    ///   - mountPoint: Mount point path
    ///   - capacity: Total capacity in bytes (optional)
    /// - Returns: Formatted string suitable for pasting
    public static func formatVolume(
        name: String,
        mountPoint: String,
        capacity: UInt64? = nil
    ) -> String {
        var result = "\(name) (\(mountPoint))"
        if let capacity {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            result += " — \(formatter.string(fromByteCount: Int64(capacity)))"
        }
        return result
    }
}
