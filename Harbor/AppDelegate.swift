import AppKit
import ServiceManagement

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let viewModel = PortViewModel()
    private var showAllPorts = false
    private var updateStatus: UpdateStatus = .idle

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let icon = Bundle.main.image(forResource: "harbor-menubar") {
            icon.size = NSSize(width: 18, height: 18)
            icon.isTemplate = true
            statusItem.button?.image = icon
        }

        // Ports are scanned when the menu opens (menuNeedsUpdate) — nothing polls in the background
        menu.delegate = self
        statusItem.menu = menu

        // Check for updates on launch, then every hour
        checkForUpdates()
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkForUpdates() }
        }
    }

    private func checkForUpdates() {
        Task {
            let status = await UpdateChecker.check()
            // A failed check (offline, rate limited) shouldn't hide an update we already found
            if case .failed = status { return }
            // Don't interrupt a download in progress
            if case .downloading = updateStatus { return }
            if updateStatus == .installing { return }
            updateStatus = status
            rebuildMenu()
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        viewModel.refresh(showAll: showAllPorts)
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        let devPorts = viewModel.ports.filter { $0.isDevPort }

        if devPorts.isEmpty {
            let item = NSMenuItem(title: "No dev ports", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            let grouped = Dictionary(grouping: devPorts) { port in
                port.projectName.isEmpty ? port.displayName : port.projectName
            }
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

        let showAllItem = NSMenuItem(title: "Show All Ports", action: #selector(toggleShowAllPorts), keyEquivalent: "")
        showAllItem.target = self
        showAllItem.state = showAllPorts ? .on : .off
        menu.addItem(showAllItem)

        let launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.target = self
        launchAtLoginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(launchAtLoginItem)

        // Only show update item when an update is available or in progress
        switch updateStatus {
        case .available(let version, _):
            let item = NSMenuItem(title: "Update available (v\(version))", action: #selector(performUpdate), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        case .downloading(let progress):
            let item = NSMenuItem(title: "Downloading... \(Int(progress * 100))%", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        case .installing:
            let item = NSMenuItem(title: "Installing...", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        case .failed(let message):
            let item = NSMenuItem(title: "Update failed — Retry", action: #selector(performUpdate), keyEquivalent: "")
            item.target = self
            item.toolTip = message
            menu.addItem(item)
        default:
            break
        }

        let aboutItem = NSMenuItem(title: "About Harbor", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "Quit Harbor", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func makePortItem(port: ListeningPort) -> NSMenuItem {
        let title = "\(port.port) · \(port.shortName)"
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.attributedTitle = portTitle(title, port: port)
        if port.isOrphaned {
            item.toolTip = "Detached — running without a terminal"
        }

        let submenu = NSMenu()

        // PID info (disabled, just for display)
        let pidItem = NSMenuItem(title: "PID \(port.pid)", action: nil, keyEquivalent: "")
        pidItem.isEnabled = false
        submenu.addItem(pidItem)

        // Uptime & memory info (Docker's backend process says nothing about the container)
        if !port.isDockerProxy {
            let infoItem = NSMenuItem(
                title: "\(Formatters.uptime(port.uptime))  ·  \(Formatters.memory(port.physicalMemory))",
                action: nil, keyEquivalent: ""
            )
            infoItem.isEnabled = false
            submenu.addItem(infoItem)
        }

        // Where it was started from — helps tell apart sessions and spot leftovers
        let originTitle: String? = if port.isOrphaned {
            "Detached"
        } else if let app = port.parentApp {
            "Started from \(app)"
        } else {
            nil
        }
        if let originTitle {
            let originItem = NSMenuItem(title: originTitle, action: nil, keyEquivalent: "")
            originItem.isEnabled = false
            submenu.addItem(originItem)
        }

        submenu.addItem(.separator())

        // Copy URL
        let copyItem = NSMenuItem(title: "Copy URL", action: #selector(copyURL(_:)), keyEquivalent: "")
        copyItem.target = self
        copyItem.representedObject = port
        submenu.addItem(copyItem)

        // Open in Browser
        let openItem = NSMenuItem(title: "Open in Browser", action: #selector(openInBrowser(_:)), keyEquivalent: "")
        openItem.target = self
        openItem.representedObject = port
        submenu.addItem(openItem)

        submenu.addItem(.separator())

        // Terminate Process
        let terminateItem = NSMenuItem(title: "Terminate Process", action: #selector(terminateProcess(_:)), keyEquivalent: "")
        terminateItem.target = self
        terminateItem.representedObject = port
        submenu.addItem(terminateItem)

        // Force Kill Process
        let forceKillItem = NSMenuItem(title: "Force Kill Process", action: #selector(forceKillProcess(_:)), keyEquivalent: "")
        forceKillItem.target = self
        forceKillItem.representedObject = port
        submenu.addItem(forceKillItem)

        item.submenu = submenu
        return item
    }

    /// "4331 · astro dev", plus a small gray dot when the server runs without a terminal.
    /// Uptime and the explanation live in the submenu so the menu stays narrow.
    private func portTitle(_ title: String, port: ListeningPort) -> NSAttributedString {
        let result = NSMutableAttributedString(string: title, attributes: [.font: NSFont.menuFont(ofSize: 0)])
        guard port.isOrphaned else { return result }
        result.append(NSAttributedString(string: "  ●", attributes: [
            .font: NSFont.menuFont(ofSize: 8),
            .foregroundColor: NSColor.tertiaryLabelColor,
            .baselineOffset: 2,
        ]))
        return result
    }

    @objc private func copyURL(_ sender: NSMenuItem) {
        guard let port = sender.representedObject as? ListeningPort else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("http://localhost:\(port.port)", forType: .string)
    }

    @objc private func openInBrowser(_ sender: NSMenuItem) {
        guard let port = sender.representedObject as? ListeningPort else { return }
        let url = URL(string: "http://localhost:\(port.port)")!
        NSWorkspace.shared.open(url)
    }

    @objc private func terminateProcess(_ sender: NSMenuItem) {
        guard let port = sender.representedObject as? ListeningPort else { return }
        viewModel.killProcess(port)
    }

    @objc private func forceKillProcess(_ sender: NSMenuItem) {
        guard let port = sender.representedObject as? ListeningPort else { return }
        viewModel.forceKillProcess(port)
    }

    @objc private func showAbout() { AboutWindow.show() }

    @objc private func toggleShowAllPorts() {
        showAllPorts.toggle()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Failed to toggle launch at login: \(error)")
        }
        rebuildMenu()
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
                        self?.updateStatus = progress >= 1 ? .installing : .downloading(progress: progress)
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


