import AppKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let viewModel = PortViewModel()
    private let menuWidth: CGFloat = 290

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "network", accessibilityDescription: "Harbor")

        refreshAndRebuild()

        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshAndRebuild() }
        }
    }

    private func refreshAndRebuild() {
        viewModel.refresh()
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.minimumWidth = menuWidth
        let devPorts = viewModel.ports.filter { $0.isDevPort }

        if devPorts.isEmpty {
            let item = NSMenuItem(title: "No dev ports", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            let grouped = Dictionary(grouping: devPorts) { port in
                port.projectName.isEmpty ? port.displayName : port.projectName
            }
            // Preserve order by first port number in each group
            let sortedGroups = grouped.sorted { $0.value[0].port < $1.value[0].port }

            for (index, (project, ports)) in sortedGroups.enumerated() {
                let header = NSMenuItem()
                header.attributedTitle = NSAttributedString(
                    string: project,
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                        .foregroundColor: NSColor.tertiaryLabelColor,
                    ]
                )
                header.isEnabled = false
                menu.addItem(header)

                for port in ports {
                    menu.addItem(makePortItem(port: port))
                }

                if index < sortedGroups.count - 1 {
                    menu.addItem(.separator())
                }
            }
        }

        menu.addItem(.separator())

        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshAction), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let quitItem = NSMenuItem(title: "Quit Harbor", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        let gitHash = Bundle.main.infoDictionary?["GitCommitHash"] as? String ?? "dev"
        let versionItem = NSMenuItem()
        versionItem.attributedTitle = NSAttributedString(
            string: "Version \(gitHash)",
            attributes: [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]
        )
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        statusItem.menu = menu
    }

    private func makePortItem(port: ListeningPort) -> NSMenuItem {
        let item = NSMenuItem()
        item.representedObject = port.pid
        item.view = PortMenuItemView(
            port: String(port.port),
            name: port.shortName,
            memory: Formatters.memory(port.physicalMemory),
            uptime: Formatters.uptime(port.uptime),
            width: menuWidth,
            onKill: { [weak self] in
                self?.viewModel.killProcess(port)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self?.refreshAndRebuild()
                }
            }
        )
        return item
    }

    @objc private func refreshAction() { refreshAndRebuild() }
    @objc private func quitAction() { NSApplication.shared.terminate(nil) }
}

// MARK: - Custom menu item view

class PortMenuItemView: NSView {
    private var trackingArea: NSTrackingArea?
    private var isHighlighted = false
    private let onKill: () -> Void

    private let portLabel: NSTextField
    private let nameLabel: NSTextField
    private let memoryLabel: NSTextField
    private let uptimeLabel: NSTextField
    private let killButton: NSButton

    private let rightPad: CGFloat = 14

    init(port: String, name: String, memory: String, uptime: String, width: CGFloat, onKill: @escaping () -> Void) {
        self.onKill = onKill
        portLabel = NSTextField(labelWithString: port)
        nameLabel = NSTextField(labelWithString: name)
        memoryLabel = NSTextField(labelWithString: memory)
        uptimeLabel = NSTextField(labelWithString: uptime)
        killButton = NSButton()

        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 22))
        setupViews(width: width)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews(width: CGFloat) {
        let leftPad: CGFloat = 20
        let killSize: CGFloat = 18

        // Kill button (right edge, hidden until hover)
        killButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Kill")?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
        killButton.bezelStyle = .inline
        killButton.isBordered = false
        killButton.imagePosition = .imageOnly
        killButton.contentTintColor = .secondaryLabelColor
        killButton.frame = NSRect(x: width - rightPad - killSize, y: 2, width: killSize, height: killSize)
        killButton.target = self
        killButton.action = #selector(killClicked)
        killButton.isHidden = true
        addSubview(killButton)

        // Memory (right-aligned)
        let memWidth: CGFloat = 50
        memoryLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        memoryLabel.textColor = .tertiaryLabelColor
        memoryLabel.alignment = .right
        memoryLabel.frame = NSRect(x: width - rightPad - memWidth, y: 3, width: memWidth, height: 16)
        addSubview(memoryLabel)

        // Uptime
        let uptimeWidth: CGFloat = 50
        let uptimeX = memoryLabel.frame.minX - uptimeWidth - 4
        uptimeLabel.font = .systemFont(ofSize: 11)
        uptimeLabel.textColor = .tertiaryLabelColor
        uptimeLabel.alignment = .right
        uptimeLabel.frame = NSRect(x: uptimeX, y: 3, width: uptimeWidth, height: 16)
        addSubview(uptimeLabel)

        // Port number (fixed width so names align across rows)
        let portWidth: CGFloat = 52
        portLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        portLabel.textColor = .labelColor
        portLabel.alignment = .right
        portLabel.frame = NSRect(x: leftPad, y: 2, width: portWidth, height: 18)
        addSubview(portLabel)

        // Name
        let nameX = leftPad + portWidth + 8
        nameLabel.font = .systemFont(ofSize: 13)
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.frame = NSRect(x: nameX, y: 2, width: uptimeX - nameX - 4, height: 18)
        addSubview(nameLabel)
    }

    @objc private func killClicked() {
        enclosingMenuItem?.menu?.cancelTracking()
        onKill()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        isHighlighted = true
        needsDisplay = true
        killButton.isHidden = false
        killButton.contentTintColor = .white
        uptimeLabel.isHidden = true
        memoryLabel.isHidden = true
        portLabel.textColor = .white
        nameLabel.textColor = .white
    }

    override func mouseExited(with event: NSEvent) {
        isHighlighted = false
        needsDisplay = true
        killButton.isHidden = true
        uptimeLabel.isHidden = false
        memoryLabel.isHidden = false
        portLabel.textColor = .labelColor
        nameLabel.textColor = .labelColor
        uptimeLabel.textColor = .tertiaryLabelColor
        memoryLabel.textColor = .tertiaryLabelColor
    }

    override func mouseUp(with event: NSEvent) {}

    override func draw(_ dirtyRect: NSRect) {
        if isHighlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 0), xRadius: 4, yRadius: 4).fill()
        }
    }
}
