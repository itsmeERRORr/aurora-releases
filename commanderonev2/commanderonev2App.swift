import SwiftUI

@main
struct commanderonev2App: App {
    @State private var appState = AppState()

    #if canImport(Sparkle)
    // Initialised in both Beta and Production, but `SparkleUpdater.init()` only
    // *starts* the updater for Production. On Beta the menu item below is also
    // hidden via AppPaths.isBeta.
    @StateObject private var updater = SparkleUpdater()
    #endif

    init() {
        FontLoader.registerAll()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(appState: appState)
                .frame(minWidth: 1280, minHeight: 800)
                #if canImport(Sparkle)
                .environmentObject(updater)
                #endif
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
