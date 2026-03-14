import SwiftUI
import ServiceManagement

struct PreferencesView: View {
    @ObservedObject var viewModel: PortViewModel
    @AppStorage("refreshInterval") private var refreshInterval: Double = 5.0
    @State private var launchAtLogin = false

    var body: some View {
        Form {
            Section("General") {
                Picker("Refresh interval", selection: $refreshInterval) {
                    Text("2 seconds").tag(2.0)
                    Text("5 seconds").tag(5.0)
                    Text("10 seconds").tag(10.0)
                    Text("30 seconds").tag(30.0)
                }
                .onChange(of: refreshInterval) { _, newValue in
                    viewModel.updateRefreshInterval(newValue)
                }

                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                LabeledContent("Ports detected", value: "\(viewModel.ports.count)")
            }
        }
        .formStyle(.grouped)
        .frame(width: 350, height: 220)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
