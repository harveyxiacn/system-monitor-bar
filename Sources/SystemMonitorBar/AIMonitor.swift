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
    var prevCPUTicks: UInt64 = 0
}

// MARK: - Monitor

final class AIMonitor: ObservableObject {
    @Published var tools: [AIToolStatus] = [
        AIToolStatus(id: "codex",    displayName: "Codex"),
        AIToolStatus(id: "claude",   displayName: "Claude Code"),
        AIToolStatus(id: "aider",    displayName: "Aider"),
        AIToolStatus(id: "windsurf", displayName: "Windsurf"),
        AIToolStatus(id: "opencode", displayName: "OpenCode"),
        AIToolStatus(id: "antigravity", displayName: "Antigravity"),
    ]

    @Published var recentCompletions: [String] = []

    private var timer: Timer?
    private let cpuThreshold: UInt64 = 50_000_000

    init() {
        let pinnedKeys = UserDefaults.standard.stringArray(forKey: "AIMonitor.pinned") ?? []
        for k in pinnedKeys {
            if let idx = tools.firstIndex(where: { $0.id == k }) {
                tools[idx].pinned = true
            }
        }

        Task { @MainActor in self.refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    @MainActor
    func togglePin(_ toolID: String) {
        guard let idx = tools.firstIndex(where: { $0.id == toolID }) else { return }
        tools[idx].pinned.toggle()
        let keys = tools.filter(\.pinned).map(\.id)
        UserDefaults.standard.set(keys, forKey: "AIMonitor.pinned")
    }

    @MainActor
    func refresh() {
        let snapshot = currentProcessSnapshot()  // [toolID: ProcInfo] — keeps highest-CPU PID per tool

        var nowRunning: Set<String> = []
        for i in tools.indices {
            let t = tools[i]
            if let info = snapshot[t.id] {
                nowRunning.insert(t.id)
                tools[i].pid = info.pid
                let delta = info.cpuTicks &- t.prevCPUTicks
                tools[i].prevCPUTicks = info.cpuTicks
                if delta > cpuThreshold {
                    tools[i].status = .working
                } else {
                    if t.status == .working {
                        tools[i].status = .idle
                    }
                    if tools[i].status == .notRunning {
                        tools[i].status = .working
                    }
                }
            }
        }

        for i in tools.indices {
            if !nowRunning.contains(tools[i].id) {
                let wasActive = tools[i].status == .working || tools[i].status == .idle
                if wasActive {
                    tools[i].status = .completed
                    recentCompletions.append(tools[i].displayName)
                    let name = tools[i].displayName
                    DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
                        self?.recentCompletions.removeAll { $0 == name }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
                        if self?.tools[i].status == .completed {
                            self?.tools[i].status = .notRunning
                        }
                    }
                } else if tools[i].status == .completed {
                    // stay completed
                } else {
                    tools[i].status = .notRunning
                }
                tools[i].pid = nil
                tools[i].prevCPUTicks = 0
            }
        }

        for i in tools.indices {
            if nowRunning.contains(tools[i].id), tools[i].status == .completed {
                tools[i].status = .working
            }
        }
    }

    private struct ProcInfo {
        var pid: Int32
        var cpuTicks: UInt64
    }

    /// Returns one entry per monitored tool, keeping the PID with the **highest** CPU ticks
    /// (so the main app / CLI wins over low-CPU helper processes like node_repl).
    private func currentProcessSnapshot() -> [String: ProcInfo] {
        let bufSize = proc_listallpids(nil, 0)
        guard bufSize > 0 else { return [:] }

        let count = Int(bufSize)
        var pids = [pid_t](repeating: 0, count: count)
        let used = proc_listallpids(&pids, Int32(count))
        guard used > 0 else { return [:] }

        let monitorIDs = Set(tools.map(\.id))
        var result: [String: ProcInfo] = [:]

        for i in 0..<Int(used) {
            let pid = pids[i]

            var nameBuf = [CChar](repeating: 0, count: Int(MAXCOMLEN) + 1)
            proc_name(pid, &nameBuf, UInt32(MAXCOMLEN))
            let procName = String(cString: nameBuf).lowercased()

            var pathBuf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            proc_pidpath(pid, &pathBuf, UInt32(MAXPATHLEN))
            let procPath = String(cString: pathBuf).lowercased()

            var matchedID: String? = nil
            for toolID in monitorIDs {
                if procName.contains(toolID) || procPath.contains(toolID) {
                    matchedID = toolID
                    break
                }
            }
            guard let matchedID else { continue }

            var ti = proc_taskinfo()
            let size = Int32(MemoryLayout<proc_taskinfo>.size)
            let ret = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &ti, size)
            let cpuTicks: UInt64 = (ret > 0) ? (ti.pti_total_user &+ ti.pti_total_system) : 0

            // Keep the PID with the highest CPU ticks for this tool.
            if let existing = result[matchedID] {
                if cpuTicks > existing.cpuTicks {
                    result[matchedID] = ProcInfo(pid: pid, cpuTicks: cpuTicks)
                }
            } else {
                result[matchedID] = ProcInfo(pid: pid, cpuTicks: cpuTicks)
            }
        }
        return result
    }
}
