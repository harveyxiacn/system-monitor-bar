import SwiftUI

// MARK: - Display Settings
//
// User-configurable selection of WHICH metrics are monitored and shown.
// Persisted as a single Codable blob in UserDefaults so the choices survive
// restarts. Three independent axes:
//   • menu-bar components (CPU%, memory, CPU/GPU temp, fan RPM)
//   • popover thermal groups (CPU / GPU / SSD / Memory / Battery / Ambient)
//   • which AI tools to scan for (disabled tools are skipped entirely, which
//     also avoids their share of the per-refresh process scan)

struct DisplayConfig: Codable, Equatable {
    // Menu-bar components
    var showCPU = true
    var showMemory = true
    var showCPUTemp = true
    var showGPUTemp = true
    var showFanSpeed = false

    // Popover thermals
    var visibleSensorGroups: Set<String> = Set(DisplayConfig.allSensorGroups)
    var showFansInPopover = true

    // AI tools (by tool id)
    var enabledToolIDs: Set<String> = Set(DisplayConfig.allToolIDs)

    static let allSensorGroups = ["CPU", "GPU", "SSD", "Memory", "Battery", "Ambient"]
    static let allToolIDs = ["codex", "claude", "aider", "windsurf", "opencode", "antigravity"]

    // Decoding tolerates older/partial blobs: any key absent from the stored
    // JSON falls back to the property's default above.
    enum CodingKeys: String, CodingKey {
        case showCPU, showMemory, showCPUTemp, showGPUTemp, showFanSpeed
        case visibleSensorGroups, showFansInPopover, enabledToolIDs
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var d = DisplayConfig()
        d.showCPU = try c.decodeIfPresent(Bool.self, forKey: .showCPU) ?? d.showCPU
        d.showMemory = try c.decodeIfPresent(Bool.self, forKey: .showMemory) ?? d.showMemory
        d.showCPUTemp = try c.decodeIfPresent(Bool.self, forKey: .showCPUTemp) ?? d.showCPUTemp
        d.showGPUTemp = try c.decodeIfPresent(Bool.self, forKey: .showGPUTemp) ?? d.showGPUTemp
        d.showFanSpeed = try c.decodeIfPresent(Bool.self, forKey: .showFanSpeed) ?? d.showFanSpeed
        d.visibleSensorGroups = try c.decodeIfPresent(Set<String>.self, forKey: .visibleSensorGroups) ?? d.visibleSensorGroups
        d.showFansInPopover = try c.decodeIfPresent(Bool.self, forKey: .showFansInPopover) ?? d.showFansInPopover
        d.enabledToolIDs = try c.decodeIfPresent(Set<String>.self, forKey: .enabledToolIDs) ?? d.enabledToolIDs
        self = d
    }
}

final class DisplaySettings: ObservableObject {
    static let shared = DisplaySettings()
    private let storageKey = "SystemMonitorBar.display"

    @Published var config: DisplayConfig {
        didSet { persist() }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(DisplayConfig.self, from: data) {
            config = decoded
        } else {
            config = DisplayConfig()
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    // CPU and GPU are always sampled regardless of popover visibility because the
    // menu-bar summary and the CSV temperature logger depend on them; only the
    // auxiliary groups are gated by the user's selection.
    var groupsToSample: Set<String> {
        config.visibleSensorGroups.union(["CPU", "GPU"])
    }

    // Convenience bindings for the Set-membership toggles in the settings UI.
    func sensorGroupBinding(_ group: String) -> Binding<Bool> {
        Binding(
            get: { self.config.visibleSensorGroups.contains(group) },
            set: { isOn in
                if isOn { self.config.visibleSensorGroups.insert(group) }
                else { self.config.visibleSensorGroups.remove(group) }
            }
        )
    }

    func toolBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { self.config.enabledToolIDs.contains(id) },
            set: { isOn in
                if isOn { self.config.enabledToolIDs.insert(id) }
                else { self.config.enabledToolIDs.remove(id) }
            }
        )
    }
}
