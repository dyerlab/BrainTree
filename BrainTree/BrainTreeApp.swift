import SwiftUI
import AppIntents

@main
struct BrainTreeApp: App {
    init() {
        BrainTreeShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
