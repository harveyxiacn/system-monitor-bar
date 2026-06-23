import Foundation
import Darwin

final class SystemMonitor: ObservableObject {
    @Published var cpuUsage: Double = 0
    @Published var memoryUsed: UInt64 = 0
    @Published var memoryTotal: UInt64 = 0
    @Published var cpuTemperature: Double? = nil
    @Published var gpuTemperature: Double? = nil
    @Published var sensors: [TemperatureSensor] = []
    @Published var fanSpeeds: [Double] = []

    let temperatureMonitor = TemperatureMonitor()
    private let temperatureLogger = TemperatureLogger()

    private var previousCPUTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?
    private var timer: Timer?
    private let updateInterval: TimeInterval = 2.0

    init() {
        sampleCPU()
        updateMemory()
        sampleTemperatures()
        timer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        sampleCPU()
        updateMemory()
        sampleTemperatures()
        temperatureLogger.record(
            cpuUsage: cpuUsage,
            sensors: temperatureMonitor.sensors,
            fans: temperatureMonitor.fanSpeeds
        )
    }

    private func sampleTemperatures() {
        temperatureMonitor.update(groups: DisplaySettings.shared.groupsToSample)
        sensors = temperatureMonitor.sensors
        cpuTemperature = temperatureMonitor.cpuTemperature
        gpuTemperature = temperatureMonitor.gpuTemperature
        fanSpeeds = temperatureMonitor.fanSpeeds
    }

    // MARK: - CPU

    private func sampleCPU() {
        let ticks = readCPUTicks()
        guard let ticks else { return }

        if let prev = previousCPUTicks {
            let userDelta   = ticks.user   &- prev.user
            let systemDelta = ticks.system &- prev.system
            let idleDelta   = ticks.idle   &- prev.idle
            let niceDelta   = ticks.nice   &- prev.nice
            let totalDelta  = userDelta &+ systemDelta &+ idleDelta &+ niceDelta

            if totalDelta > 0 {
                let usedDelta = userDelta &+ systemDelta &+ niceDelta
                let raw = Double(usedDelta) / Double(totalDelta) * 100.0
                let clamped = min(max(raw, 0), 100)
                Task { @MainActor in
                    self.cpuUsage = clamped
                }
            }
        }
        previousCPUTicks = ticks
    }

    private func readCPUTicks() -> (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)? {
        var cpuLoadInfo = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &cpuLoadInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        return (
            user:   UInt64(cpuLoadInfo.cpu_ticks.0),
            system: UInt64(cpuLoadInfo.cpu_ticks.1),
            idle:   UInt64(cpuLoadInfo.cpu_ticks.2),
            nice:   UInt64(cpuLoadInfo.cpu_ticks.3)
        )
    }

    // MARK: - Memory

    private func updateMemory() {
        guard let pageSize = hostPageSize(),
              let vmStat = readVMStatistics() else { return }

        var physMem: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &physMem, &size, nil, 0)

        let pageSize64 = UInt64(pageSize)
        // Active + Wired + Compressed pages = what's actually consuming RAM.
        // compressor_page_count reflects pages held in RAM by the compressor;
        // excluding inactive/cached file pages which macOS can reclaim instantly.
        let used = (UInt64(vmStat.active_count) &+ UInt64(vmStat.wire_count) &+ UInt64(vmStat.compressor_page_count)) &* pageSize64

        Task { @MainActor in
            self.memoryTotal = physMem
            self.memoryUsed  = used
        }
    }

    private func hostPageSize() -> vm_size_t? {
        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else { return nil }
        return pageSize
    }

    private func readVMStatistics() -> vm_statistics64? {
        var vmStat = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &vmStat) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return vmStat
    }
}
