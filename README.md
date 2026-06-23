# System Monitor Bar

A lightweight macOS menu bar app that displays real-time system metrics and tracks AI agent activity — CPU usage, memory, temperatures, fan speed, and process-level status for Codex, Claude Code, Aider, Windsurf, OpenCode, and Antigravity.

![Screenshot](.github/screenshot.png)

## Features

- **Real-time CPU & memory** — uses `host_statistics` Mach API for sub-second CPU sampling and accurate memory (active + wired + compressed pages).
- **Temperature & fan monitoring** — reads CPU/GPU temperatures and fan RPM via SMC (IOKit `AppleSMC` interface) with `sp78`/`sp4e`/`fpe2`/`flt` decoding.
- **AI agent monitoring** — detects whether AI tools are running, actively working (child process + CPU + context-switch analysis), completed, or idle.
- **Configurable display** — choose exactly what to monitor and show: which menu-bar fields, which thermal groups, fan speeds, and which AI tools. Disabled AI tools are skipped during scanning entirely.
- **Menu bar pinning** — pin any AI tool to the menu bar for at-a-glance status: `Cx:⚡` (working), `Cc:●` (idle), `Aid:✓` (completed).
- **Launch at login** — built-in toggle using `SMAppService`.
- **Zero Dock footprint** — `LSUIElement=true`, exists only in the menu bar.
- **Persistent settings** — display choices, pinned tools, and theme survive restarts via UserDefaults.

## Requirements

- macOS 14 (Sonoma) or later
- To build from source: a Swift 6 toolchain (Xcode 16+ or recent Command Line Tools) — the sources rely on Swift 6 region-based isolation

## Install

### Option A — Download (recommended)

1. Grab the latest `.dmg` from the [**Releases**](https://github.com/harveyxiacn/system-monitor-bar/releases) page (universal: Apple Silicon + Intel).
2. Open it and drag **SystemMonitorBar** into **Applications**.
3. First launch: right-click the app → **Open**, then **Open** again.

> [!NOTE]
> The app is open-source and **not paid-notarized by Apple**, so macOS Gatekeeper
> flags it on first open. If you see *"damaged"* or *"cannot verify the developer"*,
> clear the quarantine flag once:
> ```bash
> xattr -dr com.apple.quarantine /Applications/SystemMonitorBar.app
> ```
> Then open it normally. This only needs to be done once.

### Option B — Build from source

```bash
git clone https://github.com/harveyxiacn/system-monitor-bar.git
cd system-monitor-bar
./build.sh
open SystemMonitorBar.app
```

Locally built apps aren't quarantined, so no Gatekeeper step is needed. Enable
"Launch at Login" from the popover's Settings section.

## Usage

| Action | What it does |
|--------|--------------|
| Click menu bar item | Toggle popover with CPU, Memory, Thermals, AI status |
| Pushpin icon in popover | Pin / unpin AI tool to menu bar |
| ☑️ "What to Show" button | Choose which metrics / sensors / AI tools to display |
| 🎨 palette button | Customize status icon appearance / theme |
| Launch at Login toggle | Auto-start the app on login |

### Choosing what to show

Open the popover → **Settings** → **What to Show** (checklist icon) to toggle:

- **Menu bar**: CPU %, Memory, CPU temp, GPU temp, Fan speed
- **Thermals (popover)**: CPU / GPU / SSD / Memory / Battery / Ambient groups, and fan speeds
- **AI Agents**: which tools to monitor (disabled tools are not scanned at all)

### Menu bar indicators

```
12% · 8.2G · 65°C · GPU 58°C · 2400 RPM Cx:⚡
```

- `⚡` — actively using CPU (Working)
- `●` — process exists but idle (Idle)
- `✓` — task completed (shown for 15s)

### AI agent state machine

```
idle ──(activity detected)──> working
working ──(children gone + activity drops, 3s grace)──> completed
completed ──(5s elapsed, no activity)──> idle
completed ──(activity resumes)──> working
any ──(process exits)──> completed ──(30s)──> notRunning
```

## Architecture

```
Sources/SystemMonitorBar/
  App.swift                NSApplicationDelegate, NSStatusBar, SMAppService
  SystemMonitor.swift      host_statistics (CPU), host_statistics64 (memory)
  TemperatureMonitor.swift IOKit SMC interface for CPU/GPU temperature + fans
  TemperatureLogger.swift  periodic CSV history (~/Library/Application Support)
  AIMonitor.swift          proc_listallpids, proc_pidpath, proc_pidinfo, state machine
  ContentView.swift        SwiftUI popover + settings views
  DisplaySettings.swift    user-configurable monitor/display selection
  StatusTheme.swift        Theme presets and appearance configuration
```

## Releasing

Releases are built by GitHub Actions ([`.github/workflows/release.yml`](.github/workflows/release.yml)):

```bash
git tag v1.1.0
git push origin v1.1.0
```

This builds a **universal** binary on a macOS runner, packages a `.dmg`, and
publishes a GitHub Release. The DMG is ad-hoc signed (see the Gatekeeper note
above). Regenerate the app icon after artwork changes with `scripts/make-icon.sh`.

<!-- ───────────────────────────────────────────────────────────────────── -->
<!-- AI-ASSISTANT QUICK REFERENCE                                            -->
<!-- An AI coding agent can read this block to help the user install,        -->
<!-- build, run, and troubleshoot without further context.                  -->
<!-- ───────────────────────────────────────────────────────────────────── -->

## For AI assistants

If you are an AI agent helping the user with this project, these are the
canonical commands. Run them from the repository root on macOS 14+.

**Build and run from source:**
```bash
./build.sh                 # compile (release) + package SystemMonitorBar.app
open SystemMonitorBar.app  # launch (menu-bar only; no Dock icon / window)
```

**Install into /Applications:**
```bash
./build.sh
cp -R SystemMonitorBar.app /Applications/
open /Applications/SystemMonitorBar.app
```

**Quit / restart the running app** (it is single-instance, so restart to pick up a rebuild):
```bash
pkill -x SystemMonitorBar          # quit
open /Applications/SystemMonitorBar.app   # relaunch
```

**Fix a downloaded copy that won't open** (un-notarized app, one time only):
```bash
xattr -dr com.apple.quarantine /Applications/SystemMonitorBar.app
```

**Build a distributable disk image:**
```bash
./build.sh && ./scripts/make-dmg.sh    # -> SystemMonitorBar.dmg
```

**Cut a release** (CI builds the universal DMG and publishes it):
```bash
git tag vX.Y.Z && git push origin vX.Y.Z
```

**Temperature/fan history CSV** (for before/after thermal comparisons):
```bash
open "$HOME/Library/Application Support/SystemMonitorBar/temp-history.csv"
```

**Notes for agents:**
- Universal (arm64 + x86_64) builds need full Xcode; with Command Line Tools
  only, `./build.sh` produces a native-arch build (CI handles universal).
- The app has no Dock icon or window — verify it's alive with `pgrep -x SystemMonitorBar`.
- User-facing settings live in the popover under **Settings** (no CLI flags).

## License

MIT
