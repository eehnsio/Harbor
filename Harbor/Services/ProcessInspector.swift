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
}

enum ProcessInspector {

    static func inspect(pid: pid_t) -> ProcessDetails {
        let name = getProcessName(pid: pid)
        let path = getProcessPath(pid: pid)
        let cwd = getWorkingDirectory(pid: pid)
        let uptime = getUptime(pid: pid)
        let memory = getMemory(pid: pid)
        let uid = getUID(pid: pid)
        let args = getCommandLineArgs(pid: pid)
        let isDocker = name == "com.docker.backend" || name == "docker-proxy" || name == "vpnkit-bridge"
        let displayName = resolveDisplayName(name: name, path: path, cwd: cwd, args: args)

        return ProcessDetails(
            name: name,
            displayName: displayName,
            path: path,
            workingDirectory: cwd,
            uptime: uptime,
            memory: memory,
            uid: uid,
            isDockerProxy: isDocker
        )
    }

    /// Build a human-friendly display name from the process info.
    private static func resolveDisplayName(name: String, path: String, cwd: String, args: [String]) -> String {
        // Docker proxy — try to get container name
        if name == "com.docker.backend" || name == "docker-proxy" || name == "vpnkit-bridge" {
            if let containerName = resolveDockerContainer(args: args) {
                return containerName
            }
            return "docker"
        }

        let baseName: String

        // Node.js — show the script or framework being run
        if name == "node" || name == "bun" || name == "deno" {
            baseName = resolveNodeDisplayName(runtime: name, args: args)
        } else if name == "python" || name == "python3" || name.hasPrefix("Python") {
            baseName = resolvePythonDisplayName(args: args)
        } else if name == "java" {
            baseName = resolveJavaDisplayName(args: args)
        } else if name == "unknown" && !path.isEmpty {
            baseName = URL(fileURLWithPath: path).lastPathComponent
        } else {
            baseName = name
        }

        // Prefix with project folder name from cwd
        let projectName = extractProjectName(from: cwd)
        if let projectName, projectName.lowercased() != baseName.lowercased() {
            return "\(projectName) / \(baseName)"
        }

        return baseName
    }

    /// Extract a meaningful project folder name from the working directory.
    /// Skips generic dirs like home, Desktop, Developer, etc.
    private static func extractProjectName(from cwd: String) -> String? {
        guard !cwd.isEmpty else { return nil }

        let url = URL(fileURLWithPath: cwd)
        let components = url.pathComponents

        // Walk from the end, skip generic folder names
        let genericDirs: Set<String> = ["/", "Users", "home", "Desktop", "Documents",
                                         "Developer", "Projects", "Code", "dev", "src",
                                         "workspace", "repos", "git", "tmp", "var", "opt",
                                         "private", "Applications"]
        // Also skip the username component
        let username = NSUserName()

        for component in components.reversed() {
            if genericDirs.contains(component) { continue }
            if component == username { continue }
            if component.hasPrefix(".") { continue }
            // Found a meaningful name
            return component
        }

        return nil
    }

    private static func resolveNodeDisplayName(runtime: String, args: [String]) -> String {
        // Skip the binary itself, look at what comes after
        let relevantArgs = args.dropFirst().filter { !$0.hasPrefix("-") }

        for arg in relevantArgs {
            let lower = arg.lowercased()
            // Detect common frameworks from their CLI scripts
            if lower.contains("next") { return "next dev" }
            if lower.contains("vite") || lower.contains("vitest") { return "vite" }
            if lower.contains("nuxt") { return "nuxt dev" }
            if lower.contains("astro") { return "astro dev" }
            if lower.contains("remix") { return "remix dev" }
            if lower.contains("webpack") { return "webpack" }
            if lower.contains("turbo") { return "turbo" }
            if lower.contains("nest") { return "nest" }
            if lower.contains("express") { return "express" }
            if lower.contains("fastify") { return "fastify" }
            if lower.contains("svelte") || lower.contains("sveltekit") { return "sveltekit" }
            if lower.contains("gatsby") { return "gatsby" }
            if lower.contains("angular") || lower.contains("ng") && lower.contains("serve") { return "angular" }
            if lower.contains("storybook") { return "storybook" }

            // If it's a .js/.ts file, show just the filename
            if lower.hasSuffix(".js") || lower.hasSuffix(".ts") || lower.hasSuffix(".mjs") || lower.hasSuffix(".cjs") {
                return "\(runtime) \(URL(fileURLWithPath: arg).lastPathComponent)"
            }
        }

        // Check if run via npx/npm
        if let first = relevantArgs.first {
            let basename = URL(fileURLWithPath: first).lastPathComponent
            if !basename.isEmpty && basename != runtime {
                return basename
            }
        }

        return runtime
    }

    private static func resolvePythonDisplayName(args: [String]) -> String {
        let relevantArgs = args.dropFirst().filter { !$0.hasPrefix("-") }
        for arg in relevantArgs {
            let lower = arg.lowercased()
            if lower.contains("manage.py") { return "django" }
            if lower.contains("flask") { return "flask" }
            if lower.contains("uvicorn") { return "uvicorn" }
            if lower.contains("gunicorn") { return "gunicorn" }
            if lower.contains("http.server") { return "python http" }
            if lower.hasSuffix(".py") {
                return "python \(URL(fileURLWithPath: arg).lastPathComponent)"
            }
        }
        // Check for -m module
        if let mIdx = args.firstIndex(of: "-m"), mIdx + 1 < args.count {
            let module = args[mIdx + 1]
            if module == "http.server" { return "python http" }
            return "python -m \(module)"
        }
        return "python"
    }

    private static func resolveJavaDisplayName(args: [String]) -> String {
        for arg in args.dropFirst() {
            if arg.hasPrefix("-") { continue }
            let basename = URL(fileURLWithPath: arg).lastPathComponent
            if basename.hasSuffix(".jar") { return basename }
            // Main class name — take last component
            if arg.contains(".") {
                let parts = arg.split(separator: ".")
                if let last = parts.last { return String(last) }
            }
            return basename
        }
        return "java"
    }

    private static func resolveDockerContainer(args: [String]) -> String? {
        // docker-proxy args contain the port mapping but not container name
        // We need to use docker CLI to map the port
        // For now, just return "docker" — we'll enhance with docker inspect later
        return nil
    }

    // MARK: - Low-level process info

    private static func getWorkingDirectory(pid: pid_t) -> String {
        var vnodeInfo = proc_vnodepathinfo()
        let size = proc_pidinfo(
            pid, PROC_PIDVNODEPATHINFO, 0,
            &vnodeInfo, Int32(MemoryLayout<proc_vnodepathinfo>.size)
        )
        guard size == MemoryLayout<proc_vnodepathinfo>.size else { return "" }

        let path = withUnsafePointer(to: vnodeInfo.pvi_cdir.vip_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { cpath in
                String(cString: cpath)
            }
        }
        return path
    }

    private static func getProcessName(pid: pid_t) -> String {
        var nameBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let result = proc_name(pid, &nameBuffer, UInt32(MAXPATHLEN))
        guard result > 0 else { return "unknown" }
        return String(cString: nameBuffer)
    }

    private static func getProcessPath(pid: pid_t) -> String {
        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let result = proc_pidpath(pid, &pathBuffer, UInt32(MAXPATHLEN))
        guard result > 0 else { return "" }
        return String(cString: pathBuffer)
    }

    static func getCommandLineArgs(pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size: Int = 0

        // Get buffer size
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return [] }

        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return [] }

        // First 4 bytes = argc
        guard size > MemoryLayout<Int32>.size else { return [] }
        let argc = buffer.withUnsafeBufferPointer { buf in
            buf.baseAddress!.withMemoryRebound(to: Int32.self, capacity: 1) { $0.pointee }
        }

        // Skip argc (4 bytes), then the executable path (null-terminated), then padding nulls
        var offset = MemoryLayout<Int32>.size

        // Skip executable path
        while offset < size && buffer[offset] != 0 { offset += 1 }
        // Skip null terminators between exec path and args
        while offset < size && buffer[offset] == 0 { offset += 1 }

        // Now read argc arguments
        var args: [String] = []
        for _ in 0..<argc {
            guard offset < size else { break }
            var end = offset
            while end < size && buffer[end] != 0 { end += 1 }
            if end > offset {
                let argData = Data(buffer[offset..<end])
                if let arg = String(data: argData, encoding: .utf8) {
                    args.append(arg)
                }
            }
            offset = end + 1
        }

        return args
    }

    private static func getUptime(pid: pid_t) -> TimeInterval {
        var info = proc_bsdinfo()
        let size = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
        guard size == MemoryLayout<proc_bsdinfo>.size else { return 0 }

        let startTime = TimeInterval(info.pbi_start_tvsec)
        guard startTime > 0 else { return 0 }
        return Date().timeIntervalSince1970 - startTime
    }

    private static func getMemory(pid: pid_t) -> UInt64 {
        var usage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &usage) { ptr in
            ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rusagePtr in
                proc_pid_rusage(pid, RUSAGE_INFO_V4, rusagePtr)
            }
        }
        guard result == 0 else { return 0 }
        return usage.ri_phys_footprint
    }

    private static func getUID(pid: pid_t) -> uid_t {
        var info = proc_bsdinfo()
        let size = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
        guard size == MemoryLayout<proc_bsdinfo>.size else { return 0 }
        return info.pbi_uid
    }
}
