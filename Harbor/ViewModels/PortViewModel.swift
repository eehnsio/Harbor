import Foundation

@MainActor
class PortViewModel {
    private(set) var ports: [ListeningPort] = []

    func refresh(showAll: Bool = false) {
        let scanned = PortScanner.scan()
        ports = showAll ? scanned : filterNoisePorts(scanned)
    }

    /// Remove debug inspector ports and ephemeral ports when the same PID has a real dev port.
    private func filterNoisePorts(_ scanned: [ListeningPort]) -> [ListeningPort] {
        let debugPorts: Set<UInt16> = [9229, 9230]  // Node.js inspector
        let ephemeralStart: UInt16 = 49152

        // PIDs that have at least one port in a meaningful range
        let pidsWithDevPort = Set(scanned.filter {
            !debugPorts.contains($0.port) && $0.port < ephemeralStart
        }.map(\.pid))

        return scanned.filter { port in
            // Keep everything from PIDs that have no dev port (nothing else to show)
            guard pidsWithDevPort.contains(port.pid) else { return true }
            // Filter out debug and ephemeral ports
            if debugPorts.contains(port.port) { return false }
            if port.port >= ephemeralStart { return false }
            return true
        }
    }

    func killProcess(_ port: ListeningPort) {
        let result = ProcessManager.terminate(pid: port.pid)
        if case .needsEscalation = result {
            _ = ProcessManager.terminateWithPrivileges(pid: port.pid)
        }
    }
}
