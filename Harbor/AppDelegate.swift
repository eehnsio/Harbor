import AppKit
import ServiceManagement

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
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
        default:
            break
        }

        let aboutItem = NSMenuItem(title: "About Harbor", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "Quit Harbor", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func makePortItem(port: ListeningPort) -> NSMenuItem {
        let title = "\(port.port) · \(port.shortName)"
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")

        let submenu = NSMenu()

        // PID info (disabled, just for display)
        let pidItem = NSMenuItem(title: "PID \(port.pid)", action: nil, keyEquivalent: "")
        pidItem.isEnabled = false
        submenu.addItem(pidItem)

        // Uptime & memory info
        let infoItem = NSMenuItem(
            title: "\(Formatters.uptime(port.uptime))  ·  \(Formatters.memory(port.physicalMemory))",
            action: nil, keyEquivalent: ""
        )
        infoItem.isEnabled = false
        submenu.addItem(infoItem)

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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refreshAndRebuild()
        }
    }

    @objc private func forceKillProcess(_ sender: NSMenuItem) {
        guard let port = sender.representedObject as? ListeningPort else { return }
        viewModel.forceKillProcess(port)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refreshAndRebuild()
        }
    }

    @objc private func showAbout() { AboutWindow.show() }

    @objc private func toggleShowAllPorts() {
        showAllPorts.toggle()
        refreshAndRebuild()
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


