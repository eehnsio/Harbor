import Foundation

@MainActor
class PortViewModel {
    private(set) var ports: [ListeningPort] = []

    func refresh() {
        ports = consolidateByPID(PortScanner.scan())
    }

    /// Group ports by PID, keeping the lowest port as primary and tracking extras.
    private func consolidateByPID(_ scanned: [ListeningPort]) -> [ListeningPort] {
        let grouped = Dictionary(grouping: scanned) { $0.pid }
        return grouped.values.compactMap { group -> ListeningPort? in
            guard let primary = group.min(by: { $0.port < $1.port }) else { return nil }
            let extras = group.filter { $0.port != primary.port }.map(\.port).sorted()
            return ListeningPort(
                port: primary.port,
                pid: primary.pid,
                processName: primary.processName,
                displayName: primary.displayName,
                processPath: primary.processPath,
                workingDirectory: primary.workingDirectory,
                uptime: primary.uptime,
                physicalMemory: primary.physicalMemory,
                isCurrentUser: primary.isCurrentUser,
                localAddress: primary.localAddress,
                isDockerProxy: primary.isDockerProxy,
                additionalPorts: extras
            )
        }.sorted { $0.port < $1.port }
    }

    func killProcess(_ port: ListeningPort) {
        let result = ProcessManager.terminate(pid: port.pid)
        if case .needsEscalation = result {
            _ = ProcessManager.terminateWithPrivileges(pid: port.pid)
        }
    }
}
