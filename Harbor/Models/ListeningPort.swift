import Foundation

struct ListeningPort: Identifiable, Hashable {
    let id: String
    let port: UInt16
    let pid: pid_t
    let processName: String
    let displayName: String       // Friendly name: "next dev", "vite", "postgres", container name, etc.
    let processPath: String
    let workingDirectory: String
    let uptime: TimeInterval
    let physicalMemory: UInt64
    let isCurrentUser: Bool
    let localAddress: String
    let isDockerProxy: Bool

    init(port: UInt16, pid: pid_t, processName: String, displayName: String? = nil,
         processPath: String = "", workingDirectory: String = "",
         uptime: TimeInterval = 0, physicalMemory: UInt64 = 0,
         isCurrentUser: Bool = true, localAddress: String = "*", isDockerProxy: Bool = false) {
        self.id = "\(pid):\(port)"
        self.port = port
        self.pid = pid
        self.processName = processName
        self.displayName = displayName ?? processName
        self.processPath = processPath
        self.workingDirectory = workingDirectory
        self.uptime = uptime
        self.physicalMemory = physicalMemory
        self.isCurrentUser = isCurrentUser
        self.localAddress = localAddress
        self.isDockerProxy = isDockerProxy
    }

    /// Project name extracted from displayName ("walle / vite" → "walle")
    var projectName: String {
        if let slashRange = displayName.range(of: " / ") {
            return String(displayName[displayName.startIndex..<slashRange.lowerBound])
        }
        return ""
    }

    /// Short name without project prefix ("walle / vite" → "vite")
    var shortName: String {
        if let slashRange = displayName.range(of: " / ") {
            return String(displayName[slashRange.upperBound...])
        }
        return displayName
    }

    /// Is this likely a dev server port?
    var isDevPort: Bool {
        // Exclude known desktop apps that listen on ports in dev ranges
        let excludedProcesses: Set<String> = [
            "Discord", "Discord Helper", "Spotify", "Slack", "Slack Helper",
            "Google Chrome", "Google Chrome Helper", "firefox", "Safari",
            "zoom.us", "Microsoft Teams", "Figma", "Figma Helper",
            "Creative Cloud", "Adobe", "Dropbox", "1Password",
            "mDNSResponder", "rapportd", "sharingd", "airplayd",
            "launchd", "httpd", "bluetoothd", "WiFiAgent",
            "ControlCenter", "SystemUIServer", "loginwindow",
        ]
        // Also check by path for Electron helper processes
        let excludedPathParts = ["/Discord.app/", "/Spotify.app/", "/Slack.app/",
                                  "/Figma.app/", "/zoom.us.app/", "/Microsoft Teams",
                                  "/Google Chrome.app/", "/Firefox.app/"]
        if excludedProcesses.contains(processName) { return false }
        if excludedPathParts.contains(where: { processPath.contains($0) }) { return false }

        // Docker proxy is always interesting
        if isDockerProxy { return true }

        // Known dev process names
        let devProcesses: Set<String> = ["node", "npm", "npx", "bun", "deno", "ruby", "python", "python3",
                                          "java", "beam.smp", "mix", "cargo", "go", "php", "docker-proxy"]
        if devProcesses.contains(processName) { return true }

        // Common dev server port ranges
        let devRanges: [ClosedRange<UInt16>] = [
            3000...3999,   // React, Next.js, Express, Rails
            4000...4999,   // Astro (4321), Phoenix, etc.
            5000...5999,   // Vite (5173), Flask, etc.
            8000...8999,   // Python http.server, Django, etc.
            9000...9999,
        ]
        // Only match port ranges if the process isn't a known desktop app
        if devRanges.contains(where: { $0.contains(port) }) {
            return true
        }

        return false
    }
}
