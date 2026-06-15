import Foundation
import Darwin

// MARK: - Status types

enum AIStatus: String, CaseIterable {
    case notRunning = "notRunning"
    case working    = "working"
    case idle       = "idle"
    case completed  = "completed"
}

struct AIToolStatus: Identifiable {
    let id: String
    let displayName: String
    var status: AIStatus = .notRunning
    var pinned: Bool = false
    var pid: Int32? = nil
    var prevCPUTicks: UInt64 = 0  // cumulative CPU ticks for delta calc
}

// MARK: - Monitor

final class AIMonitor: ObservableObject {
    @Published var tools: [AIToolStatus] = [
        AIToolStatus(id: "codex",    displayName: "Codex"),
        AIToolStatus(id: "claude",   displayName: "Claude Code"),
        AIToolStatus(id: "gpt",      displayName: "GPT CLI"),
        AIToolStatus(id: "aider",    displayName: "Aider"),
        AIToolStatus(id: "windsurf", displayName: "Windsurf"),
        AIToolStatus(id: "opencode", displayName: "OpenCode"),
    ]

    /// Recently completed tool names for menu-bar brief display.
    @Published var recentCompletions: [String] = []

    private var timer: Timer?
    private let cpuThreshold: UInt64 = 50_000_000  // 50ms CPU time per 5s interval

    init() {
        Task { @MainActor in self.refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    // MARK: - Pinning

    @MainActor
    func togglePin(_ toolID: String) {
        guard let idx = tools.firstIndex(where: { $0.id == toolID }) else { return }
        tools[idx].pinned.toggle()
    }

    // MARK: - Refresh cycle

    @MainActor
    func refresh() {
        let snapshot = currentProcessSnapshot()

        // Process currently-running tool PIDs.
        var nowRunning: Set<String> = []
        for i in tools.indices {
            let t = tools[i]
            if let info = snapshot[t.id] {
                nowRunning.insert(t.id)
                tools[i].pid = info.pid
                // Determine working vs idle from CPU delta.
                let delta = info.cpuTicks &- t.prevCPUTicks
                tools[i].prevCPUTicks = info.cpuTicks
                if delta > cpuThreshold {
                    tools[i].status = .working
                } else {
                    // If it just became idle from working, keep "working" briefly.
                    if t.status == .working {
                        tools[i].status = .idle  // transition to idle
                    }
                    // Already idle or not_running → stay/idle
                    tools[i].status = tools[i].status == .completed ? .idle : (tools[i].status == .notRunning ? .working : tools[i].status)
                }
            }
        }

        // Handle tools that stopped running.
        for i in tools.indices {
            if !nowRunning.contains(tools[i].id) {
                if tools[i].status == .working || tools[i].status == .idle {
                    tools[i].status = .completed
                    recentCompletions.append(tools[i].displayName)
                    // Keep brief completion in recentCompletions.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
                        self?.recentCompletions.removeAll { $0 == self?.tools[i].displayName }
                    }
                    // Transition to notRunning after brief completion display.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
                        if self?.tools[i].status == .completed {
                            self?.tools[i].status = .notRunning
                        }
                    }
                } else if tools[i].status == .completed {
                    // Stay completed.
                } else {
                    tools[i].status = .notRunning
                }
                tools[i].pid = nil
                tools[i].prevCPUTicks = 0
            }
        }

        // If a tool was completed and then reappears (restarted), reset.
        for i in tools.indices {
            if nowRunning.contains(tools[i].id), tools[i].status == .completed {
                tools[i].status = .working
            }
        }
    }

    // MARK: - Process snapshot

    private struct ProcInfo {
        var pid: Int32
        var cpuTicks: UInt64
    }

    private func currentProcessSnapshot() -> [String: ProcInfo] {
        let bufSize = proc_listallpids(nil, 0)
        guard bufSize > 0 else { return [:] }

        let count = Int(bufSize)
        var pids = [pid_t](repeating: 0, count: count)
        let used = proc_listallpids(&pids, Int32(count))
        guard used > 0 else { return [:] }

        var result: [String: ProcInfo] = [:]
        let monitorIDs = Set(tools.map(\.id))

        for i in 0..<Int(used) {
            let pid = pids[i]
            var nameBuf = [CChar](repeating: 0, count: Int(MAXCOMLEN) + 1)
            proc_name(pid, &nameBuf, UInt32(MAXCOMLEN))
            let name = String(cString: nameBuf).lowercased()

            guard monitorIDs.contains(name) else { continue }

            // Get CPU ticks via proc_pidinfo(PROC_PIDTASKINFO).
            var ti = proc_taskinfo()
            let size = Int32(MemoryLayout<proc_taskinfo>.size)
            let ret = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &ti, size)
            let cpuTicks: UInt64 = (ret > 0) ? (ti.pti_total_user &+ ti.pti_total_system) : 0

            result[name] = ProcInfo(pid: pid, cpuTicks: cpuTicks)
        }
        return result
    }
}
