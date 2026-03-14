import Foundation
import SwiftUI

@MainActor
class PortViewModel: ObservableObject {
    @Published var ports: [ListeningPort] = []
    @Published var lastRefresh = Date()

    private var timer: Timer?

    init() {
        let interval = UserDefaults.standard.double(forKey: "refreshInterval")
        startTimer(interval: interval > 0 ? interval : 5.0)
        refresh()
    }

    func refresh() {
        Task.detached { [weak self] in
            let scanned = PortScanner.scan()
            await MainActor.run {
                self?.ports = scanned
                self?.lastRefresh = Date()
            }
        }
    }

    func killProcess(_ port: ListeningPort) {
        let result = ProcessManager.terminate(pid: port.pid)
        switch result {
        case .success:
            // Wait briefly then refresh
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.refresh()
            }
        case .needsEscalation:
            let escalated = ProcessManager.terminateWithPrivileges(pid: port.pid)
            if case .success = escalated {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.refresh()
                }
            }
        case .failed:
            break
        }
    }

    func updateRefreshInterval(_ interval: Double) {
        startTimer(interval: interval)
    }

    private func startTimer(interval: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }
}
