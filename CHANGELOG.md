# Changelog

All notable changes to System Monitor Bar.

## [Unreleased]

### Added
- README and CHANGELOG

## [1.0.0] — 2026-06-15

### Added
- Real-time CPU monitoring via `host_statistics` (user + system + nice tick deltas)
- Real-time memory monitoring via `host_statistics64` (active + wired pages)
- AI agent process detection for Codex, Claude Code, GPT CLI, Aider, Windsurf, OpenCode
- Per-process CPU tracking via `proc_pidinfo(PROC_PIDTASKINFO)` to distinguish Working vs Idle
- Process completion detection when monitored tools exit
- Menu bar pinning system with pushpin toggles in popover
- Pinned tool status indicators in menu bar (`⚡` working, `●` idle, `✓` done)
- Launch at Login toggle using `SMAppService`
- UserDefaults persistence for pinned tools
- `NSStatusBar` + `NSPopover` + SwiftUI architecture
- `.app` bundle packaging with `LSUIElement` (hidden from Dock)
- `build.sh` release build script

### Fixed
- Process name matching on macOS 15: `proc_name` returns empty strings for Electron-based apps; added `proc_pidpath` fallback for full executable path matching
- PID selection: when multiple processes match the same tool (main app + CLI + helpers), prefer the PID with highest cumulative CPU ticks instead of last-match
- Pin state lost on app restart: now persisted in UserDefaults

### Known issues
- Unsigned `.app` bundle may be blocked by Gatekeeper on macOS 15 when double-clicked in Finder; use `open` from Terminal or `codesign -s - SystemMonitorBar.app` for ad-hoc signing
