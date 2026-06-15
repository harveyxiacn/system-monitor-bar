# System Monitor Bar

A lightweight macOS menu bar app that displays real-time system metrics and tracks AI agent activity — CPU usage, memory, and process-level status for Codex, Claude Code, GPT CLI, Aider, Windsurf, and OpenCode.

![Screenshot](.github/screenshot.png)

## Features

- **Real-time CPU & memory** — uses `host_statistics` Mach API for sub-second CPU sampling and accurate memory (active + wired pages).
- **AI agent monitoring** — detects whether AI tools are running, actively working (per-process CPU tracking), idle, or recently completed.
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
12% · 8.2G Cod:⚡
```

- `⚡` — actively using CPU (Working)
- `●` — process exists but idle (Idle)
- `✓` — recently exited (Done, shown for 15s)

### AI status dots in popover

- Orange — Working
- Green — Idle
- Blue — Done
- Gray — Off

## Architecture

```
Sources/SystemMonitorBar/
  App.swift           NSApplicationDelegate, NSStatusBar, SMAppService
  SystemMonitor.swift  host_statistics (CPU), host_statistics64 (memory)
  AIMonitor.swift      proc_listallpids, proc_pidpath, proc_pidinfo
  ContentView.swift    SwiftUI popover views
```

## License

MIT
