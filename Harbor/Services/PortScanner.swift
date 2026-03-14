import Foundation
import Darwin

enum PortScanner {

    /// Scan for listening TCP ports using libproc APIs.
    static func scan() -> [ListeningPort] {
        var ports: [ListeningPort] = []
        let currentUID = getuid()

        // Get all PIDs
        let bufferSize = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bufferSize > 0 else { return fallbackScan() }

        let pidCount = Int(bufferSize) / MemoryLayout<pid_t>.size
        var pids = [pid_t](repeating: 0, count: pidCount)
        let actualSize = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, bufferSize)
        guard actualSize > 0 else { return fallbackScan() }

        let actualCount = Int(actualSize) / MemoryLayout<pid_t>.size

        for i in 0..<actualCount {
            let pid = pids[i]
            guard pid > 0 else { continue }

            let listeningPorts = getListeningPorts(for: pid, currentUID: currentUID)
            ports.append(contentsOf: listeningPorts)
        }

        return ports.sorted { $0.port < $1.port }
    }

    private static func getListeningPorts(for pid: pid_t, currentUID: uid_t) -> [ListeningPort] {
        // Get the number of file descriptors
        let fdBufferSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard fdBufferSize > 0 else { return [] }

        let fdCount = Int(fdBufferSize) / MemoryLayout<proc_fdinfo>.size
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: fdCount)
        let actualFdSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, fdBufferSize)
        guard actualFdSize > 0 else { return [] }

        let actualFdCount = Int(actualFdSize) / MemoryLayout<proc_fdinfo>.size
        var results: [ListeningPort] = []

        for j in 0..<actualFdCount {
            let fd = fds[j]
            guard fd.proc_fdtype == PROX_FDTYPE_SOCKET else { continue }

            var socketInfo = socket_fdinfo()
            let socketInfoSize = proc_pidfdinfo(
                pid, fd.proc_fd, PROC_PIDFDSOCKETINFO,
                &socketInfo, Int32(MemoryLayout<socket_fdinfo>.size)
            )
            guard socketInfoSize == MemoryLayout<socket_fdinfo>.size else { continue }

            // Check for TCP socket in LISTEN state
            let family = socketInfo.psi.soi_family
            guard family == AF_INET || family == AF_INET6 else { continue }
            guard socketInfo.psi.soi_kind == SOCKINFO_TCP else { continue }
            guard socketInfo.psi.soi_proto.pri_tcp.tcpsi_state == TSI_S_LISTEN else { continue }

            // Extract port (insi_lport is Int32 in network byte order)
            let rawPort = socketInfo.psi.soi_proto.pri_tcp.tcpsi_ini.insi_lport
            let port = UInt16(bigEndian: UInt16(truncatingIfNeeded: rawPort))
            let address: String
            if family == AF_INET {
                let addr = socketInfo.psi.soi_proto.pri_tcp.tcpsi_ini.insi_laddr.ina_46.i46a_addr4
                let addrValue = addr.s_addr
                address = addrValue == 0 ? "*" : formatIPv4(addrValue)
            } else {
                address = "::"
            }

            guard port > 0 else { continue }

            let details = ProcessInspector.inspect(pid: pid)
            let isCurrentUser = (details.uid == currentUID)

            let listeningPort = ListeningPort(
                port: port,
                pid: pid,
                processName: details.name,
                displayName: details.displayName,
                processPath: details.path,
                workingDirectory: details.workingDirectory,
                uptime: details.uptime,
                physicalMemory: details.memory,
                isCurrentUser: isCurrentUser,
                localAddress: address,
                isDockerProxy: details.isDockerProxy
            )
            results.append(listeningPort)
        }

        return results
    }

    private static func formatIPv4(_ addr: in_addr_t) -> String {
        let bytes = withUnsafeBytes(of: addr) { Array($0) }
        return "\(bytes[0]).\(bytes[1]).\(bytes[2]).\(bytes[3])"
    }

    /// Fallback: parse lsof output when libproc fails (e.g. permission issues)
    static func fallbackScan() -> [ListeningPort] {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-iTCP", "-sTCP:LISTEN", "-P", "-n", "-F", "pcnf"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        return parseLsofOutput(output)
    }

    private static func parseLsofOutput(_ output: String) -> [ListeningPort] {
        var ports: [ListeningPort] = []
        let currentUID = getuid()

        var currentPid: pid_t = 0
        var currentName = ""

        for line in output.split(separator: "\n") {
            let value = String(line.dropFirst())
            switch line.first {
            case "p":
                currentPid = pid_t(value) ?? 0
            case "c":
                currentName = value
            case "n":
                // Format: *:PORT or 127.0.0.1:PORT or [::1]:PORT
                if let colonIdx = value.lastIndex(of: ":") {
                    let portStr = value[value.index(after: colonIdx)...]
                    if let portNum = UInt16(portStr) {
                        let addr = String(value[value.startIndex..<colonIdx])
                        let details = ProcessInspector.inspect(pid: currentPid)
                        let port = ListeningPort(
                            port: portNum,
                            pid: currentPid,
                            processName: currentName.isEmpty ? details.name : currentName,
                            displayName: details.displayName,
                            processPath: details.path,
                            workingDirectory: details.workingDirectory,
                            uptime: details.uptime,
                            physicalMemory: details.memory,
                            isCurrentUser: details.uid == currentUID,
                            localAddress: addr,
                            isDockerProxy: details.isDockerProxy
                        )
                        ports.append(port)
                    }
                }
            default:
                break
            }
        }

        return ports.sorted { $0.port < $1.port }
    }
}
