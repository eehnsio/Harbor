import AppKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var viewModel = PortViewModel()
    private var refreshTimer: Timer?
    private let menuWidth: CGFloat = 290

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "network", accessibilityDescription: "Harbor")
        }

        rebuildMenu()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.viewModel.refresh()
                self?.rebuildMenu()
            }
        }
    }

    @MainActor
    private func rebuildMenu() {
        let menu = NSMenu()
        menu.minimumWidth = menuWidth
        let devPorts = viewModel.ports.filter { $0.isDevPort }

        if devPorts.isEmpty {
            let item = NSMenuItem(title: "No dev ports", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            let grouped = groupPorts(devPorts)

            for (index, group) in grouped.enumerated() {
                let header = NSMenuItem(title: "", action: nil, keyEquivalent: "")
                header.attributedTitle = NSAttributedString(
                    string: group.project,
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                        .foregroundColor: NSColor.tertiaryLabelColor,
                    ]
                )
                header.isEnabled = false
                menu.addItem(header)

                for port in group.ports {
                    let item = makePortItem(port: port)
                    menu.addItem(item)
                }

                if index < grouped.count - 1 {
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

        statusItem.menu = menu
    }

    private func makePortItem(port: ListeningPort) -> NSMenuItem {
        let item = NSMenuItem()
        item.representedObject = port.pid

        let view = PortMenuItemView(
            port: String(port.port),
            name: port.shortName,
            memory: Formatters.memory(port.physicalMemory),
            uptime: Formatters.uptime(port.uptime),
            width: menuWidth,
            onKill: { [weak self] in
                self?.killPort(pid: port.pid)
            }
        )
        item.view = view
        return item
    }

    private func killPort(pid: pid_t) {
        if let port = viewModel.ports.first(where: { $0.pid == pid }) {
            viewModel.killProcess(port)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.viewModel.refresh()
            self?.rebuildMenu()
        }
    }

    private func groupPorts(_ ports: [ListeningPort]) -> [(project: String, ports: [ListeningPort])] {
        var seen: [String: Int] = [:]
        var groups: [(project: String, ports: [ListeningPort])] = []

        for port in ports {
            let key = port.projectName.isEmpty ? port.displayName : port.projectName
            if let idx = seen[key] {
                groups[idx].ports.append(port)
            } else {
                seen[key] = groups.count
                groups.append((project: key, ports: [port]))
            }
        }
        return groups
    }

    @objc private func refreshAction() {
        viewModel.refresh()
        rebuildMenu()
    }

    @objc private func quitAction() {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Custom menu item view

class PortMenuItemView: NSView {
    private var trackingArea: NSTrackingArea?
    private var isHighlighted = false

    private let portLabel: NSTextField
    private let nameLabel: NSTextField
    private let memoryLabel: NSTextField
    private let uptimeLabel: NSTextField
    private let killButton: NSButton
    private let onKill: () -> Void

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
        let rightPad: CGFloat = 14
        let killSize: CGFloat = 18

        // Kill button (right edge, hidden until hover)
        let iconConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        killButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Kill")?
            .withSymbolConfiguration(iconConfig)
        killButton.bezelStyle = .inline
        killButton.isBordered = false
        killButton.imagePosition = .imageOnly
        killButton.contentTintColor = .secondaryLabelColor
        killButton.frame = NSRect(x: width - rightPad - killSize, y: 2, width: killSize, height: killSize)
        killButton.target = self
        killButton.action = #selector(killClicked)
        killButton.isHidden = true
        addSubview(killButton)

        // Memory (right-aligned, shifts left when kill button visible)
        let memWidth: CGFloat = 50
        let memX = width - rightPad - memWidth
        memoryLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        memoryLabel.textColor = .tertiaryLabelColor
        memoryLabel.alignment = .right
        memoryLabel.frame = NSRect(x: memX, y: 3, width: memWidth, height: 16)
        addSubview(memoryLabel)

        // Uptime
        let uptimeWidth: CGFloat = 50
        let uptimeX = memX - uptimeWidth - 4
        uptimeLabel.font = .systemFont(ofSize: 11)
        uptimeLabel.textColor = .tertiaryLabelColor
        uptimeLabel.alignment = .right
        uptimeLabel.frame = NSRect(x: uptimeX, y: 3, width: uptimeWidth, height: 16)
        addSubview(uptimeLabel)

        // Port number
        portLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        portLabel.textColor = .labelColor
        portLabel.sizeToFit()
        portLabel.frame.origin = NSPoint(x: leftPad, y: 2)
        addSubview(portLabel)

        // Name (fills between port and uptime)
        let nameX = leftPad + portLabel.frame.width + 8
        nameLabel.font = .systemFont(ofSize: 13)
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.frame = NSRect(x: nameX, y: 2, width: uptimeX - nameX - 4, height: 18)
        addSubview(nameLabel)
    }

    @objc private func killClicked() {
        guard let menu = enclosingMenuItem?.menu else { return }
        menu.cancelTracking()
        onKill()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        isHighlighted = true
        needsDisplay = true
        killButton.isHidden = false
        killButton.contentTintColor = .white
        // Shift memory left to make room for kill button
        memoryLabel.frame.origin.x = killButton.frame.minX - memoryLabel.frame.width - 6
        portLabel.textColor = .white
        nameLabel.textColor = .white
        uptimeLabel.textColor = .white.withAlphaComponent(0.5)
        memoryLabel.textColor = .white.withAlphaComponent(0.5)
    }

    override func mouseExited(with event: NSEvent) {
        isHighlighted = false
        needsDisplay = true
        killButton.isHidden = true
        // Reset memory position
        memoryLabel.frame.origin.x = bounds.width - 14 - memoryLabel.frame.width
        portLabel.textColor = .labelColor
        nameLabel.textColor = .labelColor
        uptimeLabel.textColor = .tertiaryLabelColor
        memoryLabel.textColor = .tertiaryLabelColor
    }

    override func mouseUp(with event: NSEvent) {
        // Row click does nothing — only kill button kills
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHighlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 0), xRadius: 4, yRadius: 4).fill()
        }
    }
}
