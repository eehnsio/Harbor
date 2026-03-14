import Foundation

enum ProcessManager {

    enum KillResult {
        case success
        case needsEscalation
        case failed(String)
    }

    /// Send SIGTERM to a process
    static func terminate(pid: pid_t) -> KillResult {
        let result = kill(pid, SIGTERM)
        if result == 0 {
            return .success
        }
        if errno == EPERM {
            return .needsEscalation
        }
        return .failed(String(cString: strerror(errno)))
    }

    /// Send SIGKILL to a process (force kill)
    static func forceKill(pid: pid_t) -> KillResult {
        let result = kill(pid, SIGKILL)
        if result == 0 {
            return .success
        }
        if errno == EPERM {
            return .needsEscalation
        }
        return .failed(String(cString: strerror(errno)))
    }

    /// Kill a process with elevated privileges using AppleScript
    static func terminateWithPrivileges(pid: pid_t, force: Bool = false) -> KillResult {
        let signal = force ? "9" : "15"
        let script = """
            do shell script "kill -\(signal) \(pid)" with administrator privileges
            """
        guard let appleScript = NSAppleScript(source: script) else {
            return .failed("Failed to create AppleScript")
        }
        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)
        if let error = error {
            let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            return .failed(message)
        }
        return .success
    }

    /// Check if a process is still running
    static func isRunning(pid: pid_t) -> Bool {
        kill(pid, 0) == 0
    }
}
