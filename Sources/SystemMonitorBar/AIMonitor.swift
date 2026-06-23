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
    var prevCSW: UInt64 = 0
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
    /// When true, we know at least one tool is running (PID detected) but idle.
    /// Use 1-second polling to catch short-lived child processes more reliably.
    private var activePolling = false

    /// CPU usage (as a fraction of one core, averaged over the sample interval)
    /// needed to *enter* the "working" state.
    private static let workingThreshold = 0.10
    /// Lower threshold for detecting "thinking" states from idle. AI agents
    /// making API calls use little CPU (network I/O, JSON parsing) but are
    /// still actively working. This threshold is intentionally low to catch
    /// those states while avoiding false positives from truly idle processes.
    private static let detectionThreshold = 0.005
    /// Lower bound to *leave* "working". The gap between the two thresholds is
    /// hysteresis: it stops a focused terminal that briefly spikes CPU just by
    /// redrawing its UI from flickering between working and idle.
    private static let idleThreshold = 0.04
    /// Short grace period for brief gaps between child process spawns
    /// (e.g., between bash commands). Much shorter than the old 60s cooldown.
    private static let workingGraceNanos: UInt64 = 3_000_000_000 // 3 seconds
    /// How long to stay in "completed" before transitioning to "idle".
    private static let completedToIdleNanos: UInt64 = 5_000_000_000 // 5 seconds
    private var lastChildActiveTime: [String: UInt64] = [:]
    private var lastCompletedTime: [String: UInt64] = [:]

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

        // Build the parent→children index ONCE per refresh (a single process
        // scan), shared by every hasActiveChildren() check below. Previously
        // each running tool triggered its own full proc_listallpids scan plus
        // recursion — O(tools × processes); this collapses it to O(processes).
        // Skipped entirely when no monitored tool is running.
        let childrenIndex: ChildrenIndex = snapshot.isEmpty ? [:] : buildChildrenIndex()

        let enabledTools = DisplaySettings.shared.config.enabledToolIDs
        var nowRunning: Set<String> = []
        for i in tools.indices {
            let t = tools[i]
            // Tools the user disabled are not scanned or shown. Reset any leftover
            // state so a previously-running tool clears immediately when disabled.
            guard enabledTools.contains(t.id) else {
                if tools[i].status != .notRunning { tools[i].status = .notRunning }
                tools[i].pid = nil
                tools[i].prevCPUTicks = 0
                tools[i].prevCSW = 0
                recentCompletions.removeAll { $0 == t.displayName }
                continue
            }
            if let info = snapshot[t.id] {
                nowRunning.insert(t.id)
                tools[i].pid = info.pid

                let hasBaseline = t.prevCPUTicks != 0 && elapsedNs > 0
                let deltaTicks = info.cpuTicks &- t.prevCPUTicks
                let deltaCSW = info.csw &- t.prevCSW
                tools[i].prevCPUTicks = info.cpuTicks
                tools[i].prevCSW = info.csw

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
                // Context switches per second: a sensitive activity signal.
                // Even I/O-waiting processes accumulate CSWs from callbacks.
                let elapsedSec = Double(elapsedNs) / 1_000_000_000.0
                let cswPerSec = elapsedSec > 0 ? Double(deltaCSW) / elapsedSec : 0
                var visitedPIDs = Set<pid_t>()
                let hasChildren = hasActiveChildren(parentPID: info.pid, in: childrenIndex, visited: &visitedPIDs)

                // State machine: idle ↔ working ↔ completed
                //
                // working:   has active children, or high CPU/CSW activity
                // completed: was working, activity just dropped (task finished)
                // idle:      process alive but inactive for 5s after completion
                let nowNs = DispatchTime.now().uptimeNanoseconds
                if hasChildren {
                    tools[i].status = .working
                    lastChildActiveTime[t.id] = nowNs
                } else if tools[i].status == .working {
                    let lastActive = lastChildActiveTime[t.id] ?? 0
                    let timeSinceChildren = nowNs &- lastActive
                    let hasActivity = cpuFraction >= Self.idleThreshold || cswPerSec >= 10.0
                    if hasActivity {
                        // Still active (thinking, processing API response)
                        tools[i].status = .working
                        lastChildActiveTime[t.id] = nowNs
                    } else if timeSinceChildren < Self.workingGraceNanos {
                        // Brief grace period — children might reappear between commands
                        // Stay working but don't update lastChildActiveTime
                    } else {
                        // Activity dropped and grace period expired → task completed
                        tools[i].status = .completed
                        lastCompletedTime[t.id] = nowNs
                        recentCompletions.append(t.displayName)
                        let name = t.displayName
                        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
                            self?.recentCompletions.removeAll { $0 == name }
                        }
                    }
                } else if tools[i].status == .completed {
                    // Check if activity resumed (new task started)
                    let isActive = cpuFraction >= Self.detectionThreshold || cswPerSec >= 30.0
                    if isActive {
                        tools[i].status = .working
                        lastChildActiveTime[t.id] = nowNs
                    } else {
                        // After 5 seconds in completed, transition to idle
                        let completedAt = lastCompletedTime[t.id] ?? 0
                        if completedAt > 0 && (nowNs &- completedAt) >= Self.completedToIdleNanos {
                            tools[i].status = .idle
                        }
                    }
                } else {
                    // Currently idle → check for new activity
                    let isActive = cpuFraction >= Self.detectionThreshold || cswPerSec >= 30.0
                    if isActive {
                        tools[i].status = .working
                        lastChildActiveTime[t.id] = nowNs
                    }
                }
            }
        }

        for i in tools.indices {
            // Disabled tools were already reset above — leave them alone.
            guard enabledTools.contains(tools[i].id) else { continue }
            if !nowRunning.contains(tools[i].id) {
                let prevStatus = tools[i].status
                if prevStatus == .working || prevStatus == .idle {
                    // Process disappeared while actively monitored → show completion
                    tools[i].status = .completed
                    recentCompletions.append(tools[i].displayName)
                    let name = tools[i].displayName
                    DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
                        self?.recentCompletions.removeAll { $0 == name }
                    }
                }
                // For any completed state (new or existing), schedule → notRunning
                if tools[i].status == .completed {
                    let toolID = tools[i].id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
                        guard let idx = self?.tools.firstIndex(where: { $0.id == toolID }) else { return }
                        if self?.tools[idx].status == .completed {
                            self?.tools[idx].status = .notRunning
                        }
                    }
                } else {
                    tools[i].status = .notRunning
                }
                tools[i].pid = nil
                tools[i].prevCPUTicks = 0
                tools[i].prevCSW = 0
            }
        }

        // When any tool is detected but not yet confirmed working, poll every
        // 1 s instead of the default 5 s. This dramatically increases the
        // chance of catching short-lived child processes.
        let anyDetectedIdle = nowRunning.contains { id in
            tools.contains { $0.id == id && $0.status != .working }
        }
        if anyDetectedIdle {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.refresh()
            }
        }
    }

    private struct ProcInfo {
        var pid: Int32
        var cpuTicks: UInt64
        var csw: UInt64
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
                let csw = UInt64(ti.pti_csw)
                surviving[toolID] = ProcInfo(pid: cached.pid, cpuTicks: cpuTicks, csw: csw)
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

    /// parent PID → its direct children (pid + raw process name).
    private typealias ChildrenIndex = [pid_t: [(pid: pid_t, name: String)]]

    /// Build a parent-PID → children map in a single pass over all processes,
    /// so the per-tool child-activity checks need no further syscalls.
    private func buildChildrenIndex() -> ChildrenIndex {
        var index: ChildrenIndex = [:]
        let capacity = Int(proc_listallpids(nil, 0))
        guard capacity > 0 else { return index }

        var pids = [pid_t](repeating: 0, count: capacity)
        let count = Int(proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.stride)))
        guard count > 0 else { return index }

        for i in 0..<count {
            let pid = pids[i]
            guard pid > 0 else { continue }
            var info = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.stride
            var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
            guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { continue }
            let ppid = info.kp_eproc.e_ppid
            let name = String(cString: withUnsafeBytes(of: info.kp_proc.p_comm) {
                $0.baseAddress!.assumingMemoryBound(to: CChar.self)
            })
            index[ppid, default: []].append((pid: pid, name: name))
        }
        return index
    }

    /// Whether `parentPID` has any child process that indicates real work
    /// (tool calls, file I/O, bash commands), resolved from the prebuilt
    /// index with no further syscalls. Always-present helpers like
    /// `caffeinate` (spawned by Claude Code to prevent sleep) are ignored.
    /// For persistent shell children (zsh, bash, etc.) kept alive by tools
    /// like Codex CLI, recurses to check whether the shell itself has active
    /// children — only then counts as "working". `visited` guards against
    /// pathological parent/child cycles.
    private func hasActiveChildren(parentPID: Int32, in index: ChildrenIndex, visited: inout Set<pid_t>) -> Bool {
        guard !visited.contains(parentPID) else { return false }
        visited.insert(parentPID)
        guard let children = index[parentPID] else { return false }

        for child in children {
            if Self.ignoredChildProcessNames.contains(child.name) {
                continue
            }
            if Self.shellProcessNames.contains(child.name) {
                // Shell child: only signal "working" if the shell itself
                // has active children (a running command).
                if hasActiveChildren(parentPID: child.pid, in: index, visited: &visited) {
                    return true
                }
                continue
            }
            return true
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
        // proc_listallpids returns PID count (not bytes) in both forms.
        let capacity = Int(proc_listallpids(nil, 0))
        guard capacity > 0 else { return [:] }

        var pids = [pid_t](repeating: 0, count: capacity)
        let pidCount = Int(proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.stride)))
        guard pidCount > 0 else { return [:] }

        // Only scan for tools the user has left enabled — disabled tools are
        // never matched, so they contribute nothing to the per-refresh scan.
        let enabled = DisplaySettings.shared.config.enabledToolIDs
        let monitorIDs = Set(tools.map(\.id)).intersection(enabled)
        guard !monitorIDs.isEmpty else { return [:] }
        var result: [String: ProcInfo] = [:]

        for i in 0..<pidCount {
            let pid = pids[i]
            guard pid > 0 else { continue }

            // Extract process name from kinfo_proc.p_comm — proc_name() returns
            // empty string on macOS 15.7.7.
            var nameInfo = kinfo_proc()
            var nameSize = MemoryLayout<kinfo_proc>.stride
            var nameMib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
            let nameResult = sysctl(&nameMib, 4, &nameInfo, &nameSize, nil, 0)
            let procName: String
            if nameResult == 0 {
                procName = String(cString: withUnsafeBytes(of: nameInfo.kp_proc.p_comm) { $0.baseAddress!.assumingMemoryBound(to: CChar.self) }).lowercased()
            } else {
                procName = ""
            }

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
            let csw: UInt64 = (ret > 0) ? UInt64(ti.pti_csw) : 0

            // Keep the PID with the highest CPU ticks for this tool.
            if let existing = result[matchedID] {
                if cpuTicks > existing.cpuTicks {
                    result[matchedID] = ProcInfo(pid: pid, cpuTicks: cpuTicks, csw: csw)
                }
            } else {
                result[matchedID] = ProcInfo(pid: pid, cpuTicks: cpuTicks, csw: csw)
            }
        }
        return result
    }
}
