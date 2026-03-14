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
        let bsdInfo = getBSDInfo(pid: pid)
        let memory = getMemory(pid: pid)
        let args = getCommandLineArgs(pid: pid)
        let isDocker = name == "com.docker.backend" || name == "docker-proxy" || name == "vpnkit-bridge"

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
            isDockerProxy: isDocker
        )
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

    private static func resolveNodeName(runtime: String, args: [String]) -> String {
        let relevantArgs = args.dropFirst().filter { !$0.hasPrefix("-") }

        // Map known framework paths to display names
        let frameworks: [(pattern: String, name: String)] = [
            ("next", "next dev"), ("vite", "vite"), ("vitest", "vitest"),
            ("nuxt", "nuxt dev"), ("astro", "astro dev"), ("remix", "remix dev"),
            ("webpack", "webpack"), ("turbo", "turbo"), ("nest", "nest"),
            ("express", "express"), ("fastify", "fastify"),
            ("svelte", "sveltekit"), ("gatsby", "gatsby"), ("storybook", "storybook"),
        ]

        for arg in relevantArgs {
            let lower = arg.lowercased()
            if let match = frameworks.first(where: { lower.contains($0.pattern) }) {
                return match.name
            }
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

    private static func resolvePythonName(args: [String]) -> String {
        if let mIdx = args.firstIndex(of: "-m"), mIdx + 1 < args.count {
            let module = args[mIdx + 1]
            if module == "http.server" { return "python http" }
            return "python -m \(module)"
        }
        let relevantArgs = args.dropFirst().filter { !$0.hasPrefix("-") }
        for arg in relevantArgs {
            let lower = arg.lowercased()
            if lower.contains("manage.py") { return "django" }
            if lower.contains("flask") { return "flask" }
            if lower.contains("uvicorn") { return "uvicorn" }
            if lower.contains("gunicorn") { return "gunicorn" }
            if lower.hasSuffix(".py") { return "python \(URL(fileURLWithPath: arg).lastPathComponent)" }
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
