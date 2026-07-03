<p align="center">
  <img src="https://img.shields.io/badge/macOS-12%2B-brightgreen" alt="macOS 12+">
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT">
  <img src="https://img.shields.io/badge/version-1.1.4-orange" alt="Version 1.1.4">
  <img src="https://img.shields.io/badge/arch-arm64%20%7C%20x86__64-lightgrey" alt="Universal Binary">
  <img src="https://img.shields.io/badge/Swift-5-orange" alt="Swift 5">
  <img src="https://img.shields.io/badge/Bun-Typescript-14151a" alt="Bun">
</p>

<h1 align="center">
  ⌘ OpenCode Status Bar
</h1>

<p align="center">
  <strong>Tiny macOS menu bar app that puts OpenCode's live status — always one glance away.</strong><br>
  No windows. No dock icon. No analytics. Just a pixel in your menu bar.
</p>

> Built so you can tab away during a long thinking stretch and see, at a glance, whether OpenCode is working, waiting on you, or done.

<p align="center">
  <img width="600" alt="OpenCode Status Bar" src="https://raw.githubusercontent.com/aacassandra/opencode-status-bar/main/assets/preview-img.png" />
  <br>
  <em>↑ System widget, NVMe detection, timer continuity</em>
</p>

<p align="center">
  <img width="600" alt="OpenCode Status Bar demo" src="https://raw.githubusercontent.com/aacassandra/opencode-status-bar/main/assets/capture.gif" />
  <br>
  <em>↑ Live status, animasi, dan break time overlay</em>
</p>

---

## ✨ What it shows

| State | What you see |
|-------|-------------|
| **Thinking** | Animated icon + live timer (`1m 1s`) |
| **Running a tool** | Short label: `Editing`, `Reading`, `Running command`, `Searching` |
| **Awaiting permission** | Paused yellow dot |
| **Idle / done** | Rests on terminal icon |

### ⚙️ Options

| Feature | Description |
|---------|-------------|
| **Show timer** | Toggle the elapsed clock on/off |
| **Completion sound** | Soft chime when a turn >1 min finishes (user-selectable) |
| **Notification sound** | Always plays when OpenCode asks for permission (user-selectable, defaults to Tink) |
| **Animation style** | OpenCode Spark · Block Build · Terminal Pulse · Bounce · Pulse · Dots |
| **Hide idle sessions** | Auto-hide after 5m / 15m / 30m / 1h / never |
| **Break Time** | Break reminder with two modes: fullscreen overlay or Sound Only |
| **Sound Only** | Plays sound on interval, no fullscreen overlay |
| **System info** | Graphical bar charts for CPU (per-core tooltip), RAM, Disk (internal & external), and temperature (°C) — click any row to open Activity Monitor |
| **Customize** | Submenu with Change Icon, Change Sound, Colors, Labels, Reset All |
| **Change Sound** | Completion, Permission, plus Break Time sounds: Sound Only, Starting, Completion |
| **Colors** | Per-state color picker for Thinking, Idle, Permission, Tool — applies to status text & icon |
| **Auto-update** | One-click "Update available" in menu |

---

## 🔥 Multi-session

Run multiple OpenCode sessions side-by-side. The menu bar surfaces the **highest-priority** session:

> A session awaiting permission **always** jumps above one that's thinking.

The dropdown lists **every live session** — project name, status, timer, and CLI/APP badge. Click any session to focus its terminal or the OpenCode Desktop app.

---

## 🖥️ Where it works

| Surface | Tracked? |
|---------|:--------:|
| OpenCode CLI (terminal) | ✅ |
| OpenCode Desktop | ✅ |
| Terminal, iTerm, VS Code, Warp | ✅ |

---

## 📦 Install

### Download DMG

Grab the latest DMG from the [releases page](https://github.com/aacassandra/opencode-status-bar/releases/latest), mount it, and drag to Applications.

### Homebrew

```bash
brew tap ardith666/tap
brew trust ardith666/tap
brew install --cask opencode-status-bar
```

### From source

```bash
# 1. Build
./build.sh

# 2. Launch once (wires up the plugin automatically)
open build/OpenCodeStatusBar.app

# 3. Start an OpenCode session — the icon appears in your menu bar
```

The app copies its plugin to `~/.config/opencode/plugins/statusbar.ts` and the plugin writes state to `~/.config/opencode/statusbar/state.d/`. Everything is automatic.

### Updating

Rebuild and re-launch. The plugin is overwritten on each launch if the content differs.

---

## ⚡ How it works

```
OpenCode (Bun)  ──►  plugin/statusbar.ts  ──►  ~/.config/opencode/statusbar/state.d/*.json
                                                      │
                                                      ▼
                                              Swift app polls every 0.4s
                                                      │
                                                      ▼
                                              Menu bar icon + dropdown
```

- **Stateless.** OpenCode fires lifecycle events → plugin writes JSON → app reads JSON → renders icon.
- **Self-managing.** Plugin auto-launches the app when a session starts.
- **Private.** Zero data collection. One daily GitHub API call for update checks.

---

## 🛠️ Build from source

```bash
# Prerequisites: macOS 12+, Xcode Command Line Tools, Bun
./build.sh
```

The script:
1. Compiles all Swift sources with `swiftc -O` for arm64 + x86_64
2. Merges into a **universal binary** via `lipo`
3. Creates `.app` bundle with embedded `Info.plist`
4. Bundles plugin, icon, and assets into `Resources/`

Output: `build/OpenCodeStatusBar.app`

---

## ❓ Troubleshooting

App not showing? Plugin not installed?

- Check the plugin file exists: `~/.config/opencode/plugins/statusbar.ts`
- Check state directory: `~/.config/opencode/statusbar/state.d/`
- Launch the app manually: `open build/OpenCodeStatusBar.app`

---

## 📋 Changelog

### v1.1.4
- **Permission pulse**: slow breathing animation with permission color, isolated frame counter
- **Update check cooldown**: reduced from 24h to 1h for faster update detection

### v1.1.3
- **Permission pulse**: waiting permission state animates with pulse icon, honoring permission color
- **Basic spacing**: compact RAM detail (`10/16GB`) and disk detail (`NVME: 238GB/75%`)

### v1.1.2
- **NVMe detection**: accurate disk type via IORegistry parent chain (IONVMeController)
- **System Style**: switchable Basic (text) / ProgressBar (graphical) layout under Customize menu
- **Basic layout**: compact 2-column text format with disk type prefix (NVMe/SSD/HDD)
- **Disk filter**: exclude system volumes, <1 GB, timemachine snapshots
- **Timer continuity**: tracks from first active state across thinking→tool→permission transitions
- **Temperature**: auto-hides row when SMC unavailable (Hackintosh)

### v1.1.0
- **Graphical system widget**: bar charts with color thresholds for CPU, RAM, Disk, temperature
- **Per-core CPU**: shows core count, tooltip with per-core usage on hover
- **Multiple disks**: internal & external volumes (filters APFS system volumes & Time Machine snapshots)
- **Temperature**: now displayed when valid (>5°C), expanded SMC key support
- **Click to Activity Monitor**: click any system stat row to open Activity Monitor

### v1.0.6
- **Fix**: completion sound min-duration measured from first busy state, not last transition

### v1.0.5
- **Fix**: reset break interval default to 30m (remove stale UserDefaults 60s from testing)

### v1.0.4
- Permission notification fix, count/completion sound for break, emoji carousel, custom interval, crash fixes

---

## 🗑️ Uninstall

```bash
bun run plugin/uninstall.ts
# Then delete the app
```

Removes the plugin and state directory from `~/.config/opencode/`.

---

## 📄 License

MIT
