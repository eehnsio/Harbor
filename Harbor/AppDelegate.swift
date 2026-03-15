import AppKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let viewModel = PortViewModel()
    private let menuWidth: CGFloat = 290
    private var showAllPorts = false
    private var updateStatus: UpdateStatus = .idle

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "network", accessibilityDescription: "Harbor")

        refreshAndRebuild()

        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshAndRebuild() }
        }

        // Check for updates on launch, then every hour
        checkForUpdates()
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkForUpdates() }
        }
    }

    private func checkForUpdates() {
        updateStatus = .checking
        rebuildMenu()
        Task {
            let status = await UpdateChecker.check()
            updateStatus = status
            rebuildMenu()
        }
    }

    private func refreshAndRebuild() {
        viewModel.refresh(showAll: showAllPorts)
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.minimumWidth = menuWidth
        let devPorts = viewModel.ports.filter { $0.isDevPort }

        // Compute max port label width so all columns align
        let portFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        let maxPortWidth = devPorts.reduce(CGFloat(0)) { maxW, p in
            let w = (String(p.port) as NSString).size(withAttributes: [.font: portFont]).width
            return max(maxW, w)
        }

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
                    menu.addItem(makePortItem(port: port, portColumnWidth: maxPortWidth))
                }

                if index < sortedGroups.count - 1 {
                    menu.addItem(.separator())
                }
            }
        }

        menu.addItem(.separator())

        let showAllItem = NSMenuItem(title: "Show All Ports", action: #selector(toggleShowAllPorts), keyEquivalent: "")
        showAllItem.target = self
        showAllItem.state = showAllPorts ? .on : .off
        menu.addItem(showAllItem)

        // Update / version row (NSView-based so clicks don't close menu)
        let updateTitle: String
        let updateClickable: Bool
        switch updateStatus {
        case .available(let version, _):
            updateTitle = "Update available (v\(version))"
            updateClickable = true
        case .downloading(let progress):
            updateTitle = "Downloading update... \(Int(progress * 100))%"
            updateClickable = false
        case .installing:
            updateTitle = "Installing update..."
            updateClickable = false
        case .failed:
            updateTitle = "Update failed — Retry"
            updateClickable = true
        case .checking:
            updateTitle = "Checking for updates..."
            updateClickable = false
        default:
            updateTitle = "Check for updates"
            updateClickable = true
        }
        let updateItem = NSMenuItem()
        updateItem.view = UpdateMenuItemView(
            title: updateTitle,
            clickable: updateClickable,
            width: menuWidth
        ) { [weak self] in
            guard let self else { return }
            if case .available = self.updateStatus {
                self.performUpdate()
            } else if case .failed = self.updateStatus {
                self.performUpdate()
            } else {
                self.checkForUpdates()
            }
        }
        menu.addItem(updateItem)

        let quitItem = NSMenuItem(title: "Quit Harbor", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func makePortItem(port: ListeningPort, portColumnWidth: CGFloat) -> NSMenuItem {
        let item = NSMenuItem()
        item.representedObject = port.pid
        item.view = PortMenuItemView(
            port: String(port.port),
            portColumnWidth: portColumnWidth,
            name: port.shortName,
            memory: Formatters.memory(port.physicalMemory),
            uptime: Formatters.uptime(port.uptime),
            width: menuWidth,
            onClick: {
                let url = URL(string: "http://localhost:\(port.port)")!
                NSWorkspace.shared.open(url)
            },
            onKill: { [weak self] in
                self?.viewModel.killProcess(port)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self?.refreshAndRebuild()
                }
            }
        )
        return item
    }

    @objc private func checkForUpdatesAction(_ sender: NSMenuItem) {
        sender.title = "Checking for updates..."
        sender.action = nil
        Task {
            let status = await UpdateChecker.check()
            updateStatus = status
            if case .upToDate = status {
                sender.title = "Up to date"
                try? await Task.sleep(for: .seconds(2))
            }
            rebuildMenu()
        }
    }

    @objc private func toggleShowAllPorts() {
        showAllPorts.toggle()
        refreshAndRebuild()
    }

    @objc private func performUpdate() {
        guard case .available(_, let url) = updateStatus else {
            // Retry: re-check first
            checkForUpdates()
            return
        }
        updateStatus = .downloading(progress: 0)
        rebuildMenu()

        Task {
            do {
                try await AppUpdater.update(from: url) { [weak self] progress in
                    Task { @MainActor in
                        self?.updateStatus = .downloading(progress: progress)
                        self?.rebuildMenu()
                    }
                }
            } catch {
                updateStatus = .failed(error.localizedDescription)
                rebuildMenu()
            }
        }
    }

    @objc private func quitAction() { NSApplication.shared.terminate(nil) }
}

// MARK: - Custom menu item view

class PortMenuItemView: NSView {
    private var trackingArea: NSTrackingArea?
    private var isHighlighted = false
    private let onClick: () -> Void
    private let onKill: () -> Void

    private let portLabel: NSTextField
    private let nameLabel: NSTextField
    private let memoryLabel: NSTextField
    private let uptimeLabel: NSTextField
    private let killButton: NSButton

    private let rightPad: CGFloat = 14

    private let portColumnWidth: CGFloat

    init(port: String, portColumnWidth: CGFloat = 40, name: String, memory: String, uptime: String, width: CGFloat,
         onClick: @escaping () -> Void = {}, onKill: @escaping () -> Void) {
        self.portColumnWidth = portColumnWidth
        self.onClick = onClick
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

        // Port number — right-aligned within shared column width
        portLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        portLabel.textColor = .labelColor
        portLabel.alignment = .right
        portLabel.frame = NSRect(x: leftPad, y: 2, width: portColumnWidth, height: 18)
        addSubview(portLabel)

        // Name — fixed start position based on shared column width
        let nameX = leftPad + portColumnWidth + 8
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

    override func mouseUp(with event: NSEvent) {
        enclosingMenuItem?.menu?.cancelTracking()
        onClick()
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHighlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 0), xRadius: 4, yRadius: 4).fill()
        }
    }
}

// MARK: - Update menu item view (doesn't close menu on click)

class UpdateMenuItemView: NSView {
    private var trackingArea: NSTrackingArea?
    private var isHighlighted = false
    private let label: NSTextField
    private let onClick: () -> Void
    private let clickable: Bool

    init(title: String, clickable: Bool, width: CGFloat, onClick: @escaping () -> Void) {
        self.onClick = onClick
        self.clickable = clickable
        label = NSTextField(labelWithString: title)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 22))

        label.font = .systemFont(ofSize: 13)
        label.textColor = clickable ? .labelColor : .tertiaryLabelColor
        label.frame = NSRect(x: 20, y: 2, width: width - 40, height: 18)
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        guard clickable else { return }
        isHighlighted = true
        label.textColor = .white
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHighlighted = false
        label.textColor = clickable ? .labelColor : .tertiaryLabelColor
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard clickable else { return }
        // Don't call cancelTracking — keeps menu open
        label.stringValue = "Checking for updates..."
        label.textColor = .tertiaryLabelColor
        isHighlighted = false
        needsDisplay = true
        onClick()
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHighlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 0), xRadius: 4, yRadius: 4).fill()
        }
    }
}
