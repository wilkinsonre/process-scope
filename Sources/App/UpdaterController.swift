import SwiftUI
import Sparkle

/// Wraps Sparkle's `SPUStandardUpdaterController` for SwiftUI integration.
///
/// Provides a `checkForUpdates()` method and a `canCheckForUpdates`
/// published property that tracks whether an update check is possible.
@MainActor
final class UpdaterController: ObservableObject {
    private let controller: SPUStandardUpdaterController

    @Published var canCheckForUpdates = false

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        // Observe the updater's canCheckForUpdates property via KVO
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    /// Triggers a user-initiated update check via Sparkle.
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
