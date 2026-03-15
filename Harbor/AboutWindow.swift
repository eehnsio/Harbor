import AppKit

class AboutWindow {
    private static var window: NSWindow?

    static func show() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let w: CGFloat = 280
        let h: CGFloat = 220

        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: w, height: h),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = ""
        window.isReleasedWhenClosed = false
        window.center()
        window.isMovableByWindowBackground = true

        let content = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))

        // App icon
        let iconView = NSImageView(frame: NSRect(x: (w - 64) / 2, y: h - 80, width: 64, height: 64))
        iconView.image = NSApp.applicationIconImage
        content.addSubview(iconView)

        // App name
        let nameLabel = NSTextField(labelWithString: "Harbor")
        nameLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        nameLabel.alignment = .center
        nameLabel.frame = NSRect(x: 0, y: h - 105, width: w, height: 22)
        content.addSubview(nameLabel)

        // Version
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let gitHash = Bundle.main.infoDictionary?["GitCommitHash"] as? String ?? "dev"
        let versionLabel = NSTextField(labelWithString: "Version \(version) (\(gitHash))")
        versionLabel.font = .systemFont(ofSize: 11)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.alignment = .center
        versionLabel.frame = NSRect(x: 0, y: h - 125, width: w, height: 16)
        content.addSubview(versionLabel)

        // Description
        let descLabel = NSTextField(labelWithString: "Dev server port monitor for macOS")
        descLabel.font = .systemFont(ofSize: 12)
        descLabel.textColor = .secondaryLabelColor
        descLabel.alignment = .center
        descLabel.frame = NSRect(x: 0, y: h - 148, width: w, height: 16)
        content.addSubview(descLabel)

        // Author
        let authorLabel = NSTextField(labelWithString: "Made by Erik Ehnsio")
        authorLabel.font = .systemFont(ofSize: 11)
        authorLabel.textColor = .tertiaryLabelColor
        authorLabel.alignment = .center
        authorLabel.frame = NSRect(x: 0, y: h - 166, width: w, height: 16)
        content.addSubview(authorLabel)

        // Buttons
        let buttonWidth: CGFloat = 110
        let buttonGap: CGFloat = 10
        let totalWidth = buttonWidth * 2 + buttonGap
        let startX = (w - totalWidth) / 2

        let ghButton = IconLinkButton(
            title: " GitHub",
            symbolName: "chevron.left.forwardslash.chevron.right",
            url: "https://github.com/eehnsio/Harbor"
        )
        ghButton.frame = NSRect(x: startX, y: 18, width: buttonWidth, height: 28)
        content.addSubview(ghButton)

        let coffeeButton = IconLinkButton(
            title: " Support",
            symbolName: "heart.fill",
            url: "https://buymeacoffee.com/eehnsio"
        )
        coffeeButton.frame = NSRect(x: startX + buttonWidth + buttonGap, y: 18, width: buttonWidth, height: 28)
        content.addSubview(coffeeButton)

        window.contentView = content
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }
}

// MARK: - Icon link button

private class IconLinkButton: NSButton {
    private let url: String

    init(title: String, symbolName: String, url: String) {
        self.url = url
        super.init(frame: .zero)

        self.title = title
        image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .medium))
        imagePosition = .imageLeading
        bezelStyle = .rounded
        controlSize = .regular
        font = .systemFont(ofSize: 12)
        target = self
        action = #selector(openLink)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func openLink() {
        if let url = URL(string: url) {
            NSWorkspace.shared.open(url)
        }
    }
}
