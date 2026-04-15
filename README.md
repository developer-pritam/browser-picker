# Browser Picker

**Choose which browser opens every link on macOS.**

A lightweight macOS app that registers itself as the system default browser. Every time you click a link — from Mail, Slack, Notes, Terminal, or anywhere — a clean floating panel appears in the center of your screen listing all installed browsers. Pick one with a click or a number key. Or star a browser to skip the picker entirely and open links directly.

![Browser Picker panel](docs/assets/icon.png)

> **Download** → [browserpicker.developerpritam.in](https://browserpicker.developerpritam.in)

---

## Features

- **Instant picker panel** — appears in the center of your screen on any link click. Dismisses automatically after you choose.
- **Keyboard-first** — press `1`–`9` to open in a specific browser, `↑↓` to navigate, `Enter` to confirm, `Esc` to cancel.
- **Set a default, skip the dialog** — star any browser in Settings to open links directly with no picker shown. Switch defaults anytime from the menu bar.
- **Dynamic browser discovery** — uses `NSWorkspace.urlsForApplications(toOpen:)` to detect every installed browser automatically. No hardcoded list.
- **Reorder & hide** — drag browsers to set your preferred order. Eye-toggle any you never use so they don't clutter the picker.
- **Status bar menu** — change your default browser instantly from the menu bar without opening Settings.
- **Launch at login** — stays out of your way and is always ready.
- **Privacy first** — no network calls, no analytics, no telemetry. Completely offline.

---

## Requirements

- macOS 14 Sonoma or later
- Apple Silicon or Intel Mac

---

## Installation (pre-built)

1. Download `BrowserPicker-<version>.zip` from the [Releases](../../releases) page.
2. Unzip and drag **BrowserPicker.app** to `/Applications`.
3. **Right-click → Open** on first launch to bypass the Gatekeeper warning (unsigned app).
4. Go to **System Settings → Desktop & Dock → Default web browser** and choose **Browser Picker**.
5. Click any link — the picker panel appears.

To uninstall: quit from the menu bar icon, then move `BrowserPicker.app` to Trash.

---

## Building from source

**Prerequisites:** Xcode 15+, [xcodegen](https://github.com/yonaskolb/XcodeGen)

```bash
# Install xcodegen if needed
brew install xcodegen

# Clone and build
git clone https://github.com/developer-pritam/browser-picker.git
cd browser-picker
xcodegen generate
open BrowserPicker.xcodeproj
```

Build and run from Xcode (`⌘R`). Then set Browser Picker as your default browser in System Settings.

### Release build (unsigned zip)

```bash
./scripts/build-release.sh
# Output: dist/BrowserPicker-1.0.zip

# With explicit version
./scripts/build-release.sh --version 1.1

# Build and publish to GitHub Releases
./scripts/build-release.sh --version 1.1 --publish

# Publish as draft first
./scripts/build-release.sh --version 1.1 --publish --draft
```

### Regenerate app icon

```bash
swift scripts/generate-icon.swift
```

---

## Project structure

```
browser-picker/
├── BrowserPicker/
│   ├── AppDelegate.swift          # App lifecycle, URL interception, panel, status bar
│   ├── BrowserPickerApp.swift     # SwiftUI @main entry point
│   ├── BrowserManager.swift       # Browser discovery, persistence, picker actions
│   ├── Browser.swift              # Browser + ManagedBrowser models
│   ├── ContentView.swift          # Floating picker panel UI + BrowserRow
│   ├── WelcomeWindow.swift        # Settings window (Browsers / Preferences / How to Use tabs)
│   ├── Info.plist                 # LSUIElement, CFBundleURLTypes, CFBundleDocumentTypes
│   ├── BrowserPicker.entitlements
│   └── Assets.xcassets/           # App icon (all sizes)
├── docs/                          # GitHub Pages website
│   ├── index.html
│   ├── CNAME
│   └── assets/
├── scripts/
│   ├── build-release.sh           # Clean release build → versioned zip
│   └── generate-icon.swift        # Generates app icon PNGs with Core Graphics
├── dist/                          # Build output (git-ignored)
├── project.yml                    # XcodeGen spec
└── README.md
```

---

## How it works

### Default browser registration

`Info.plist` declares two things that together make macOS list the app in **System Settings → Desktop & Dock → Default web browser**:

1. **`CFBundleURLTypes`** — claims `http` and `https` URL schemes with `CFBundleTypeRole: Editor` and `LSHandlerRank: Owner`.
2. **`CFBundleDocumentTypes`** — claims `public.html` / `public.xhtml` document types with `LSHandlerRank: Alternate`. This is what triggers macOS to recognise the app as a `com.apple.default-app.web-browser` UTI handler and show it in the dropdown.

After installing to `/Applications`, run `lsregister -f -R -trusted ~/Applications/BrowserPicker.app` to force Launch Services to pick up the registration immediately.

### URL interception

Instead of SwiftUI's `onOpenURL`, the app registers with `NSAppleEventManager.setEventHandler(_:andSelector:forEventClass:andEventID:)` for `kInternetEventClass / kAEGetURL`. This is the same mechanism browsers use and is more reliable for the default browser use-case.

### Picker panel

`AppDelegate.setupPanel()` creates an `NSPanel` with `.nonactivatingPanel | .fullSizeContentView` at `.floating` window level. The non-activating style means it appears without stealing focus from the app you clicked from.

A custom `PickerHostingView: NSHostingView<ContentView>` overrides `keyDown(with:)` directly, handling arrow keys, Enter, Esc, and digit keys. This bypasses SwiftUI's `onKeyPress` which is unreliable on non-activating floating panels.

### Browser discovery

`BrowserManager.refreshBrowsers()` calls `NSWorkspace.shared.urlsForApplications(toOpen: URL(string: "https://example.com")!)` which returns every app registered as an `https://` handler. The app's own bundle ID is filtered out. Display names are read from `CFBundleDisplayName` falling back to `CFBundleName`.

### Persistence

Browser order, hidden state, and primary (default) state are saved as a `[BrowserPref]` JSON array in `UserDefaults` keyed by bundle ID. New browsers discovered after first launch are appended to the bottom. The `isPrimary` field uses a custom `init(from:)` decoder so old saved data (without the field) migrates gracefully.

### Direct open

When a browser is starred as the default, `handleGetURL` checks `BrowserManager.primaryBrowser` and calls `NSWorkspace.shared.open(_:withApplicationAt:configuration:)` directly, bypassing the panel entirely.

### Smooth update

On launch, `terminateOldInstances` finds any running instances of the same bundle ID, calls `forceTerminate()`, and polls `NSRunningApplication.isTerminated` before setting up the new status bar icon — so no ghost icons appear when deploying a new build.

---

## Acknowledgements

Inspired by Android's browser chooser dialog and the general frustration of not having this feature natively on macOS.

---

## License

MIT License — see [LICENSE](LICENSE) for details.

---

Built by [Pritam](https://developerpritam.in) · [Buy me a coffee](https://developerpritam.in/donate)
