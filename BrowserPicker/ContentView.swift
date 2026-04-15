import SwiftUI

struct ContentView: View {
    @ObservedObject var manager: BrowserManager
    let onDismiss: () -> Void
    @State private var hoveredId: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // URL preview
            if let url = manager.pendingURL {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text(url.host ?? url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)
                Divider()
            }

            // Browser list — only visible browsers
            let browsers = manager.visibleBrowsers
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(browsers.enumerated()), id: \.element.id) { index, browser in
                        BrowserRow(
                            browser: browser,
                            index: index,
                            isSelected: manager.selectedIndex == index
                        )
                        .onHover { hovering in
                            hoveredId = hovering ? browser.id : nil
                            if hovering { manager.selectedIndex = index }
                        }
                        .onTapGesture {
                            guard let url = manager.pendingURL else { return }
                            manager.open(url: url, in: browser)
                            onDismiss()
                        }
                    }
                }
                .padding(8)
            }
        }
        .frame(width: 320)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 20)
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
        .onKeyPress(.return) {
            manager.openInSelectedBrowser()
            onDismiss()
            return .handled
        }
        .onKeyPress(.upArrow) {
            manager.moveSelectionUp()
            return .handled
        }
        .onKeyPress(.downArrow) {
            manager.moveSelectionDown()
            return .handled
        }
        .onKeyPress(characters: .decimalDigits, phases: .down) { key in
            if let n = Int(key.key.character.description), n >= 1 {
                manager.selectByNumber(n)
                onDismiss()
                return .handled
            }
            return .ignored
        }
    }
}

struct BrowserRow: View {
    let browser: Browser
    let index: Int
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: browser.icon)
                .resizable()
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            Text(browser.name)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)

            Spacer()

            if index < 9 {
                Text("\(index + 1)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(.quaternary))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : .clear)
        )
        .contentShape(Rectangle())
    }
}
