import Foundation

// MARK: - Temperature Logger
//
// Appends a periodic snapshot of CPU/GPU temperatures and fan speeds to a CSV
// at ~/Library/Application Support/SystemMonitorBar/temp-history.csv. Sampling
// is throttled to one row per `logInterval` regardless of how often the caller
// fires, and rows older than `retentionDays` are pruned on a slow cadence so the
// file stays small (~700 KB for a week). The goal is a lightweight historical
// record for before/after comparisons (e.g. evaluating a thermal-paste change).

final class TemperatureLogger {
    private let fileURL: URL
    private let logInterval: TimeInterval = 60
    private let retentionDays: Double = 7
    private let pruneInterval: TimeInterval = 3600

    private var lastLogTime: Date?
    private var lastPruneTime: Date?
    private let ioQueue = DispatchQueue(label: "com.systemmonitor.bar.templogger", qos: .utility)

    private static let header = "timestamp,cpu_usage,cpu_die,cpu_proximity,core_max,gpu,fan0_rpm,fan1_rpm\n"

    init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SystemMonitorBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("temp-history.csv")

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try? Self.header.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    /// Records one snapshot if at least `logInterval` has elapsed since the last.
    /// Safe to call on every monitor tick — extra calls are dropped cheaply.
    /// Expected to be called on the main thread; file I/O is offloaded.
    func record(cpuUsage: Double, sensors: [TemperatureSensor], fans: [Double]) {
        let now = Date()
        if let last = lastLogTime, now.timeIntervalSince(last) < logInterval { return }
        lastLogTime = now

        let die = sensors.first { $0.id == "TC0E" }?.temperature
        let proximity = sensors.first { $0.id == "TC0P" }?.temperature
        let coreMax = sensors
            .filter { $0.group == "CPU" && $0.id.hasSuffix("C") }
            .map { $0.temperature }
            .max()
        let gpu = sensors.first { $0.group == "GPU" }?.temperature
        let fan0 = fans.indices.contains(0) ? fans[0] : nil
        let fan1 = fans.indices.contains(1) ? fans[1] : nil

        func num(_ value: Double?, _ format: String) -> String {
            value.map { String(format: format, $0) } ?? ""
        }
        let ts = ISO8601DateFormatter().string(from: now)
        let line = [
            ts,
            num(cpuUsage, "%.0f"),
            num(die, "%.1f"),
            num(proximity, "%.1f"),
            num(coreMax, "%.1f"),
            num(gpu, "%.1f"),
            num(fan0, "%.0f"),
            num(fan1, "%.0f"),
        ].joined(separator: ",") + "\n"

        ioQueue.async { [self] in
            append(line)
            maybePrune(now: now)
        }
    }

    // MARK: - File I/O (ioQueue only)

    private func append(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(data)
        } else {
            // File vanished (e.g. user deleted it) — recreate with header + row.
            try? (Self.header + line).write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    private func maybePrune(now: Date) {
        if let last = lastPruneTime, now.timeIntervalSince(last) < pruneInterval { return }
        lastPruneTime = now

        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        guard lines.count > 1 else { return }

        let cutoff = now.addingTimeInterval(-retentionDays * 86_400)
        let parser = ISO8601DateFormatter()
        var kept = [String(Self.header.dropLast())]  // header without trailing newline
        for line in lines.dropFirst() {
            let timestamp = line.prefix { $0 != "," }
            if let date = parser.date(from: String(timestamp)), date >= cutoff {
                kept.append(String(line))
            }
        }
        let rebuilt = kept.joined(separator: "\n") + "\n"
        try? rebuilt.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
