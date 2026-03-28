import Foundation

enum ProcessManager {

    enum KillResult {
        case success
        case needsEscalation
        case failed(String)
    }

    static func terminate(pid: pid_t) -> KillResult {
        let result = kill(pid, SIGTERM)
        if result == 0 { return .success }
        if errno == EPERM { return .needsEscalation }
        return .failed(String(cString: strerror(errno)))
    }

    static func forceKill(pid: pid_t) -> KillResult {
        let result = kill(pid, SIGKILL)
        if result == 0 { return .success }
        if errno == EPERM { return .needsEscalation }
        return .failed(String(cString: strerror(errno)))
    }

    static func forceKillWithPrivileges(pid: pid_t) -> KillResult {
        let script = "do shell script \"kill -9 \(pid)\" with administrator privileges"
        guard let appleScript = NSAppleScript(source: script) else {
            return .failed("Failed to create AppleScript")
        }
        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)
        if let error = error {
            return .failed(error[NSAppleScript.errorMessage] as? String ?? "Unknown error")
        }
        return .success
    }

    static func terminateWithPrivileges(pid: pid_t) -> KillResult {
        let script = "do shell script \"kill -15 \(pid)\" with administrator privileges"
        guard let appleScript = NSAppleScript(source: script) else {
            return .failed("Failed to create AppleScript")
        }
        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)
        if let error = error {
            return .failed(error[NSAppleScript.errorMessage] as? String ?? "Unknown error")
        }
        return .success
    }
}
