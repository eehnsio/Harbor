import SwiftUI

struct PortListView: View {
    @ObservedObject var viewModel: PortViewModel
    @State private var killConfirmation: ListeningPort?
    @State private var searchText = ""
    @AppStorage("showAllPorts") private var showAllPorts = false

    private var visiblePorts: [ListeningPort] {
        var result = viewModel.ports
        if !showAllPorts {
            result = result.filter { $0.isDevPort }
        }
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.displayName.lowercased().contains(query) ||
                $0.processName.lowercased().contains(query) ||
                String($0.port).contains(query)
            }
        }
        return result
    }

    private var hiddenCount: Int {
        viewModel.ports.count - viewModel.ports.filter { $0.isDevPort }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Harbor")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Button { viewModel.refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .buttonStyle(.plain)
                .keyboardShortcut("r", modifiers: .command)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Filter
            if !viewModel.ports.isEmpty {
                HStack(spacing: 0) {
                    ForEach(["Dev", "All"], id: \.self) { label in
                        let isSelected = (label == "Dev") != showAllPorts
                        Button {
                            showAllPorts = (label == "All")
                        } label: {
                            Text(label)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(isSelected ? .white : .white.opacity(0.3))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(isSelected ? .white.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.2))
                        TextField("Filter...", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11))
                            .frame(width: 70)
                        if !searchText.isEmpty {
                            Button { searchText = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.white.opacity(0.25))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            }

            Divider().overlay(.white.opacity(0.06))

            // List
            if viewModel.ports.isEmpty {
                Spacer()
                Text("No listening ports")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.3))
                Spacer()
            } else if visiblePorts.isEmpty {
                Spacer()
                VStack(spacing: 4) {
                    Text("No dev ports")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.3))
                    if hiddenCount > 0 {
                        Button("Show all") { showAllPorts = true }
                            .font(.system(size: 11))
                            .buttonStyle(.plain)
                            .foregroundStyle(.green)
                    }
                }
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(visiblePorts) { port in
                            PortRow(port: port) { killConfirmation = port }
                            if port.id != visiblePorts.last?.id {
                                Divider().overlay(.white.opacity(0.04))
                                    .padding(.leading, 54)
                            }
                        }

                        if !showAllPorts && hiddenCount > 0 {
                            Divider().overlay(.white.opacity(0.04))
                            Button { showAllPorts = true } label: {
                                Text("+ \(hiddenCount) system ports")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white.opacity(0.2))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Divider().overlay(.white.opacity(0.06))

            // Footer
            HStack {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.3))
                }
                Spacer()
                Button { NSApplication.shared.terminate(nil) } label: {
                    Label("Quit", systemImage: "power")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .buttonStyle(.plain)
                .keyboardShortcut("q", modifiers: .command)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .background(Color(nsColor: .init(white: 0.12, alpha: 1)))
        .preferredColorScheme(.dark)
        .alert("Kill Process", isPresented: .init(
            get: { killConfirmation != nil },
            set: { if !$0 { killConfirmation = nil } }
        )) {
            if let port = killConfirmation {
                Button("Cancel", role: .cancel) { killConfirmation = nil }
                Button("Terminate", role: .destructive) {
                    viewModel.killProcess(port)
                    killConfirmation = nil
                }
            }
        } message: {
            if let port = killConfirmation {
                Text("Terminate \(port.displayName) (PID \(port.pid)) on port \(port.port)?")
            }
        }
    }
}

// MARK: - Row

struct PortRow: View {
    let port: ListeningPort
    let onKill: () -> Void
    @State private var isHovered = false

    private var accentColor: Color {
        if port.isDockerProxy { return .blue }
        if !port.isCurrentUser { return .red }
        return .green
    }

    var body: some View {
        HStack(spacing: 10) {
            // Port
            HStack(spacing: 6) {
                Circle()
                    .fill(accentColor)
                    .frame(width: 6, height: 6)
                Text("\(port.port)")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .frame(width: 58, alignment: .leading)

            // Name
            Text(port.displayName)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            // Meta
            HStack(spacing: 6) {
                if port.uptime > 0 {
                    Text(Formatters.uptime(port.uptime))
                }
                if port.physicalMemory > 0 {
                    Text(Formatters.memory(port.physicalMemory))
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(.white.opacity(0.2))

            // Kill
            Button { onKill() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(isHovered ? .red.opacity(0.8) : .white.opacity(0.08))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(isHovered ? .white.opacity(0.04) : .clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .help(portTooltip)
    }

    private var portTooltip: String {
        var lines: [String] = []
        if !port.workingDirectory.isEmpty { lines.append(port.workingDirectory) }
        if !port.processPath.isEmpty { lines.append(port.processPath) }
        lines.append("PID \(port.pid) — \(port.localAddress):\(port.port)")
        return lines.joined(separator: "\n")
    }
}
