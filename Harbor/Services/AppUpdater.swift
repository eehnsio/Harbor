import AppKit
import Security

enum AppUpdater {

    /// Apple Developer Team ID that signs official Harbor releases.
    static let teamID = "735SV765PC"

    /// Download, extract, replace, and relaunch the app.
    static func update(from zipURL: URL, onProgress: @escaping (Double) -> Void) async throws {
        // 1. Download
        let localZip = try await download(zipURL, onProgress: onProgress)

        // 2. Extract
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-xk", localZip.path, tempDir.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else {
            throw UpdateError.extractionFailed
        }

        let extractedApp = tempDir.appendingPathComponent("Harbor.app")
        guard FileManager.default.fileExists(atPath: extractedApp.path) else {
            throw UpdateError.extractionFailed
        }

        // 3. Refuse anything not signed with our Developer ID
        try verifySignature(of: extractedApp)

        // 4. Clear quarantine
        let xattr = Process()
        xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattr.arguments = ["-cr", extractedApp.path]
        try? xattr.run()
        xattr.waitUntilExit()

        // 5. Replace /Applications/Harbor.app
        let appPath = "/Applications/Harbor.app"
        let backupPath = "/Applications/Harbor.app.old"

        do {
            try? FileManager.default.removeItem(atPath: backupPath)
            if FileManager.default.fileExists(atPath: appPath) {
                try FileManager.default.moveItem(atPath: appPath, toPath: backupPath)
            }
            try FileManager.default.moveItem(atPath: extractedApp.path, toPath: appPath)
            try? FileManager.default.removeItem(atPath: backupPath)
        } catch {
            // Try with admin privileges
            try replaceWithPrivileges(extractedPath: extractedApp.path)
        }

        // 6. Cleanup downloaded zip
        try? FileManager.default.removeItem(at: localZip)

        // 7. Relaunch
        relaunch()
    }

    /// Valid Developer ID Application signature from `teamID`, including nested code.
    private static func verifySignature(of app: URL) throws {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else {
            throw UpdateError.invalidSignature
        }

        // 1.2.840.113635.100.6.1.13 = Developer ID Application certificate
        let requirementText = """
        anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] \
        and certificate leaf[subject.OU] = "\(teamID)"
        """
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(requirementText as CFString, [], &requirement) == errSecSuccess,
              let requirement else {
            throw UpdateError.invalidSignature
        }

        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        guard SecStaticCodeCheckValidity(staticCode, flags, requirement) == errSecSuccess else {
            throw UpdateError.invalidSignature
        }
    }

    private static func download(_ url: URL, onProgress: @escaping (Double) -> Void) async throws -> URL {
        let delegate = DownloadDelegate(onProgress: onProgress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let (localURL, response) = try await session.download(from: url)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.downloadFailed
        }

        // Move to a stable temp location (URLSession temp files get deleted)
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("Harbor-update.zip")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: localURL, to: dest)
        return dest
    }

    private static func replaceWithPrivileges(extractedPath: String) throws {
        let script = """
        do shell script "rm -rf /Applications/Harbor.app.old; \
        mv /Applications/Harbor.app /Applications/Harbor.app.old 2>/dev/null; \
        mv '\(extractedPath)' /Applications/Harbor.app; \
        rm -rf /Applications/Harbor.app.old" with administrator privileges
        """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error { throw UpdateError.privilegesFailed(error.description) }
    }

    private static func relaunch() {
        let appPath = "/Applications/Harbor.app"
        let script = "sleep 1; open \"\(appPath)\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        try? process.run()
        NSApplication.shared.terminate(nil)
    }
}

enum UpdateError: LocalizedError {
    case downloadFailed
    case extractionFailed
    case privilegesFailed(String)
    case invalidSignature

    var errorDescription: String? {
        switch self {
        case .downloadFailed: "Download failed"
        case .extractionFailed: "Failed to extract update"
        case .privilegesFailed(let msg): "Privileges error: \(msg)"
        case .invalidSignature: "Update is not signed by the Harbor developer"
        }
    }
}

// MARK: - Download progress tracking

private class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let onProgress: (Double) -> Void

    init(onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async { self.onProgress(progress) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // Handled by async download call
    }
}
