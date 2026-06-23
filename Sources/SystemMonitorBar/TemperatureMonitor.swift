import Foundation
import IOKit

// MARK: - SMC Raw Interface
//
// Uses raw byte buffers matching the C SMCKeyData_t struct layout from osx-cpu-temp.
// Layout (80 bytes):
//   key:0(4) vers:4(6) pad:10(2) pLimitData:12(16) keyInfo:28(12)
//   result:40(1) status:41(1) data8:42(1) pad:43(1) data32:44(4) bytes:48(32)
//
// All multi-byte fields use NATIVE byte order (little-endian on x86_64).

private let SMC_BUF_SIZE = 80
private let OFF_KEY      = 0
private let OFF_DATA8    = 42
private let OFF_DATASIZE = 28
private let OFF_DATATYPE = 32
private let OFF_BYTES    = 48

private let SMC_CMD_READ_KEYINFO: UInt8 = 9
private let SMC_CMD_READ_BYTES: UInt8 = 5

private func smcKey(_ str: String) -> UInt32 {
    var k: UInt32 = 0
    for (i, byte) in str.utf8.prefix(4).enumerated() {
        k |= UInt32(byte) << UInt32(8 * (3 - i))
    }
    return k
}

private func readU32(_ ptr: UnsafeRawPointer, _ off: Int) -> UInt32 {
    (ptr + off).load(as: UInt32.self)
}

private func writeU32(_ ptr: UnsafeMutableRawPointer, _ off: Int, _ val: UInt32) {
    (ptr + off).storeBytes(of: val, as: UInt32.self)
}

// MARK: - Temperature Sensor

struct TemperatureSensor: Identifiable {
    let id: String
    let group: String
    let displayName: String
    var temperature: Double
}

// MARK: - Temperature Monitor

final class TemperatureMonitor: ObservableObject {
    @Published var sensors: [TemperatureSensor] = []
    @Published var cpuTemperature: Double?
    @Published var gpuTemperature: Double?
    @Published var fanSpeeds: [Double] = []

    private var connection: io_connect_t = 0

    private static let sensorGroups: [(group: String, keys: [(key: String, name: String)])] = [
        ("CPU", [
            ("TC0E", "CPU Die"), ("TC0P", "CPU Proximity"),
            ("TC1C", "Core 1"), ("TC2C", "Core 2"),
            ("TC3C", "Core 3"), ("TC4C", "Core 4"),
            ("TC5C", "Core 5"), ("TC6C", "Core 6"),
            ("TC7C", "Core 7"), ("TC8C", "Core 8"),
        ]),
        ("GPU", [
            ("TG0D", "GPU Die"), ("TG0P", "GPU Proximity"),
        ]),
        ("SSD", [
            ("Ts0P", "SSD"),
        ]),
        ("Memory", [
            ("TM0P", "Memory"),
        ]),
        ("Battery", [
            ("TB0T", "Battery"),
        ]),
        ("Ambient", [
            ("TA0P", "Ambient"),
        ]),
    ]

    init() {
        openSMC()
    }

    deinit {
        closeSMC()
    }

    /// Samples every sensor in `groups`. Groups the user has hidden are skipped
    /// entirely, so their SMC reads (two IOKit round-trips each) never happen.
    func update(groups: Set<String> = Set(DisplayConfig.allSensorGroups)) {
        var results: [TemperatureSensor] = []
        var bestCPUTemp: Double?
        var bestGPUTemp: Double?

        for group in Self.sensorGroups where groups.contains(group.group) {
            for entry in group.keys {
                if let temp = readSMCValue(key: entry.key) {
                    results.append(TemperatureSensor(
                        id: entry.key,
                        group: group.group,
                        displayName: entry.name,
                        temperature: temp
                    ))
                    if group.group == "CPU" {
                        if bestCPUTemp == nil || entry.key == "TC0E" || entry.key == "TC0P" {
                            bestCPUTemp = temp
                        }
                    }
                    if group.group == "GPU" {
                        if bestGPUTemp == nil || entry.key == "TG0D" || entry.key == "TG0P" {
                            bestGPUTemp = temp
                        }
                    }
                }
            }
        }

        if bestCPUTemp == nil {
            let cpuTemps = results.filter { $0.group == "CPU" }.map { $0.temperature }
            if !cpuTemps.isEmpty {
                bestCPUTemp = cpuTemps.max()
            }
        }
        if bestGPUTemp == nil {
            let gpuTemps = results.filter { $0.group == "GPU" }.map { $0.temperature }
            if !gpuTemps.isEmpty {
                bestGPUTemp = gpuTemps.max()
            }
        }
        // Fan RPM uses the same SMC value path (fpe2-encoded on this hardware).
        // Most Macs expose F0Ac/F1Ac; missing keys simply return nil and are skipped.
        var fans: [Double] = []
        for key in ["F0Ac", "F1Ac"] {
            if let rpm = readSMCValue(key: key) {
                fans.append(rpm)
            }
        }

        self.sensors = results
        self.cpuTemperature = bestCPUTemp
        self.gpuTemperature = bestGPUTemp
        self.fanSpeeds = fans
    }

    // MARK: - SMC Interface

    private func openSMC() {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSMC")
        )
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }

        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        if result != kIOReturnSuccess {
            connection = 0
        }
    }

    private func closeSMC() {
        if connection != 0 {
            IOServiceClose(connection)
            connection = 0
        }
    }

    // Reads any numeric SMC key (temperature in °C, fan RPM, etc.) via the
    // shared sp78/sp4e/fpe2/flt decoding. The key's own data type selects the unit.
    private func readSMCValue(key: String) -> Double? {
        guard connection != 0 else { return nil }

        let smcKeyVal = smcKey(key)

        // Step 1: READ_KEYINFO — get data type and size
        let input = UnsafeMutableRawPointer.allocate(byteCount: SMC_BUF_SIZE, alignment: 4)
        let output = UnsafeMutableRawPointer.allocate(byteCount: SMC_BUF_SIZE, alignment: 4)
        defer { input.deallocate(); output.deallocate() }

        memset(input, 0, SMC_BUF_SIZE)
        memset(output, 0, SMC_BUF_SIZE)
        writeU32(input, OFF_KEY, smcKeyVal)
        (input + OFF_DATA8).storeBytes(of: SMC_CMD_READ_KEYINFO, as: UInt8.self)

        var outputSize = SMC_BUF_SIZE
        var kr = IOConnectCallStructMethod(
            connection, UInt32(2), input, SMC_BUF_SIZE, output, &outputSize
        )
        guard kr == kIOReturnSuccess else { return nil }

        let dataType = readU32(output, OFF_DATATYPE)
        let dataSize = readU32(output, OFF_DATASIZE)
        guard dataSize > 0 else { return nil }

        // Step 2: READ_BYTES — get the actual value
        memset(input, 0, SMC_BUF_SIZE)
        memset(output, 0, SMC_BUF_SIZE)
        writeU32(input, OFF_KEY, smcKeyVal)
        (input + OFF_DATA8).storeBytes(of: SMC_CMD_READ_BYTES, as: UInt8.self)
        writeU32(input, OFF_DATASIZE, dataSize)
        writeU32(input, OFF_DATATYPE, dataType)

        outputSize = SMC_BUF_SIZE
        kr = IOConnectCallStructMethod(
            connection, UInt32(2), input, SMC_BUF_SIZE, output, &outputSize
        )
        guard kr == kIOReturnSuccess else { return nil }

        let b0 = (output + OFF_BYTES).load(as: UInt8.self)
        let b1 = (output + OFF_BYTES + 1).load(as: UInt8.self)

        return interpretTemperature(dataType: dataType, dataSize: dataSize, b0: b0, b1: b1)
    }

    private func interpretTemperature(dataType: UInt32, dataSize: UInt32, b0: UInt8, b1: UInt8) -> Double? {
        // On little-endian, the kernel stores type codes as native UInt32.
        // Kernel returns type codes in the same byte order as smcKey().
        // Direct comparison — no byte-swapping needed.
        let sp78 = smcKey("sp78")
        let sp4e = smcKey("sp4e")
        let fpe2 = smcKey("fpe2")
        let flt  = smcKey("flt ")

        if dataType == sp78 && dataSize >= 2 {
            let raw = Int16(b0) << 8 | Int16(b1)
            return Double(raw) / 256.0
        }
        if dataType == sp4e && dataSize >= 2 {
            let raw = Int16(b0) << 8 | Int16(b1)
            return Double(raw) / 4096.0
        }
        if dataType == fpe2 && dataSize >= 2 {
            let raw = UInt16(b0) << 8 | UInt16(b1)
            return Double(raw) / 4.0
        }
        if dataType == flt && dataSize >= 4 {
            var val: Float = 0
            withUnsafeMutableBytes(of: &val) { buf in
                buf[0] = b0; buf[1] = b1
            }
            return Double(val)
        }

        return nil
    }
}
