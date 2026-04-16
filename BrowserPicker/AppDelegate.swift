import AppKit
import Carbon
import Sparkle
import SwiftUI

extension Notification.Name {
    static let statusBarIconVisibilityChanged = Notification.Name("com.dp.BrowserPicker.statusBarIconVisibility")
}

// NSHostingView subclass that accepts first responder and handles keyboard directly
private class PickerHostingView: NSHostingView<ContentView> {
    var onDismiss: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let manager = BrowserManager.shared
        guard manager.pendingURL != nil else { super.keyDown(with: event); return }

        switch event.keyCode {
        case 125: // down arrow
            manager.moveSelectionDown()
        case 126: // up arrow
            manager.moveSelectionUp()
        case 36, 76: // return / enter
            manager.openInSelectedBrowser()
            onDismiss?()
        case 53: // escape
            onDismiss?()
        default:
            if let chars = event.characters, let n = Int(chars), (1...9).contains(n) {
                manager.selectByNumber(n)
                onDismiss?()
            } else {
                super.keyDown(with: event)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var pickerPanel: NSPanel?
    private var welcomeWindowController: WelcomeWindowController?
    private var statusItem: NSStatusItem?
    private let statusMenu = NSMenu()
    private var updaterController: SPUStandardUpdaterController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Terminate any old instances so their status bar icons are cleaned up before we add ours
        terminateOldInstances {
            self.finishLaunching()
        }
    }

    private func terminateOldInstances(then completion: @escaping () -> Void) {
        guard let bundleId = Bundle.main.bundleIdentifier else { completion(); return }
        let old = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            .filter { $0 != NSRunningApplication.current }
        guard !old.isEmpty else { completion(); return }
        // Force-terminate is immediate (SIGKILL); avoids waiting on graceful shutdown
        old.forEach { $0.forceTerminate() }
        // Poll until all old instances are confirmed dead, then continue (max 2 s)
        waitUntilTerminated(old, deadline: .now() + 2, completion: completion)
    }

    private func waitUntilTerminated(_ apps: [NSRunningApplication], deadline: DispatchTime, completion: @escaping () -> Void) {
        let alive = apps.filter { !$0.isTerminated }
        if alive.isEmpty || DispatchTime.now() >= deadline {
            completion()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.waitUntilTerminated(alive, deadline: deadline, completion: completion)
        }
    }

    private func finishLaunching() {
        UserDefaults.standard.register(defaults: ["showStatusBarIcon": true])

        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:replyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        NSApp.setActivationPolicy(.accessory)
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        setupPanel()
        welcomeWindowController = WelcomeWindowController()
        // Close SwiftUI-generated windows BEFORE creating the status item —
        // NSApp.windows includes the NSStatusItem's internal button window, so
        // calling this after setupStatusBar() would close it and break click handling.
        NSApp.windows.forEach { $0.close() }
        if UserDefaults.standard.bool(forKey: "showStatusBarIcon") {
            setupStatusBar()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateStatusBarVisibility),
            name: .statusBarIconVisibilityChanged,
            object: nil
        )

        // Show welcome window on first ever launch
        let hasLaunchedBefore = UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
        if !hasLaunchedBefore {
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.welcomeWindowController?.show()
            }
        }
    }

    @objc private func updateStatusBarVisibility() {
        let show = UserDefaults.standard.bool(forKey: "showStatusBarIcon")
        if show {
            if statusItem == nil { setupStatusBar() }
        } else {
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
                statusItem = nil
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Remove status item immediately so the icon disappears before the process exits
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    // Called when user launches the app again while it's already running
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        welcomeWindowController?.show()
        return true
    }

    // MARK: - Status Bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            let image = NSImage(systemSymbolName: "globe", accessibilityDescription: "Browser Picker")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Browser Picker"
        }
        statusMenu.delegate = self
        statusItem?.menu = statusMenu
    }

    @objc private func openSettings() {
        welcomeWindowController?.show()
    }

    @objc func openDefaultBrowserSettings() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")!
        )
    }

    @objc private func setDefaultBrowserFromMenu(_ sender: NSMenuItem) {
        guard let bundleId = sender.representedObject as? String else { return }
        BrowserManager.shared.setPrimary(bundleId: bundleId)
    }

    @objc private func clearDefaultBrowser() {
        BrowserManager.shared.clearPrimary()
    }

    // MARK: - Panel

    private func setupPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 400),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.title = ""
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        panel.backgroundColor = .clear

        let contentView = ContentView(
            manager: BrowserManager.shared,
            onDismiss: { [weak self] in self?.hidePanel() }
        )
        let hostingView = PickerHostingView(rootView: contentView)
        hostingView.onDismiss = { [weak self] in self?.hidePanel() }
        panel.contentView = hostingView
        pickerPanel = panel
    }

    func showPanel() {
        guard let panel = pickerPanel else { return }
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        if let screen {
            let origin = CGPoint(
                x: screen.visibleFrame.midX - panel.frame.width / 2,
                y: screen.visibleFrame.midY - panel.frame.height / 2
            )
            panel.setFrameOrigin(origin)
        } else {
            panel.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        // Give the hosting view first-responder status so onKeyPress fires immediately
        panel.makeFirstResponder(panel.contentView)
    }

    func hidePanel() {
        pickerPanel?.orderOut(nil)
        BrowserManager.shared.pendingURL = nil
    }

    // MARK: - Apple Event

    @objc func handleGetURL(_ event: NSAppleEventDescriptor, replyEvent: NSAppleEventDescriptor) {
        guard
            let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
            let url = URL(string: urlString)
        else { return }
        DispatchQueue.main.async {
            let manager = BrowserManager.shared
            if let primary = manager.primaryBrowser {
                // Skip the picker — open directly in the chosen default
                manager.open(url: url, in: primary)
            } else {
                manager.receiveURL(url)
                self.showPanel()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

// MARK: - Status Menu (built fresh each time it opens)

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let manager = BrowserManager.shared

        // Title
        let title = NSMenuItem(title: "Browser Picker", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        // Settings
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)

        // Check for Updates
        let checkUpdates = NSMenuItem(title: "Check for Updates…", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
        checkUpdates.target = updaterController
        menu.addItem(checkUpdates)

        menu.addItem(.separator())

        // Open links with — browser list
        let hasPrimary = manager.managedBrowsers.contains(where: { $0.isPrimary })
        let headerItem = NSMenuItem(title: "Open Links With", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        for managed in manager.managedBrowsers where !managed.isHidden {
            let item = NSMenuItem(
                title: managed.browser.name,
                action: #selector(setDefaultBrowserFromMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = managed.id
            item.state = managed.isPrimary ? .on : .off
            let icon = managed.browser.icon.copy() as! NSImage
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            menu.addItem(item)
        }

        // Always Ask option
        let alwaysAsk = NSMenuItem(title: "Always Ask", action: #selector(clearDefaultBrowser), keyEquivalent: "")
        alwaysAsk.target = self
        alwaysAsk.state = hasPrimary ? .off : .on
        menu.addItem(alwaysAsk)

        menu.addItem(.separator())

        // Quit
        let quit = NSMenuItem(title: "Quit Browser Picker", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
    }
}
