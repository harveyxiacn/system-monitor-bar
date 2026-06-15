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

        aiMonitor.refresh()

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

        var parts: [String] = ["\(cpu) · \(mem)"]

        let pinnedWorking = aiMonitor.tools.filter { $0.pinned && $0.status == .working }
        let pinnedIdle   = aiMonitor.tools.filter { $0.pinned && $0.status == .idle }

        for t in pinnedWorking { parts.append("\(shortName(t.displayName)):⚡") }
        for t in pinnedIdle   { parts.append("\(shortName(t.displayName)):●") }
        let compNames = aiMonitor.recentCompletions.map { "\(shortName($0)):✓" }
        parts.append(contentsOf: compNames)

        let title = parts.joined(separator: " ")
        let font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        button.attributedTitle = NSAttributedString(string: title, attributes: [.font: font])
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
                toggleLoginItem: { [weak self] in self?.toggleLoginItem() }
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
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        strongDelegate = delegate
        app.delegate = delegate
        app.run()
    }
}
