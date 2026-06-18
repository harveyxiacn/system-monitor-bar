import SwiftUI
import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    let monitor = SystemMonitor()
    let aiMonitor = AIMonitor()

    var loginItemEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // 2s balances responsiveness with minimal CPU overhead for a menu-bar utility.
        if let button = statusItem?.button {
            Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateMenuBarTitle(button: button)
                }
            }
            updateMenuBarTitle(button: button)
        }

        statusItem?.button?.target = self
        statusItem?.button?.action = #selector(togglePopover)
    }

    func toggleLoginItem() {
        do {
            if loginItemEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            print("SMAppService error: \(error)")
        }
    }

    private func updateMenuBarTitle(button: NSStatusBarButton) {
        let cpu = String(format: "%.0f%%", monitor.cpuUsage)
        let mem: String = {
            let gb = Double(monitor.memoryUsed) / 1_073_741_824.0
            return gb >= 10 ? String(format: "%.0fG", gb) : String(format: "%.1fG", gb)
        }()
        let temp: String = {
            guard let t = monitor.cpuTemperature else { return "" }
            return String(format: " · %.0f°C", t)
        }()
        let gpuTemp: String = {
            guard let t = monitor.gpuTemperature else { return "" }
            return String(format: " · GPU %.0f°C", t)
        }()

        let baseFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        let result = NSMutableAttributedString()

        result.append(NSAttributedString(
            string: "\(cpu) · \(mem)\(temp)\(gpuTemp)",
            attributes: [.font: baseFont, .foregroundColor: NSColor.labelColor]
        ))

        let theme = ThemeManager.shared.currentTheme

        func appendBadge(name: String, appearance: StatusAppearance) {
            result.append(NSAttributedString(
                string: " \(shortName(name)):\(appearance.menuSymbol)",
                attributes: [.font: baseFont, .foregroundColor: appearance.color.nsColor]
            ))
        }

        for t in aiMonitor.tools where t.pinned && t.status == .working {
            appendBadge(name: t.displayName, appearance: theme.working)
        }
        for t in aiMonitor.tools where t.pinned && t.status == .idle {
            appendBadge(name: t.displayName, appearance: theme.idle)
        }
        for name in aiMonitor.recentCompletions {
            appendBadge(name: name, appearance: theme.completed)
        }

        button.attributedTitle = result
    }

    private func shortName(_ name: String) -> String {
        switch name.lowercased() {
        case "codex":       return "Cx"
        case "claude code": return "Cc"
        case "aider":       return "Aid"
        case "windsurf":    return "Ws"
        case "opencode":    return "Oc"
        case "antigravity": return "AG"
        default:            return String(name.prefix(2))
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }

        if let popover = popover, popover.isShown {
            popover.performClose(nil)
            return
        }

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 420)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(
                monitor: monitor,
                aiMonitor: aiMonitor,
                loginItemEnabled: loginItemEnabled,
                toggleLoginItem: { [weak self] in self?.toggleLoginItem() },
                onResize: { [weak self] size in
                    self?.popover?.contentSize = size
                }
            )
        )
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        self.popover = popover
        NSApp.activate(ignoringOtherApps: true)
    }
}

private var strongDelegate: AppDelegate?

@main
struct MainEntry {
    static func main() {
        // Single-instance guard: write our PID to a lock file. If another
        // instance is already running (PID still alive), exit immediately.
        let lockPath = NSTemporaryDirectory().appending("SystemMonitorBar.lock")
        if let data = FileManager.default.contents(atPath: lockPath),
           let contents = String(data: data, encoding: .utf8),
           let existingPID = Int32(contents.trimmingCharacters(in: .whitespacesAndNewlines)),
           existingPID != ProcessInfo.processInfo.processIdentifier {
            // Check if the existing process is still alive
            if kill(existingPID, 0) == 0 {
                // Another instance is running — exit silently
                exit(0)
            }
        }
        // Write our PID (overwrite stale lock)
        try? "\(ProcessInfo.processInfo.processIdentifier)".write(
            toFile: lockPath, atomically: true, encoding: .utf8
        )

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        strongDelegate = delegate
        app.delegate = delegate
        app.run()
    }
}
