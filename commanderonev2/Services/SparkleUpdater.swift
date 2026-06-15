import Foundation
import Combine
import SwiftUI

#if canImport(Sparkle)
import Sparkle

/// Lightweight wrapper around Sparkle's `SPUStandardUpdaterController` so the
/// SwiftUI view tree can drive "Check for Updates…" through a normal observable
/// object. Wrapped in `#if canImport(Sparkle)` so the project still compiles
/// before the SwiftPM dependency is added.
///
/// SUFeedURL and SUPublicEDKey live in Info.plist. Until Phase 4 wires them up
/// (GitHub Releases + EdDSA keys), `canCheckForUpdates` returns false and the
/// menu item stays disabled — no crashes, no surprise prompts.
@MainActor
final class SparkleUpdater: NSObject, ObservableObject {

    @Published private(set) var canCheckForUpdates = false

    private let updaterController: SPUStandardUpdaterController

    override init() {
        // Beta IS the publisher — it must never start the updater, otherwise
        // it would try to update itself with its own release.
        let shouldStart = !AppPaths.isBeta
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: shouldStart,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
        if shouldStart {
            updaterController.updater.publisher(for: \.canCheckForUpdates)
                .receive(on: RunLoop.main)
                .assign(to: &$canCheckForUpdates)
        }
    }

    /// Shows Sparkle's standard "checking…" UI; if an update is available the user
    /// sees Sparkle's update window and can choose Install Now / Remind Me Later.
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
#endif
