import SwiftUI
import ServiceManagement

// MARK: - Window Controller

final class WelcomeWindowController: NSWindowController, NSWindowDelegate {

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Browser Picker"
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 420, height: 480)
        window.center()
        window.isReleasedWhenClosed = false

        let view = WelcomeView { window.close() }
        window.contentView = NSHostingView(rootView: view)
        self.init(window: window)
        window.delegate = self
    }

    func show() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

// MARK: - Tab

private enum Tab: String, CaseIterable {
    case browsers    = "Browsers"
    case preferences = "Preferences"
    case howToUse    = "How to Use"
}

// MARK: - Main View

struct WelcomeView: View {
    let close: () -> Void

    @ObservedObject private var manager = BrowserManager.shared
    @State private var isDefaultBrowser = false
    @State private var launchAtLogin = (SMAppService.mainApp.status == .enabled)
    @State private var showStatusBarIcon: Bool = {
        // Returns the registered default (true) if not yet set, or the user's saved value
        UserDefaults.standard.object(forKey: "showStatusBarIcon") != nil
            ? UserDefaults.standard.bool(forKey: "showStatusBarIcon")
            : true
    }()
    @State private var draggedBundleId: String?
    @State private var selectedTab: Tab = .browsers

    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            tabBar
            Divider()
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footerSection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { refreshStatus() }
        .onReceive(timer) { _ in refreshStatus() }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 14) {
            Image(systemName: "globe")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .indigo],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Browser Picker")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("v\(appVersion)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
                Text("Choose which browser opens every link")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases, id: \.self) { tab in
                TabButton(title: tab.rawValue, isSelected: selectedTab == tab) {
                    withAnimation(.easeInOut(duration: 0.15)) { selectedTab = tab }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .browsers:    browsersTab
        case .preferences: preferencesTab
        case .howToUse:    howToUseTab
        }
    }

    // MARK: - Browsers Tab

    private var browsersTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Drag to reorder  ·  ★ to set default  ·  eye to hide")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 6)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(manager.managedBrowsers) { item in
                        BrowserManagementRow(
                            item: item,
                            isDragging: draggedBundleId == item.id,
                            onToggle: { manager.toggleHidden(bundleId: item.id) },
                            onSetPrimary: { manager.setPrimary(bundleId: item.id) }
                        )
                        .onDrag {
                            draggedBundleId = item.id
                            return NSItemProvider(object: item.id as NSString)
                        }
                        .onDrop(of: [.plainText], isTargeted: nil) { _ in
                            guard
                                let fromId = draggedBundleId,
                                let fromIdx = manager.managedBrowsers.firstIndex(where: { $0.id == fromId }),
                                let toIdx  = manager.managedBrowsers.firstIndex(where: { $0.id == item.id }),
                                fromIdx != toIdx
                            else { return false }
                            withAnimation(.easeInOut(duration: 0.2)) {
                                manager.move(
                                    from: IndexSet(integer: fromIdx),
                                    to: toIdx > fromIdx ? toIdx + 1 : toIdx
                                )
                            }
                            draggedBundleId = nil
                            return true
                        }

                        if item.id != manager.managedBrowsers.last?.id {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Preferences Tab

    private var preferencesTab: some View {
        ScrollView {
            VStack(spacing: 0) {
                PreferenceRow(
                    icon: "arrow.circlepath",
                    iconColor: .green,
                    title: "Launch at Login",
                    description: "Automatically start Browser Picker when you log in to your Mac."
                ) {
                    Toggle("", isOn: $launchAtLogin)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .onChange(of: launchAtLogin) { _, enabled in
                            do {
                                if enabled { try SMAppService.mainApp.register()   }
                                else       { try SMAppService.mainApp.unregister() }
                            } catch {
                                launchAtLogin = (SMAppService.mainApp.status == .enabled)
                            }
                        }
                }

                Divider().padding(.leading, 50)

                PreferenceRow(
                    icon: "menubar.rectangle",
                    iconColor: .purple,
                    title: "Show Status Bar Icon",
                    description: "Display the globe icon in your menu bar for quick access to settings and browser selection."
                ) {
                    Toggle("", isOn: $showStatusBarIcon)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .onChange(of: showStatusBarIcon) { _, enabled in
                            UserDefaults.standard.set(enabled, forKey: "showStatusBarIcon")
                            NotificationCenter.default.post(name: .statusBarIconVisibilityChanged, object: nil)
                        }
                }

                Divider().padding(.leading, 50)

                PreferenceRow(
                    icon: "globe.badge.chevron.backward",
                    iconColor: .blue,
                    title: "Default Browser",
                    description: isDefaultBrowser
                        ? "Browser Picker is your current default browser."
                        : "Open Desktop & Dock settings to make Browser Picker your default browser."
                ) {
                    if isDefaultBrowser {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 18))
                    } else {
                        Button("Open Settings") {
                            NSWorkspace.shared.open(
                                URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")!
                            )
                        }
                        .controlSize(.small)
                    }
                }
            }
            .padding(.top, 8)
        }
    }

    // MARK: - How to Use Tab

    private var howToUseTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                StepRow(number: 1, text: "Go to **System Settings → Desktop & Dock → Default web browser** and choose **Browser Picker**")
                StepRow(number: 2, text: "Click any link — the picker panel appears instantly in the center of your screen")
                StepRow(number: 3, text: "Click a browser, or press **1–9** for quick selection, **↑↓** to navigate, **Esc** to cancel")
            }
            .padding(20)
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack(spacing: 10) {
            if !isDefaultBrowser {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                    Text("Not set as default browser")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            Spacer()
            Button("Done") { close() }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Helpers

    private func refreshStatus() {
        guard let testURL = URL(string: "https://example.com"),
              let defaultAppURL = NSWorkspace.shared.urlForApplication(toOpen: testURL),
              let bundleId = Bundle(url: defaultAppURL)?.bundleIdentifier
        else { isDefaultBrowser = false; return }
        isDefaultBrowser = (bundleId == Bundle.main.bundleIdentifier)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

// MARK: - Tab Button

private struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .accentColor : .secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected
                              ? Color.accentColor.opacity(0.12)
                              : (isHovered ? Color.secondary.opacity(0.08) : .clear))
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Preference Row

private struct PreferenceRow<Control: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(iconColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            control()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

// MARK: - Step Row

private struct StepRow: View {
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 24, height: 24)
                Text("\(number)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.accentColor)
            }
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Browser Management Row

private struct BrowserManagementRow: View {
    let item: ManagedBrowser
    let isDragging: Bool
    let onToggle: () -> Void
    let onSetPrimary: () -> Void

    @State private var isToggleHovered = false
    @State private var isStarHovered   = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 20)

            Image(nsImage: item.browser.icon)
                .resizable()
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .opacity(item.isHidden ? 0.35 : 1.0)

            HStack(spacing: 6) {
                Text(item.browser.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(item.isHidden ? .tertiary : .primary)
                    .lineLimit(1)

                if item.isPrimary {
                    Text("Default")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
            }

            Spacer()

            // Star — set as default
            Button(action: onSetPrimary) {
                Image(systemName: item.isPrimary ? "star.fill" : "star")
                    .font(.system(size: 13))
                    .foregroundColor(item.isPrimary
                                     ? .yellow
                                     : (isStarHovered ? Color.secondary : Color.secondary.opacity(0.4)))
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isStarHovered && !item.isPrimary ? Color.secondary.opacity(0.12) : .clear)
                    )
            }
            .buttonStyle(.plain)
            .onHover { isStarHovered = $0 }
            .help(item.isPrimary ? "Current default browser" : "Set as default (opens directly, skips picker)")

            // Eye — hide / show
            Button(action: onToggle) {
                Image(systemName: item.isHidden ? "eye.slash" : "eye")
                    .font(.system(size: 13))
                    .foregroundStyle(item.isHidden ? .tertiary : .secondary)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isToggleHovered ? Color.secondary.opacity(0.12) : .clear)
                    )
            }
            .buttonStyle(.plain)
            .onHover { isToggleHovered = $0 }
            .help(item.isHidden ? "Show in picker" : "Hide from picker")
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isDragging ? Color.accentColor.opacity(0.08) : .clear)
        )
        .contentShape(Rectangle())
    }
}
