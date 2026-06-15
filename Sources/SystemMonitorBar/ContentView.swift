import SwiftUI

// MARK: - Popover

struct PopoverView: View {
    @ObservedObject var monitor: SystemMonitor
    @ObservedObject var aiMonitor: AIMonitor
    let loginItemEnabled: Bool
    let toggleLoginItem: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // CPU section
            section(
                icon: "cpu",
                title: "CPU",
                value: String(format: "%.1f%%", monitor.cpuUsage)
            ) {
                Gauge(value: monitor.cpuUsage, in: 0...100) {}
                    .gaugeStyle(.accessoryLinearCapacity)
                    .tint(gaugeTint(monitor.cpuUsage))
            }

            Divider().padding(.horizontal, 14)

            // Memory section
            section(
                icon: "memorychip",
                title: "Memory",
                value: memoryDetail
            ) {
                let fraction = memoryFraction
                Gauge(value: fraction, in: 0...1) {}
                    .gaugeStyle(.accessoryLinearCapacity)
                    .tint(memoryTint(fraction))
            }

            Divider().padding(.horizontal, 14)

            // AI section
            VStack(alignment: .leading, spacing: 4) {
                aiSectionHeader
                ForEach(aiMonitor.tools.indices, id: \.self) { i in
                    let tool = aiMonitor.tools[i]
                    aiRow(tool)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider().padding(.horizontal, 14)

            // Settings section
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label("Settings", systemImage: "gearshape")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.bottom, 2)

                Toggle(isOn: .init(
                    get: { loginItemEnabled },
                    set: { _ in toggleLoginItem() }
                )) {
                    Text("Launch at Login")
                        .font(.system(size: 12, weight: .regular))
                }
                .toggleStyle(.switch)
                .padding(.vertical, 2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider().padding(.horizontal, 14)

            // Quit
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack {
                    Spacer()
                    Text("Quit")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Helpers

    private var memoryDetail: String {
        let used = Double(monitor.memoryUsed) / 1_073_741_824.0
        let total = Double(monitor.memoryTotal) / 1_073_741_824.0
        return String(format: "%.1f / %.0f GB", used, total)
    }

    private var memoryFraction: Double {
        guard monitor.memoryTotal > 0 else { return 0 }
        return Double(monitor.memoryUsed) / Double(monitor.memoryTotal)
    }

    @ViewBuilder
    private func section(
        icon: String,
        title: String,
        value: String,
        @ViewBuilder gauge: () -> some View
    ) -> some View {
        VStack(spacing: 8) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
            }
            gauge()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var aiSectionHeader: some View {
        HStack {
            Label("AI Agents", systemImage: "brain.head.profile")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text("Click pin to show in menu bar")
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(.tertiary)
        }
        .padding(.bottom, 2)
    }

    private func aiRow(_ tool: AIToolStatus) -> some View {
        HStack(spacing: 8) {
            statusIcon(tool.status)
            Text(tool.displayName)
                .font(.system(size: 12, weight: .regular))
            Spacer()
            Text(statusText(tool.status))
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.secondary)
            Button {
                aiMonitor.togglePin(tool.id)
            } label: {
                Label("Pin", systemImage: tool.pinned ? "pin.fill" : "pin")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 10))
                    .foregroundStyle(tool.pinned ? Color.blue : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(tool.pinned ? "Unpin from menu bar" : "Pin to menu bar")
        }
        .padding(.vertical, 2)
    }

    private func statusIcon(_ status: AIStatus) -> some View {
        let size: CGFloat = 7
        switch status {
        case .working:
            return Circle().fill(Color.orange).frame(width: size, height: size)
        case .idle:
            return Circle().fill(Color.green).frame(width: size, height: size)
        case .completed:
            return Circle().fill(Color.blue).frame(width: size, height: size)
        case .notRunning:
            return Circle().fill(Color.secondary.opacity(0.3)).frame(width: size, height: size)
        }
    }

    private func statusText(_ status: AIStatus) -> String {
        switch status {
        case .working:   return "Working"
        case .idle:      return "Idle"
        case .completed: return "Done"
        case .notRunning: return "Off"
        }
    }

    private func gaugeTint(_ value: Double) -> Color {
        switch value {
        case 0..<30:  return .green
        case 30..<60: return .yellow
        case 60..<85: return .orange
        default:      return .red
        }
    }

    private func memoryTint(_ fraction: Double) -> Color {
        switch fraction {
        case 0..<0.5:  return .green
        case 0.5..<0.7: return .yellow
        case 0.7..<0.85: return .orange
        default:        return .red
        }
    }
}
