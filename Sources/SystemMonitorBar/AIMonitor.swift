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
    private var lastSampleTime: DispatchTime?
    private var cachedPIDs: [String: ProcInfo] = [:]
    private var pendingQuickRefresh = false

    /// CPU usage (as a fraction of one core, averaged over the sample interval)
    /// needed to *enter* the "working" state.
    private static let workingThreshold = 0.10
    /// Lower bound to *leave* "working". The gap between the two thresholds is
    /// hysteresis: it stops a focused terminal that briefly spikes CPU just by
    /// redrawing its UI from flickering between working and idle.
    private static let idleThreshold = 0.04

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
        let snapshot: [String: ProcInfo]
        if cachedPIDs.isEmpty {
            // First run or no cached PIDs — must do a full scan.
            snapshot = currentProcessSnapshot()
        } else {
            let (cached, allSurvived) = incrementalCheck()
            snapshot = allSurvived ? cached : currentProcessSnapshot()
        }
        cachedPIDs = snapshot

        let now = DispatchTime.now()
        let elapsedNs = lastSampleTime.map { now.uptimeNanoseconds &- $0.uptimeNanoseconds } ?? 0
        lastSampleTime = now

        var nowRunning: Set<String> = []
        for i in tools.indices {
            let t = tools[i]
            if let info = snapshot[t.id] {
                nowRunning.insert(t.id)
                tools[i].pid = info.pid

                let hasBaseline = t.prevCPUTicks != 0 && elapsedNs > 0
                let deltaTicks = info.cpuTicks &- t.prevCPUTicks
                tools[i].prevCPUTicks = info.cpuTicks

                guard hasBaseline else {
                    tools[i].status = .idle
                    // Schedule a quick follow-up sample in 1 second so we can
                    // detect "working" state faster than the normal 5-second interval.
                    if !pendingQuickRefresh {
                        pendingQuickRefresh = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                            self?.pendingQuickRefresh = false
                            self?.refresh()
                        }
                    }
                    continue
                }

                // Child-process detection is the primary signal: AI agents spawn
                // subprocesses (bash, file reads, MCP tools) when actively working.
                // Idle sessions at a prompt have no children.
                let cpuFraction = Double(deltaTicks) / Double(elapsedNs)
                let hasChildren = hasActiveChildren(parentPID: info.pid)

                if hasChildren {
                    tools[i].status = .working
                } else if tools[i].status == .working {
                    // Was working, no children now — transitioning to idle.
                    // Use CPU as a grace period: only switch if CPU also dropped,
                    // to avoid flickering when a tool finishes but next one starts.
                    tools[i].status = cpuFraction < Self.idleThreshold ? .idle : .working
                } else {
                    // Idle/notRunning with no children: stay idle regardless of CPU.
                    // This prevents terminal UI redraws from falsely triggering "working".
                    tools[i].status = .idle
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
                    let toolID = tools[i].id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
                        self?.recentCompletions.removeAll { $0 == name }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
                        guard let idx = self?.tools.firstIndex(where: { $0.id == toolID }) else { return }
                        if self?.tools[idx].status == .completed {
                            self?.tools[idx].status = .notRunning
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
    }

    private struct ProcInfo {
        var pid: Int32
        var cpuTicks: UInt64
    }

    // MARK: - PID caching

    /// Quick check: are the previously-detected PIDs still alive and active?
    /// Returns updated ProcInfo for surviving PIDs; entries for dead PIDs
    /// are removed.  If ALL cached PIDs survived, no full scan is needed.
    private func incrementalCheck() -> ([String: ProcInfo], allSurvived: Bool) {
        var surviving: [String: ProcInfo] = [:]
        for (toolID, cached) in cachedPIDs {
            var ti = proc_taskinfo()
            let size = Int32(MemoryLayout<proc_taskinfo>.size)
            let ret = proc_pidinfo(cached.pid, PROC_PIDTASKINFO, 0, &ti, size)
            if ret > 0 {
                let cpuTicks = ti.pti_total_user &+ ti.pti_total_system
                surviving[toolID] = ProcInfo(pid: cached.pid, cpuTicks: cpuTicks)
            }
        }
        let allSurvived = surviving.count == cachedPIDs.count
        return (surviving, allSurvived)
    }

    // MARK: - Child process detection

    /// Process names that are always present when an AI agent is open
    /// but do NOT indicate active work (e.g. sleep-prevention daemons).
    private static let ignoredChildProcessNames: Set<String> = ["caffeinate"]

    /// Persistent shell processes that tools like Codex CLI keep alive even
    /// when idle.  For these, we recurse one level to check whether the shell
    /// itself has children (i.e. a command is actually running).
    private static let shellProcessNames: Set<String> = [
        "zsh", "bash", "sh", "fish", "csh", "tcsh", "ksh",
    ]

    /// Checks whether a given PID has any active child processes that
    /// indicate real work (tool calls, file I/O, bash commands).
    /// Filters out known always-present background processes like
    /// `caffeinate` which Claude Code spawns to prevent system sleep.
    /// For persistent shell children (zsh, bash, etc.) kept alive by tools
    /// like Codex CLI, recurses one level to check whether the shell itself
    /// has active children — only then counts as "working".
    private func hasActiveChildren(parentPID: Int32) -> Bool {
        var pids = [pid_t](repeating: 0, count: 2048)
        let bytes = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.stride))
        guard bytes > 0 else { return false }
        let count = min(Int(bytes) / MemoryLayout<pid_t>.stride, 2048)

        for i in 0..<count {
            let pid = pids[i]
            guard pid > 0, pid != parentPID else { continue }
            var info = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.stride
            var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
            let result = sysctl(&mib, 4, &info, &size, nil, 0)
            if result == 0 && info.kp_eproc.e_ppid == parentPID {
                var nameBuf = [CChar](repeating: 0, count: Int(MAXCOMLEN) + 1)
                proc_name(pid, &nameBuf, UInt32(MAXCOMLEN))
                let childName = String(cString: nameBuf)
                if Self.ignoredChildProcessNames.contains(childName) {
                    continue
                }
                if Self.shellProcessNames.contains(childName) {
                    // Shell child: only signal "working" if the shell itself
                    // has active children (a running command).
                    if hasActiveChildren(parentPID: pid) {
                        return true
                    }
                    continue
                }
                    return true
            }
        }
        return false
    }

    // MARK: - Process scanning

    /// Known executable path fragments for each tool.  A match on any
    /// fragment is sufficient; these are checked against the full path
    /// returned by `proc_pidpath` which is more expensive but more
    /// accurate than `proc_name`.
    private static let toolPathFragments: [String: [String]] = [
        "codex":        ["/.codex/", "codex-cli", "/codex.app/"],
        "claude":       ["/.claude/local/node_modules/", "/@anthropic-ai/claude-code/", "/bin/claude", "/.local/share/claude/"],
        "aider":        ["aider-chat", "/.local/bin/aider", "/aider/"],
        "windsurf":     ["/Windsurf.app/", "/windsurf"],
        "opencode":     ["/opencode", "/.opencode/"],
        "antigravity":  ["/antigravity", "/.antigravity/"],
    ]

    /// Returns one entry per monitored tool, keeping the PID with the **highest** CPU ticks
    /// (so the main app / CLI wins over low-CPU helper processes like node_repl).
    private func currentProcessSnapshot() -> [String: ProcInfo] {
        // `proc_listallpids` reports/consumes sizes in BYTES, not element counts.
        let pidSize = MemoryLayout<pid_t>.stride
        let neededBytes = proc_listallpids(nil, 0)
        guard neededBytes > 0 else { return [:] }

        let capacity = Int(neededBytes) / pidSize
        var pids = [pid_t](repeating: 0, count: capacity)
        let usedBytes = proc_listallpids(&pids, Int32(capacity * pidSize))
        guard usedBytes > 0 else { return [:] }
        let pidCount = min(Int(usedBytes) / pidSize, capacity)

        let monitorIDs = Set(tools.map(\.id))
        var result: [String: ProcInfo] = [:]

        for i in 0..<pidCount {
            let pid = pids[i]
            guard pid > 0 else { continue }

            var nameBuf = [CChar](repeating: 0, count: Int(MAXCOMLEN) + 1)
            proc_name(pid, &nameBuf, UInt32(MAXCOMLEN))
            let procName = String(cString: nameBuf).lowercased()

            // 1. Fast path: check process name against tool ID with word-boundary
            //    semantics to avoid false positives like "claudemonitor".
            var matchedID: String? = monitorIDs.first { id in
                procName == id || procName.hasPrefix(id) || procName.contains("/" + id)
            }

            // 2. Fallback: check full executable path against known fragments.
            if matchedID == nil {
                var pathBuf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
                proc_pidpath(pid, &pathBuf, UInt32(MAXPATHLEN))
                let procPath = String(cString: pathBuf).lowercased()
                matchedID = monitorIDs.first { id in
                    guard let fragments = Self.toolPathFragments[id] else {
                        return procPath.contains(id)
                    }
                    // Check specific fragments first, then fall back to
                    // generic substring match as a safety net.
                    return fragments.contains { procPath.contains($0) } || procPath.contains(id)
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
