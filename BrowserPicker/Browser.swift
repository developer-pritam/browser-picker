import AppKit

struct Browser: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let bundleId: String
    let appURL: URL

    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: appURL.path)
    }

    static func == (lhs: Browser, rhs: Browser) -> Bool {
        lhs.bundleId == rhs.bundleId
    }
}

struct ManagedBrowser: Identifiable {
    let browser: Browser
    var isHidden: Bool
    var isPrimary: Bool

    var id: String { browser.bundleId }
}
