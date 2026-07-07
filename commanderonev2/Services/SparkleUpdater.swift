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
private final class SparkleDelegate: NSObject, SPUUpdaterDelegate {
    var onUpdateFound: (() -> Void)?
    var onNoUpdate: (() -> Void)?
    var onUpdateInstalled: (() -> Void)?

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        onUpdateFound?()
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        onNoUpdate?()
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        // Don't clear the badge on network errors — update may still be available
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        onUpdateInstalled?()
    }
}

@MainActor
final class SparkleUpdater: NSObject, ObservableObject {

    private static let udKey = "aurora.updateAvailable"

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var updateAvailable: Bool = UserDefaults.standard.bool(forKey: udKey)

    private let updaterController: SPUStandardUpdaterController
    private let sparkleDelegate = SparkleDelegate()

    override init() {
        // Never start the updater in debug builds (Xcode runs) — only in
        // production Release binaries. Beta also never updates itself.
        #if DEBUG
        let shouldStart = false
        #else
        let shouldStart = !AppPaths.isBeta
        #endif
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: shouldStart,
            updaterDelegate: sparkleDelegate,
            userDriverDelegate: nil
        )
        super.init()

        sparkleDelegate.onUpdateFound = { [weak self] in
            Task { @MainActor in
                self?.updateAvailable = true
                UserDefaults.standard.set(true, forKey: SparkleUpdater.udKey)
            }
        }
        sparkleDelegate.onNoUpdate = { [weak self] in
            Task { @MainActor in
                self?.updateAvailable = false
                UserDefaults.standard.set(false, forKey: SparkleUpdater.udKey)
            }
        }
        sparkleDelegate.onUpdateInstalled = { [weak self] in
            Task { @MainActor in
                self?.updateAvailable = false
                UserDefaults.standard.set(false, forKey: SparkleUpdater.udKey)
            }
        }

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
