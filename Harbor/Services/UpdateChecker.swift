import Foundation

struct GitHubRelease: Decodable {
    let tagName: String
    let assets: [Asset]

    struct Asset: Decodable {
        let name: String
        let browserDownloadUrl: String

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadUrl = "browser_download_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }

    /// Version string without "v" prefix
    var version: String {
        tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
    }

    /// URL for Harbor.app.zip asset
    var zipURL: URL? {
        assets.first(where: { $0.name == "Harbor.app.zip" })
            .flatMap { URL(string: $0.browserDownloadUrl) }
    }
}

enum UpdateStatus: Equatable {
    case idle
    case checking
    case available(version: String, url: URL)
    case downloading(progress: Double)
    case installing
    case failed(String)
    case upToDate

    static func == (lhs: UpdateStatus, rhs: UpdateStatus) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.checking, .checking), (.installing, .installing), (.upToDate, .upToDate):
            return true
        case let (.available(v1, _), .available(v2, _)):
            return v1 == v2
        case let (.downloading(p1), .downloading(p2)):
            return p1 == p2
        case let (.failed(m1), .failed(m2)):
            return m1 == m2
        default:
            return false
        }
    }
}

enum UpdateChecker {
    private static let apiURL = URL(string: "https://api.github.com/repos/eehnsio/Harbor/releases/latest")!

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    static func check() async -> UpdateStatus {
        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("Harbor/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

            guard let zipURL = release.zipURL else {
                return .upToDate
            }

            if isNewer(release.version, than: currentVersion) {
                return .available(version: release.version, url: zipURL)
            }
            return .upToDate
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Compare semantic versions using Foundation's numeric comparison
    private static func isNewer(_ remote: String, than local: String) -> Bool {
        local.compare(remote, options: .numeric) == .orderedAscending
    }
}
