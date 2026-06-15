import SwiftUI

@main
struct commanderonev2App: App {
    @State private var appState = AppState()
    @State private var showLicenseOverlay = !LicensingService.isActivated()

    #if canImport(Sparkle)
    @StateObject private var updater = SparkleUpdater()
    #endif

    init() {
        FontLoader.registerAll()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(appState: appState, showLicenseOverlay: $showLicenseOverlay)
                .frame(minWidth: 1280, minHeight: 800)
                #if canImport(Sparkle)
                .environmentObject(updater)
                #endif
                .overlay {
                    if showLicenseOverlay {
                        LicenseEntryView(isPresented: $showLicenseOverlay)
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
        .commands {
            #if canImport(Sparkle)
            if !AppPaths.isBeta {
                CommandGroup(after: .appInfo) {
                    Button("Check for Updates…") {
                        updater.checkForUpdates()
                    }
                    .disabled(!updater.canCheckForUpdates)
                }
            }
            #endif
        }
    }
}
