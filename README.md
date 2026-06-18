# System Monitor Bar

A lightweight macOS menu bar app that displays real-time system metrics and tracks AI agent activity — CPU usage, memory, temperatures, and process-level status for Codex, Claude Code, Aider, Windsurf, OpenCode, and Antigravity.

![Screenshot](.github/screenshot.png)

## Features

- **Real-time CPU & memory** — uses `host_statistics` Mach API for sub-second CPU sampling and accurate memory (active + wired pages).
- **Temperature monitoring** — reads CPU and GPU temperatures via SMC (IOKit `AppleSMC` interface) with `sp78`/`fpe2` data type support.
- **AI agent monitoring** — detects whether AI tools are running, actively working (child process + CPU + context-switch analysis), completed (task finished), or idle.
- **Menu bar pinning** — pin any AI tool to the menu bar for at-a-glance status: `Cod:⚡` (working), `Cc:●` (idle), `Aid:✓` (completed).
- **Launch at login** — built-in toggle using `SMAppService` (macOS 13+).
- **Zero Dock footprint** — `LSUIElement=true`, exists only in the menu bar.
- **Persistent settings** — pinned tools survive app restarts via UserDefaults.

## Requirements

- macOS 10.13 or later
- Swift 5.9+ (Command Line Tools or Xcode)

## Install

```bash
git clone https://github.com/harveyxiacn/system-monitor-bar.git
cd system-monitor-bar
./build.sh
open SystemMonitorBar.app
```

Enable "Launch at Login" from the popover's Settings section.

## Usage

| Action | What it does |
|--------|--------------|
| Click menu bar item | Toggle popover with CPU, Memory, AI status |
| Pushpin icon in popover | Pin / unpin AI tool to menu bar |
| Launch at Login toggle | Auto-start the app on login |

### Menu bar indicators

```
12% · 8.2G · 65°C · GPU 58°C Cod:⚡
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

### AI status dots in popover

- Orange — Working
- Green — Idle
- Blue — Done
- Gray — Off

## Architecture

```
Sources/SystemMonitorBar/
  App.swift               NSApplicationDelegate, NSStatusBar, SMAppService
  SystemMonitor.swift      host_statistics (CPU), host_statistics64 (memory)
  TemperatureMonitor.swift IOKit SMC interface for CPU/GPU temperature
  AIMonitor.swift          proc_listallpids, proc_pidpath, proc_pidinfo, state machine
  ContentView.swift        SwiftUI popover views
  StatusTheme.swift        Theme presets and appearance configuration
```

## License

MIT
