import SwiftUI

// MARK: - Icon Type

enum StatusIconType: String, CaseIterable, Codable, Identifiable {
    case colorDot
    case emoji
    case sfSymbol

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .colorDot: return "● Dot"
        case .emoji:    return "🔤 Emoji"
        case .sfSymbol: return "◆ Symbol"
        }
    }
}

// MARK: - Animation

enum StatusAnimation: String, CaseIterable, Codable, Identifiable {
    case none
    case pulse

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .none:  return "None"
        case .pulse: return "Pulse"
        }
    }
}

// MARK: - Emoji Catalog

enum StatusEmojiCatalog {
    /// Curated emoji that stay legible at menu-bar / badge size, grouped loosely
    /// by the status they suit (active · resting · done · indicators).
    static let all: [String] = [
        "🔥", "⚡", "🚀", "✨", "💪", "🏃", "⌛", "🔄", "🛠️", "⚙️",
        "🧠", "🤖", "💻", "📡", "🎯", "👀", "💡", "🐢", "🐇", "🌀",
        "☕", "💤", "🌙", "🛌", "🧘", "🍵", "❄️", "🌊", "🪨", "🍃",
        "✅", "✔️", "🎉", "🎊", "🏁", "🥳", "💯", "⭐", "🌟", "🙌",
        "🟢", "🟡", "🟠", "🔴", "🔵", "🟣", "⚫", "⚪", "🟤", "🔘",
    ]
}

// MARK: - Codable Color

struct CodableColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var opacity: Double

    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: opacity)
    }
    var nsColor: NSColor {
        NSColor(red: red, green: green, blue: blue, alpha: opacity)
    }

    init(red: Double, green: Double, blue: Double, opacity: Double = 1.0) {
        self.red = red; self.green = green; self.blue = blue; self.opacity = opacity
    }

    init(color: Color) {
        let ns = NSColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.red = Double(r); self.green = Double(g); self.blue = Double(b); self.opacity = Double(a)
    }
}

extension CodableColor {
    static let red       = CodableColor(red: 1.0,    green: 0.231, blue: 0.188)
    static let orange    = CodableColor(red: 1.0,    green: 0.584, blue: 0.0)
    static let yellow    = CodableColor(red: 1.0,    green: 0.8,   blue: 0.0)
    static let green     = CodableColor(red: 0.298,  green: 0.851, blue: 0.392)
    static let blue      = CodableColor(red: 0.0,    green: 0.478, blue: 1.0)
    static let gray      = CodableColor(red: 0.557,  green: 0.557, blue: 0.576)
    static let black     = CodableColor(red: 0.0,    green: 0.0,   blue: 0.0)
    static let lightGray = CodableColor(red: 0.557,  green: 0.557, blue: 0.576, opacity: 0.3)
}

// MARK: - Status Appearance

struct StatusAppearance: Codable, Equatable {
    var iconType:  StatusIconType
    var iconValue: String
    var color:     CodableColor
    var label:     String
    var animation: StatusAnimation

    /// Short symbol used in the constrained menu‑bar space.
    var menuSymbol: String {
        switch iconType {
        case .colorDot, .sfSymbol: return "●"
        case .emoji:               return iconValue.isEmpty ? "●" : iconValue
        }
    }
}

extension StatusAppearance {
    static func dot(_ color: CodableColor, label: String, animation: StatusAnimation = .none) -> Self {
        Self(iconType: .colorDot, iconValue: "", color: color, label: label, animation: animation)
    }
    static func emoji(_ e: String, color: CodableColor, label: String, animation: StatusAnimation = .none) -> Self {
        Self(iconType: .emoji, iconValue: e, color: color, label: label, animation: animation)
    }
    static func sfSymbol(_ name: String, color: CodableColor, label: String, animation: StatusAnimation = .none) -> Self {
        Self(iconType: .sfSymbol, iconValue: name, color: color, label: label, animation: animation)
    }
}

// MARK: - Theme Preset

struct ThemePreset: Codable, Identifiable {
    var id:   String
    var name: String
    var working:    StatusAppearance
    var idle:       StatusAppearance
    var completed:  StatusAppearance
    var notRunning: StatusAppearance

    func appearance(for status: AIStatus) -> StatusAppearance {
        switch status {
        case .working:    return working
        case .idle:       return idle
        case .completed:  return completed
        case .notRunning: return notRunning
        }
    }
}

// MARK: - Built-in Presets

extension ThemePreset {
    static let trafficLight = ThemePreset(
        id: "traffic-light", name: "Traffic Light",
        working:    .dot(.red,    label: "Working"),
        idle:       .dot(.yellow, label: "Idle"),
        completed:  .dot(.green,  label: "Done"),
        notRunning: .dot(.lightGray, label: "Off")
    )

    static let emojiFun = ThemePreset(
        id: "emoji-fun", name: "Emoji Fun",
        working:    .emoji("🔥", color: .red,    label: "On Fire"),
        idle:       .emoji("☕", color: .orange,  label: "Chill"),
        completed:  .emoji("✅", color: .green,   label: "Done"),
        notRunning: .emoji("💤", color: .gray,    label: "Off")
    )

    static let pulse = ThemePreset(
        id: "pulse", name: "Pulse",
        working:    .dot(.red,  label: "Working", animation: .pulse),
        idle:       .dot(.yellow, label: "Idle"),
        completed:  .dot(.green, label: "Done"),
        notRunning: .dot(.lightGray, label: "Off")
    )

    static let sfSymbols = ThemePreset(
        id: "sf-symbols", name: "SF Symbols",
        working:    .sfSymbol("bolt.fill",            color: .red,    label: "Working"),
        idle:       .sfSymbol("moon.fill",            color: .orange, label: "Idle"),
        completed:  .sfSymbol("checkmark.circle.fill", color: .green,  label: "Done"),
        notRunning: .sfSymbol("poweroff",             color: .lightGray, label: "Off")
    )

    static let monochrome = ThemePreset(
        id: "monochrome", name: "Minimal",
        working:    .dot(.black, label: "Active"),
        idle:       .sfSymbol("circle", color: CodableColor(red: 0.5, green: 0.5, blue: 0.5), label: "Standby"),
        completed:  .sfSymbol("checkmark", color: .black, label: "Complete"),
        notRunning: .sfSymbol("minus", color: .lightGray, label: "Off")
    )

    static let allPresets: [ThemePreset] = [trafficLight, emojiFun, pulse, sfSymbols, monochrome]
}

// MARK: - Theme Manager

final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published var currentTheme: ThemePreset {
        didSet { persist() }
    }

    private let storageKey = "SystemMonitorBar.theme"

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let theme = try? JSONDecoder().decode(ThemePreset.self, from: data) {
            currentTheme = theme
        } else {
            currentTheme = .trafficLight
        }
    }

    func applyPreset(_ preset: ThemePreset) {
        currentTheme = preset
    }

    func resetToDefaults() {
        currentTheme = .trafficLight
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(currentTheme) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
