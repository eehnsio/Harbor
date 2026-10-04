import Foundation
import Darwin

struct ProcessDetails {
    let name: String
    let displayName: String
    let path: String
    let workingDirectory: String
    let uptime: TimeInterval
    let memory: UInt64
    let uid: uid_t
    let isDockerProxy: Bool
    /// App the process was started from (e.g. "Ghostty", "Claude", "Code"), via the parent chain
    let parentApp: String?
    /// No app or terminal multiplexer up the parent chain — usually a dev server left behind by a closed terminal
    let isOrphaned: Bool
}

enum ProcessInspector {

    static func inspect(pid: pid_t) -> ProcessDetails {
        let name = getProcessName(pid: pid)
        let path = getProcessPath(pid: pid)
        let cwd = getWorkingDirectory(pid: pid)
        let bsdInfo = getBSDInfo(pid: pid)
        let memory = getMemory(pid: pid)
        let args = getCommandLineArgs(pid: pid)
        let isDocker = name == "com.docker.backend" || name == "docker-proxy" || name == "vpnkit-bridge"

        let ppid = pid_t(bsdInfo?.pbi_ppid ?? 0)
        let origin = isDocker ? (app: nil, detached: false) : findOrigin(ppid: ppid)
        let startTime = TimeInterval(bsdInfo?.pbi_start_tvsec ?? 0)
        let uptime = startTime > 0 ? Date().timeIntervalSince1970 - startTime : 0

        return ProcessDetails(
            name: name,
            displayName: resolveDisplayName(name: name, path: path, cwd: cwd, args: args),
            path: path,
            workingDirectory: cwd,
            uptime: uptime,
            memory: memory,
            uid: bsdInfo?.pbi_uid ?? 0,
            isDockerProxy: isDocker,
            parentApp: origin.app,
            isOrphaned: origin.detached
        )
    }

    // MARK: - Parent chain

    /// Ancestors that keep a session alive even though their own parent is launchd.
    private static let sessionHosts: Set<String> = ["tmux", "screen", "zellij", "sshd", "login", "mosh-server"]

    /// Walk up the parent chain. The outermost ancestor inside an .app bundle is the origin
    /// ("Ghostty", "Claude", "Visual Studio Code") — apps nest helper bundles, so keep walking.
    /// Reaching launchd without one means the terminal that started it is gone — unless the
    /// top of the chain is a multiplexer or ssh session.
    private static func findOrigin(ppid: pid_t) -> (app: String?, detached: Bool) {
        var current = ppid
        var topmost: pid_t?
        var appPath: String?
        for _ in 0..<32 where current > 1 {
            let path = getProcessPath(pid: current)
            if let range = path.range(of: ".app/") {
                appPath = String(path[..<range.lowerBound]) + ".app"
            }
            guard let info = getBSDInfo(pid: current) else { break }
            topmost = current
            current = pid_t(info.pbi_ppid)
        }
        if let appPath { return (appDisplayName(appPath), false) }
        guard current == 1 else { return (nil, false) }
        guard let topmost else { return (nil, true) }  // Parent is launchd itself
        return (nil, !sessionHosts.contains(getProcessName(pid: topmost)))
    }

    private static func appDisplayName(_ appPath: String) -> String {
        let bundle = Bundle(path: appPath)
        return bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? URL(fileURLWithPath: appPath).deletingPathExtension().lastPathComponent
    }

    // MARK: - Display name resolution

    private static func resolveDisplayName(name: String, path: String, cwd: String, args: [String]) -> String {
        if name == "com.docker.backend" || name == "docker-proxy" || name == "vpnkit-bridge" {
            return "docker"
        }

        let baseName: String
        if name == "node" || name == "bun" || name == "deno" {
            baseName = resolveNodeName(runtime: name, args: args)
        } else if name == "python" || name == "python3" || name.hasPrefix("Python") {
            baseName = resolvePythonName(args: args)
        } else if name == "java" {
            baseName = resolveJavaName(args: args)
        } else if name == "unknown" && !path.isEmpty {
            baseName = URL(fileURLWithPath: path).lastPathComponent
        } else {
            baseName = name
        }

        if let project = extractProjectName(from: cwd), project.lowercased() != baseName.lowercased() {
            return "\(project) / \(baseName)"
        }
        return baseName
    }

    private static func extractProjectName(from cwd: String) -> String? {
        guard !cwd.isEmpty else { return nil }
        let skip: Set<String> = ["/", "Users", "home", "Desktop", "Documents", "Developer",
                                  "Projects", "Code", "dev", "src", "workspace", "repos",
                                  "git", "tmp", "var", "opt", "private", "Applications"]
        let username = NSUserName()

        for component in URL(fileURLWithPath: cwd).pathComponents.reversed() {
            if skip.contains(component) || component == username || component.hasPrefix(".") { continue }
            return component
        }
        return nil
    }

    /// Known CLI packages/binaries → display name. Matched exactly against the npm package
    /// name or script basename, never as a substring of the full path.
    private static let nodeFrameworks: [String: String] = [
        "next": "next dev", "vite": "vite", "vitest": "vitest",
        "nuxt": "nuxt dev", "nuxi": "nuxt dev", "astro": "astro dev",
        "@remix-run/dev": "remix dev", "remix": "remix dev",
        "webpack": "webpack", "webpack-dev-server": "webpack", "webpack-cli": "webpack",
        "turbo": "turbo", "@nestjs/cli": "nest", "nest": "nest",
        "fastify-cli": "fastify", "gatsby": "gatsby",
        "storybook": "storybook", "@storybook/cli": "storybook",
        "wrangler": "wrangler", "expo": "expo", "react-scripts": "react-scripts",
    ]

    private static func resolveNodeName(runtime: String, args: [String]) -> String {
        let relevantArgs = args.dropFirst().filter { !$0.hasPrefix("-") }

        for arg in relevantArgs {
            let lower = arg.lowercased()
            let package = nodePackageName(in: lower)
            let scriptName = URL(fileURLWithPath: lower).deletingPathExtension().lastPathComponent

            if let package, let name = nodeFrameworks[package] { return name }
            if let name = nodeFrameworks[scriptName] { return name }
            // Script inside node_modules → the package is more telling than "cli.js"
            if let package { return package }
            if lower.hasSuffix(".js") || lower.hasSuffix(".ts") || lower.hasSuffix(".mjs") || lower.hasSuffix(".cjs") {
                return "\(runtime) \(URL(fileURLWithPath: arg).lastPathComponent)"
            }
        }

        if let first = relevantArgs.first {
            let basename = URL(fileURLWithPath: first).lastPathComponent
            if !basename.isEmpty && basename != runtime { return basename }
        }
        return runtime
    }

    /// ".../node_modules/wrangler/bin/cli.js" → "wrangler", ".../node_modules/@nestjs/cli/..." → "@nestjs/cli"
    private static func nodePackageName(in path: String) -> String? {
        guard let range = path.range(of: "/node_modules/", options: .backwards) else { return nil }
        let parts = path[range.upperBound...].split(separator: "/")
        guard let first = parts.first else { return nil }
        if first.hasPrefix("@"), parts.count > 1 { return "\(first)/\(parts[1])" }
        // ".bin/vite" is a symlink named after the binary
        if first == ".bin", parts.count > 1 { return String(parts[1]) }
        return String(first)
    }

    private static func resolvePythonName(args: [String]) -> String {
        if let mIdx = args.firstIndex(of: "-m"), mIdx + 1 < args.count {
            let module = args[mIdx + 1]
            if module == "http.server" { return "python http" }
            return "python -m \(module)"
        }
        let relevantArgs = args.dropFirst().filter { !$0.hasPrefix("-") }
        for arg in relevantArgs {
            // Match on basename only so a project folder named e.g. "flask-demo" isn't misread
            let basename = URL(fileURLWithPath: arg).lastPathComponent
            switch basename.lowercased() {
            case "manage.py": return "django"
            case "flask", "uvicorn", "gunicorn", "hypercorn", "daphne": return basename.lowercased()
            default: break
            }
            if basename.lowercased().hasSuffix(".py") { return "python \(basename)" }
        }
        return "python"
    }

    private static func resolveJavaName(args: [String]) -> String {
        for arg in args.dropFirst() where !arg.hasPrefix("-") {
            let basename = URL(fileURLWithPath: arg).lastPathComponent
            if basename.hasSuffix(".jar") { return basename }
            if arg.contains("."), let last = arg.split(separator: ".").last { return String(last) }
            return basename
        }
        return "java"
    }

    // MARK: - Process info via libproc

    private static func getProcessName(pid: pid_t) -> String {
        var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        return proc_name(pid, &buf, UInt32(MAXPATHLEN)) > 0 ? String(cString: buf) : "unknown"
    }

    private static func getProcessPath(pid: pid_t) -> String {
        var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        return proc_pidpath(pid, &buf, UInt32(MAXPATHLEN)) > 0 ? String(cString: buf) : ""
    }

    private static func getWorkingDirectory(pid: pid_t) -> String {
        var info = proc_vnodepathinfo()
        let size = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, Int32(MemoryLayout<proc_vnodepathinfo>.size))
        guard size == MemoryLayout<proc_vnodepathinfo>.size else { return "" }
        return withUnsafePointer(to: info.pvi_cdir.vip_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
    }

    private static func getBSDInfo(pid: pid_t) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
        return size == MemoryLayout<proc_bsdinfo>.size ? info : nil
    }

    private static func getMemory(pid: pid_t) -> UInt64 {
        var usage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &usage) { ptr in
            ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        }
        return result == 0 ? usage.ri_phys_footprint : 0
    }

    private static func getCommandLineArgs(pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size: Int = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return [] }

        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }

        let argc = buffer.withUnsafeBufferPointer { buf in
            buf.baseAddress!.withMemoryRebound(to: Int32.self, capacity: 1) { $0.pointee }
        }

        var offset = MemoryLayout<Int32>.size
        while offset < size && buffer[offset] != 0 { offset += 1 }
        while offset < size && buffer[offset] == 0 { offset += 1 }

        var args: [String] = []
        for _ in 0..<argc {
            guard offset < size else { break }
            var end = offset
            while end < size && buffer[end] != 0 { end += 1 }
            if end > offset, let arg = String(data: Data(buffer[offset..<end]), encoding: .utf8) {
                args.append(arg)
            }
            offset = end + 1
        }
        return args
    }
}
