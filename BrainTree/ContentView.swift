import SwiftUI
#if os(iOS)
import UIKit
private let didBecomeActiveNotification = UIApplication.didBecomeActiveNotification
#else
import AppKit
private let didBecomeActiveNotification = NSApplication.didBecomeActiveNotification
#endif

struct ContentView: View {
    @State private var selectedTab = 0
    @State private var showSetup = false

    var body: some View {
        TabView(selection: $selectedTab) {
            FeedView()
                .tabItem { Label("Feed", systemImage: "list.bullet") }
                .tag(0)

            AskView()
                .tabItem { Label("Ask", systemImage: "magnifyingglass") }
                .tag(1)

            CaptureView()
                .tabItem { Label("Capture", systemImage: "mic") }
                .tag(2)

            settingsTab
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(3)
        }
        .onAppear {
            if !KeychainClient.allPresent { showSetup = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: didBecomeActiveNotification)) { _ in
            let defaults = UserDefaults(suiteName: "group.com.dyerlab.openbrain")
            if defaults?.bool(forKey: "launchToCapture") == true {
                defaults?.removeObject(forKey: "launchToCapture")
                selectedTab = 2
            }
        }
        .sheet(isPresented: $showSetup) {
            SecretsSetupView()
        }
    }

    private var settingsTab: some View {
        NavigationStack {
            List {
                Section("About") {
                    LabeledContent("App", value: "Open Brain")
                    LabeledContent("Backend", value: "Supabase + MCP")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("API Keys") { showSetup = true }
                }
            }
        }
    }
}
