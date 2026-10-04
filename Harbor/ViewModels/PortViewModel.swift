import Foundation

@MainActor
class PortViewModel {
    private(set) var ports: [ListeningPort] = []

    func refresh(showAll: Bool = false) {
        let scanned = withDockerNames(PortScanner.scan())
        ports = showAll ? scanned : filterNoisePorts(scanned)
    }

    /// Replace "docker" with the container behind each published port:
    /// project = compose project (or container name), name = service + image.
    private func withDockerNames(_ scanned: [ListeningPort]) -> [ListeningPort] {
        guard scanned.contains(where: \.isDockerProxy) else { return scanned }
        let containers = DockerClient.runningContainers()
        guard !containers.isEmpty else { return scanned }

        return scanned.map { port in
            guard port.isDockerProxy,
                  let container = containers.first(where: { $0.publicPorts.contains(port.port) }) else { return port }
            var named = port
            let image = container.imageName
            if let project = container.composeProject, let service = container.composeService {
                let name = service == image ? image : "\(service) (\(image))"
                named.displayName = "\(project) / \(name)"
            } else {
                named.displayName = "\(container.name) / \(image)"
            }
            return named
        }
    }

    /// Remove debug inspector ports and ephemeral ports when the same project (or PID)
    /// already has a real dev port — e.g. wrangler's internal ports next to workerd on 8787.
    private func filterNoisePorts(_ scanned: [ListeningPort]) -> [ListeningPort] {
        let debugPorts: Set<UInt16> = [9229, 9230]  // Node.js inspector
        let ephemeralStart: UInt16 = 49152

        func groupKey(_ port: ListeningPort) -> String {
            port.projectName.isEmpty ? "pid:\(port.pid)" : port.projectName
        }
        func isNoise(_ port: ListeningPort) -> Bool {
            debugPorts.contains(port.port) || port.port >= ephemeralStart
        }

        // Groups with at least one port in a meaningful range
        let groupsWithDevPort = Set(scanned.filter { !isNoise($0) }.map(groupKey))

        // Keep everything from groups that have no dev port (nothing else to show)
        return scanned.filter { !groupsWithDevPort.contains(groupKey($0)) || !isNoise($0) }
    }

    func killProcess(_ port: ListeningPort) {
        let result = ProcessManager.terminate(pid: port.pid)
        if case .needsEscalation = result {
            _ = ProcessManager.terminateWithPrivileges(pid: port.pid)
        }
    }

    func forceKillProcess(_ port: ListeningPort) {
        let result = ProcessManager.forceKill(pid: port.pid)
        if case .needsEscalation = result {
            _ = ProcessManager.forceKillWithPrivileges(pid: port.pid)
        }
    }
}
