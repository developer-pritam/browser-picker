import AppKit
import Combine

final class BrowserManager: ObservableObject {
    static let shared = BrowserManager()

    /// All browsers in user-defined order, including hidden ones. Used by the management UI.
    @Published var managedBrowsers: [ManagedBrowser] = []

    /// Only the visible browsers shown in the picker — primary first, then the rest in order.
    var visibleBrowsers: [Browser] {
        let visible = managedBrowsers.filter { !$0.isHidden }
        if let primaryIdx = visible.firstIndex(where: { $0.isPrimary }) {
            var ordered = visible
            let primary = ordered.remove(at: primaryIdx)
            ordered.insert(primary, at: 0)
            return ordered.map { $0.browser }
        }
        return visible.map { $0.browser }
    }

    @Published var pendingURL: URL?
    @Published var selectedIndex: Int = 0

    private let prefsKey = "com.dp.BrowserPicker.browserPrefs"

    // Lightweight persistence: ordered array of (bundleId, isHidden, isPrimary)
    private struct BrowserPref: Codable {
        let bundleId: String
        var isHidden: Bool
        var isPrimary: Bool

        init(bundleId: String, isHidden: Bool, isPrimary: Bool) {
            self.bundleId = bundleId
            self.isHidden = isHidden
            self.isPrimary = isPrimary
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            bundleId = try c.decode(String.self, forKey: .bundleId)
            isHidden = try c.decode(Bool.self, forKey: .isHidden)
            isPrimary = (try? c.decode(Bool.self, forKey: .isPrimary)) ?? false
        }
    }

    private init() {
        refreshBrowsers()
    }

    // MARK: - Discovery & Merge

    func refreshBrowsers() {
        guard let testURL = URL(string: "https://example.com") else { return }

        let discovered: [Browser] = NSWorkspace.shared
            .urlsForApplications(toOpen: testURL)
            .compactMap { appURL in
                guard
                    let bundle = Bundle(url: appURL),
                    let bundleId = bundle.bundleIdentifier,
                    bundleId != Bundle.main.bundleIdentifier,
                    let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                             ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                else { return nil }
                return Browser(name: name, bundleId: bundleId, appURL: appURL)
            }

        let saved = loadPrefs()
        let savedIds = saved.map { $0.bundleId }

        // 1. Saved browsers in saved order (only if still installed)
        var result: [ManagedBrowser] = saved.compactMap { pref in
            guard let browser = discovered.first(where: { $0.bundleId == pref.bundleId })
            else { return nil }
            return ManagedBrowser(browser: browser, isHidden: pref.isHidden, isPrimary: pref.isPrimary)
        }

        // 2. New browsers not in saved prefs go to the bottom, visible by default
        for browser in discovered where !savedIds.contains(browser.bundleId) {
            result.append(ManagedBrowser(browser: browser, isHidden: false, isPrimary: false))
        }

        managedBrowsers = result
        selectedIndex = 0
    }

    // MARK: - Management Actions

    func move(from source: IndexSet, to destination: Int) {
        managedBrowsers.move(fromOffsets: source, toOffset: destination)
        savePrefs()
    }

    func toggleHidden(bundleId: String) {
        guard let idx = managedBrowsers.firstIndex(where: { $0.id == bundleId }) else { return }
        managedBrowsers[idx].isHidden.toggle()
        savePrefs()
    }

    // MARK: - Picker Actions

    func receiveURL(_ url: URL) {
        pendingURL = url
        selectedIndex = 0
    }

    func open(url: URL, in browser: Browser) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: browser.appURL, configuration: config)
        pendingURL = nil
        selectedIndex = 0
    }

    func openInSelectedBrowser() {
        let visible = visibleBrowsers
        guard visible.indices.contains(selectedIndex), let url = pendingURL else { return }
        open(url: url, in: visible[selectedIndex])
    }

    func moveSelectionUp() {
        if selectedIndex > 0 { selectedIndex -= 1 }
    }

    func moveSelectionDown() {
        if selectedIndex < visibleBrowsers.count - 1 { selectedIndex += 1 }
    }

    func selectByNumber(_ n: Int) {
        let index = n - 1
        let visible = visibleBrowsers
        guard visible.indices.contains(index), let url = pendingURL else { return }
        open(url: url, in: visible[index])
    }

    // MARK: - Persistence

    private func loadPrefs() -> [BrowserPref] {
        guard
            let data = UserDefaults.standard.data(forKey: prefsKey),
            let prefs = try? JSONDecoder().decode([BrowserPref].self, from: data)
        else { return [] }
        return prefs
    }

    /// The browser that should receive URLs directly, bypassing the picker. nil = always ask.
    var primaryBrowser: Browser? {
        managedBrowsers.first(where: { $0.isPrimary })?.browser
    }

    func setPrimary(bundleId: String) {
        for idx in managedBrowsers.indices {
            managedBrowsers[idx].isPrimary = (managedBrowsers[idx].id == bundleId)
        }
        savePrefs()
    }

    func clearPrimary() {
        for idx in managedBrowsers.indices {
            managedBrowsers[idx].isPrimary = false
        }
        savePrefs()
    }

    private func savePrefs() {
        let prefs = managedBrowsers.map { BrowserPref(bundleId: $0.id, isHidden: $0.isHidden, isPrimary: $0.isPrimary) }
        if let data = try? JSONEncoder().encode(prefs) {
            UserDefaults.standard.set(data, forKey: prefsKey)
        }
    }
}
