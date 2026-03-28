import AppIntents
import Foundation

struct CaptureThoughtIntent: AppIntent {
    static var title: LocalizedStringResource = "Capture Thought"
    static var description = IntentDescription("Open Brain to record a new voice thought.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        // Signal the app to start recording immediately when it opens
        UserDefaults(suiteName: "group.com.dyerlab.openbrain")?.set(true, forKey: "launchToCapture")
        return .result()
    }
}

struct BrainTreeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureThoughtIntent(),
            phrases: [
                "Capture a thought with \(.applicationName)",
                "New thought with \(.applicationName)",
                "Add note to \(.applicationName)"
            ],
            shortTitle: "Capture Thought",
            systemImageName: "brain"
        )
    }
}
