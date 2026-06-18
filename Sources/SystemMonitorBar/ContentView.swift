import SwiftUI

// MARK: - Popover

struct PopoverView: View {
    @ObservedObject var monitor: SystemMonitor
    @ObservedObject var aiMonitor: AIMonitor
    let loginItemEnabled: Bool
    let toggleLoginItem: () -> Void
    var onResize: ((NSSize) -> Void)?

    @State private var showSettings = false

    var body: some View {
        if showSettings {
            StatusSettingsView(isPresented: $showSettings, onResize: onResize)
        } else {
            VStack(spacing: 0) {
                // CPU section
                section(
                    icon: "cpu",
                    title: "CPU",
                    value: String(format: "%.1f%%", monitor.cpuUsage)
                ) {
                    Gauge(value: monitor.cpuUsage, in: 0...100) {}
                        .gaugeStyle(.accessoryLinearCapacity)
                        .tint(gaugeTint(monitor.cpuUsage))
                }

                Divider().padding(.horizontal, 14)

                // Memory section
                section(
                    icon: "memorychip",
                    title: "Memory",
                    value: memoryDetail
                ) {
                    let fraction = memoryFraction
                    Gauge(value: fraction, in: 0...1) {}
                        .gaugeStyle(.accessoryLinearCapacity)
                        .tint(memoryTint(fraction))
                }

                // Thermals section
                if !monitor.sensors.isEmpty {
                    thermalsSection
                    Divider().padding(.horizontal, 14)
                }

                // AI section
                VStack(alignment: .leading, spacing: 4) {
                    aiSectionHeader
                    ForEach(aiMonitor.tools.indices, id: \.self) { i in
                        aiRow(aiMonitor.tools[i])
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Divider().padding(.horizontal, 14)

                // Settings section
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label("Settings", systemImage: "gearshape")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            showSettings = true
                            onResize?(NSSize(width: 300, height: 580))
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .help("Status Display Settings")
                    }
                    .padding(.bottom, 2)

                    Toggle(isOn: .init(
                        get: { loginItemEnabled },
                        set: { _ in toggleLoginItem() }
                    )) {
                        Text("Launch at Login")
                            .font(.system(size: 12, weight: .regular))
                    }
                    .toggleStyle(.switch)
                    .padding(.vertical, 2)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Divider().padding(.horizontal, 14)

                // Quit
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    HStack {
                        Spacer()
                        Text("Quit")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .onAppear {
                onResize?(NSSize(width: 300, height: 420))
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private var thermalsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("Thermals", systemImage: "thermometer.medium")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.bottom, 2)

            ForEach(monitor.sensors) { sensor in
                HStack(spacing: 8) {
                    Circle()
                        .fill(temperatureColor(sensor.temperature))
                        .frame(width: 7, height: 7)
                    Text(sensor.displayName)
                        .font(.system(size: 12, weight: .regular))
                    Spacer()
                    Text(String(format: "%.1f°C", sensor.temperature))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(temperatureColor(sensor.temperature))
                }
                .padding(.vertical, 1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func temperatureColor(_ temp: Double) -> Color {
        switch temp {
        case ..<50:  return .blue
        case 50..<70: return .green
        case 70..<80: return .cyan
        case 80..<90: return .orange
        default:      return .red
        }
    }

    private var memoryDetail: String {
        let used = Double(monitor.memoryUsed) / 1_073_741_824.0
        let total = Double(monitor.memoryTotal) / 1_073_741_824.0
        return String(format: "%.1f / %.0f GB", used, total)
    }

    private var memoryFraction: Double {
        guard monitor.memoryTotal > 0 else { return 0 }
        return Double(monitor.memoryUsed) / Double(monitor.memoryTotal)
    }

    @ViewBuilder
    private func section(
        icon: String,
        title: String,
        value: String,
        @ViewBuilder gauge: () -> some View
    ) -> some View {
        VStack(spacing: 8) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
            }
            gauge()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var aiSectionHeader: some View {
        HStack {
            Label("AI Agents", systemImage: "brain.head.profile")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text("Click pin to show in menu bar")
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(.tertiary)
        }
        .padding(.bottom, 2)
    }

    private func aiRow(_ tool: AIToolStatus) -> some View {
        HStack(spacing: 8) {
            statusIconView(for: tool.status)
            Text(tool.displayName)
                .font(.system(size: 12, weight: .regular))
            Spacer()
            Text(statusText(for: tool.status))
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.secondary)
            Button {
                aiMonitor.togglePin(tool.id)
            } label: {
                Label("Pin", systemImage: tool.pinned ? "pin.fill" : "pin")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 10))
                    .foregroundStyle(tool.pinned ? Color.blue : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(tool.pinned ? "Unpin from menu bar" : "Pin to menu bar")
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func statusIconView(for status: AIStatus) -> some View {
        let appearance = ThemeManager.shared.currentTheme.appearance(for: status)

        switch appearance.iconType {
        case .colorDot:
            if appearance.animation == .pulse && status == .working {
                PulsingCircle(color: appearance.color.color, size: 8)
            } else {
                Circle()
                    .fill(appearance.color.color)
                    .frame(width: 8, height: 8)
            }
        case .emoji:
            Text(appearance.iconValue.isEmpty ? "●" : appearance.iconValue)
                .font(.system(size: 12))
        case .sfSymbol:
            Image(systemName: appearance.iconValue)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(appearance.color.color)
                .frame(width: 14, height: 14)
        }
    }

    private func statusText(for status: AIStatus) -> String {
        ThemeManager.shared.currentTheme.appearance(for: status).label
    }

    private func gaugeTint(_ value: Double) -> Color {
        switch value {
        case 0..<30:  return .green
        case 30..<60: return .cyan
        case 60..<85: return .orange
        default:      return .red
        }
    }

    private func memoryTint(_ fraction: Double) -> Color {
        switch fraction {
        case 0..<0.5:  return .green
        case 0.5..<0.7: return .cyan
        case 0.7..<0.85: return .orange
        default:        return .red
        }
    }
}

// MARK: - Pulsing Circle

struct PulsingCircle: View {
    let color: Color
    let size: CGFloat

    @State private var opacity: CGFloat = 1.0

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    opacity = 0.3
                }
            }
    }
}

// MARK: - Status Settings View

struct StatusSettingsView: View {
    @Binding var isPresented: Bool
    var onResize: ((NSSize) -> Void)?

    @ObservedObject private var themeManager = ThemeManager.shared

    @State private var working: StatusAppearance
    @State private var idle: StatusAppearance
    @State private var completed: StatusAppearance
    @State private var notRunning: StatusAppearance
    @State private var selectedPresetID: String
    @State private var isPresetApplication = false

    init(isPresented: Binding<Bool>, onResize: ((NSSize) -> Void)? = nil) {
        self._isPresented = isPresented
        self.onResize = onResize
        let theme = ThemeManager.shared.currentTheme
        self._working    = State(initialValue: theme.working)
        self._idle       = State(initialValue: theme.idle)
        self._completed  = State(initialValue: theme.completed)
        self._notRunning = State(initialValue: theme.notRunning)

        // Attempt to match a built‑in preset; otherwise mark as custom.
        let matched = ThemePreset.allPresets.first { p in
            p.working == theme.working && p.idle == theme.idle &&
            p.completed == theme.completed && p.notRunning == theme.notRunning
        }
        self._selectedPresetID = State(initialValue: matched?.id ?? "custom")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack {
                    Button {
                        saveTheme()
                        isPresented = false
                        onResize?(NSSize(width: 300, height: 420))
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)

                    Spacer()

                    Text("Status Display")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Spacer()
                }

                // Theme preset
                VStack(alignment: .leading, spacing: 6) {
                    Text("Theme Preset")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Picker("", selection: $selectedPresetID) {
                        ForEach(ThemePreset.allPresets) { preset in
                            Text(preset.name).tag(preset.id)
                        }
                        Text("Custom").tag("custom")
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                // Live preview
                VStack(alignment: .leading, spacing: 6) {
                    Text("Preview")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        previewBadge(appearance: working, label: "Working")
                        previewBadge(appearance: idle, label: "Idle")
                        previewBadge(appearance: completed, label: "Done")
                    }
                }

                Divider()

                // Per‑status settings
                StatusConfigSection(title: "Working", appearance: $working, onChange: onCustomize)
                StatusConfigSection(title: "Idle", appearance: $idle, onChange: onCustomize)
                StatusConfigSection(title: "Completed", appearance: $completed, onChange: onCustomize)
                StatusConfigSection(title: "Not Running", appearance: $notRunning, onChange: onCustomize)

                // Reset
                HStack {
                    Spacer()
                    Button("Reset to Defaults", role: .destructive) {
                        applyPreset(.trafficLight)
                    }
                    .controlSize(.small)
                }
                .padding(.top, 4)
            }
            .padding(16)
        }
        .onChange(of: selectedPresetID) { _, newID in
            guard !isPresetApplication, newID != "custom" else { return }
            guard let preset = ThemePreset.allPresets.first(where: { $0.id == newID }) else { return }
            applyPreset(preset)
        }
    }

    // MARK: - Preview Badge

    private func previewBadge(appearance: StatusAppearance, label: String) -> some View {
        HStack(spacing: 4) {
            switch appearance.iconType {
            case .colorDot:
                Circle()
                    .fill(appearance.color.color)
                    .frame(width: 7, height: 7)
            case .emoji:
                Text(appearance.iconValue.isEmpty ? "●" : appearance.iconValue)
                    .font(.system(size: 10))
            case .sfSymbol:
                Image(systemName: appearance.iconValue)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(appearance.color.color)
            }
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.1))
        )
    }

    // MARK: - Actions

    private func applyPreset(_ preset: ThemePreset) {
        isPresetApplication = true
        selectedPresetID = preset.id
        working   = preset.working
        idle      = preset.idle
        completed = preset.completed
        notRunning = preset.notRunning
        saveTheme()
        // Allow onChange to fire naturally on next interaction
        DispatchQueue.main.async { isPresetApplication = false }
    }

    private func saveTheme() {
        var theme = themeManager.currentTheme
        theme.working    = working
        theme.idle       = idle
        theme.completed  = completed
        theme.notRunning = notRunning
        themeManager.currentTheme = theme
    }

    private func onCustomize() {
        selectedPresetID = "custom"
        saveTheme()
    }
}

// MARK: - Status Config Section

struct StatusConfigSection: View {
    let title: String
    @Binding var appearance: StatusAppearance
    let onChange: () -> Void

    @State private var showEmojiPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)

            // Icon type
            Picker("Icon Type", selection: Binding(
                get: { appearance.iconType },
                set: { appearance.iconType = $0; onChange() }
            )) {
                ForEach(StatusIconType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            // Conditional inputs
            if appearance.iconType == .emoji {
                emojiPicker
            }

            if appearance.iconType == .sfSymbol {
                TextField("SF Symbol (e.g. bolt.fill)", text: Binding(
                    get: { appearance.iconValue },
                    set: { appearance.iconValue = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .onSubmit(onChange)
            }

            // Label
            TextField("Label", text: Binding(
                get: { appearance.label },
                set: { appearance.label = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12))
            .onSubmit(onChange)

            // Color
            ColorPicker("Color", selection: Binding(
                get: { appearance.color.color },
                set: { appearance.color = CodableColor(color: $0); onChange() }
            ))
            .font(.system(size: 11))

            // Animation (working only)
            if title == "Working" {
                Picker("Animation", selection: Binding(
                    get: { appearance.animation },
                    set: { appearance.animation = $0; onChange() }
                )) {
                    ForEach(StatusAnimation.allCases) { anim in
                        Text(anim.displayName).tag(anim)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.05))
        )
    }

    @ViewBuilder
    private var emojiPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(appearance.iconValue.isEmpty ? "🙂" : appearance.iconValue)
                    .font(.system(size: 18))
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.secondary.opacity(0.12))
                    )

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { showEmojiPicker.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "face.smiling")
                        Text(showEmojiPicker ? "Hide" : "Choose Emoji")
                        Image(systemName: showEmojiPicker ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8))
                    }
                    .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)

                Spacer()
            }

            if showEmojiPicker {
                EmojiPickerGrid(selection: appearance.iconValue) { picked in
                    appearance.iconValue = picked
                    onChange()
                }
            }
        }
    }
}

// MARK: - Emoji Picker Grid

struct EmojiPickerGrid: View {
    let selection: String
    let onPick: (String) -> Void

    @State private var custom = ""

    private let columns = Array(repeating: GridItem(.fixed(30), spacing: 4), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(StatusEmojiCatalog.all, id: \.self) { emoji in
                    Button {
                        onPick(emoji)
                    } label: {
                        Text(emoji)
                            .font(.system(size: 17))
                            .frame(width: 30, height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(emoji == selection
                                          ? Color.accentColor.opacity(0.30)
                                          : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 6) {
                TextField("Or type your own…", text: $custom)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .onSubmit(useCustom)
                Button("Use", action: useCustom)
                    .controlSize(.small)
                    .disabled(custom.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.top, 2)
    }

    private func useCustom() {
        let trimmed = custom.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onPick(trimmed)
        custom = ""
    }
}
