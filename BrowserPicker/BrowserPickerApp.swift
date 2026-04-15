import SwiftUI

@main
struct BrowserPickerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Settings is the least intrusive placeholder scene for a background agent.
        // WindowGroup would create a visible window; Settings does not.
        Settings {
            EmptyView()
        }
    }
}
