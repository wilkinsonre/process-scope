import SwiftUI
import ServiceManagement
import os

/// Manages installation and status of the privileged helper daemon
@MainActor
public final class HelperInstaller: ObservableObject {
    private static let logger = Logger(subsystem: "com.processscope", category: "HelperInstaller")

    public enum Status: String {
        case installed = "Installed"
        case notInstalled = "Not Installed"
        case requiresApproval = "Requires Approval"
    }

    @Published public var status: Status = .notInstalled

    public init() {
        checkStatus()
    }

    public func checkStatus() {
        let service = SMAppService.daemon(plistName: "com.processscope.helper.plist")
        switch service.status {
        case .enabled:
            status = .installed
        case .requiresApproval:
            status = .requiresApproval
        case .notRegistered, .notFound:
            status = .notInstalled
        @unknown default:
            status = .notInstalled
        }
    }

    public func install() throws {
        let service = SMAppService.daemon(plistName: "com.processscope.helper.plist")
        try service.register()
        checkStatus()
        Self.logger.info("Helper daemon installed")
    }

    public func uninstall() throws {
        let service = SMAppService.daemon(plistName: "com.processscope.helper.plist")
        try service.unregister()
        checkStatus()
        Self.logger.info("Helper daemon uninstalled")
    }
}
