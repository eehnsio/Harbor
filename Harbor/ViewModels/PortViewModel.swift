import Foundation

@MainActor
class PortViewModel {
    private(set) var ports: [ListeningPort] = []

    func refresh() {
        ports = PortScanner.scan()
    }

    func killProcess(_ port: ListeningPort) {
        let result = ProcessManager.terminate(pid: port.pid)
        if case .needsEscalation = result {
            _ = ProcessManager.terminateWithPrivileges(pid: port.pid)
        }
    }
}
