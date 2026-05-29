import SwiftUI

@main
struct commanderonev2App: App {
    @State private var appState = AppState()

    init() {
        FontLoader.registerAll()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(appState: appState)
                .frame(minWidth: 1280, minHeight: 800)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
    }
}
