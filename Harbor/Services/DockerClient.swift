import Foundation
import Darwin

/// A running container that publishes a host port.
struct DockerContainer {
    let name: String           // "consid-db-1"
    let image: String          // "postgres:16-alpine"
    let composeProject: String?
    let composeService: String?
    let publicPorts: Set<UInt16>

    /// "postgres:16-alpine" / "ghcr.io/foo/postgres:16" → "postgres"
    var imageName: String {
        let last = image.split(separator: "/").last.map(String.init) ?? image
        return last.split(separator: ":").first.map(String.init) ?? last
    }
}

/// Minimal Docker Engine API client over the local unix socket (Docker Desktop, OrbStack, Colima).
enum DockerClient {

    private static let socketPaths = [
        "\(NSHomeDirectory())/.docker/run/docker.sock",
        "\(NSHomeDirectory())/.orbstack/run/docker.sock",
        "\(NSHomeDirectory())/.colima/default/docker.sock",
        "/var/run/docker.sock",
    ]

    static func runningContainers() -> [DockerContainer] {
        for path in socketPaths where FileManager.default.fileExists(atPath: path) {
            if let data = get("/containers/json", socketPath: path) {
                return parse(data)
            }
        }
        return []
    }

    private struct APIContainer: Decodable {
        let Names: [String]
        let Image: String
        let Ports: [APIPort]?
        let Labels: [String: String]?

        struct APIPort: Decodable {
            let PublicPort: UInt16?
        }
    }

    private static func parse(_ data: Data) -> [DockerContainer] {
        guard let containers = try? JSONDecoder().decode([APIContainer].self, from: data) else { return [] }
        return containers.compactMap { c in
            let ports = Set((c.Ports ?? []).compactMap(\.PublicPort))
            guard !ports.isEmpty else { return nil }
            let name = c.Names.first.map { $0.hasPrefix("/") ? String($0.dropFirst()) : $0 } ?? c.Image
            return DockerContainer(
                name: name,
                image: c.Image,
                composeProject: c.Labels?["com.docker.compose.project"],
                composeService: c.Labels?["com.docker.compose.service"],
                publicPorts: ports
            )
        }
    }

    /// HTTP/1.0 GET over a unix socket — the server closes the connection, so read to EOF.
    private static func get(_ path: String, socketPath: String) -> Data? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        // Never let a hung daemon block the menu
        var timeout = timeval(tv_sec: 0, tv_usec: 300_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            buf.copyBytes(from: pathBytes)
        }
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { return nil }

        let request = Array("GET \(path) HTTP/1.0\r\nHost: docker\r\n\r\n".utf8)
        guard write(fd, request, request.count) == request.count else { return nil }

        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let n = read(fd, &buffer, buffer.count)
            if n <= 0 { break }
            response.append(buffer, count: n)
        }

        guard let headerEnd = response.range(of: Data("\r\n\r\n".utf8)),
              let statusLine = String(data: response[..<headerEnd.lowerBound], encoding: .utf8)?
                .split(separator: "\r\n").first,
              statusLine.contains(" 200 ") else { return nil }
        return response[headerEnd.upperBound...]
    }
}
