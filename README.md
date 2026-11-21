# ScriptDeck

**Your scripts. One deck.**

ScriptDeck is a lightweight native macOS (Swift + SwiftUI) dashboard for managing and running local scripts from one deck. It replaces juggling multiple Terminal windows for local background workers with a focused Start / Stop interface—without becoming a terminal emulator, log viewer, or task scheduler.

## Scripts stay on your Mac

Saved scripts are not part of this repository. Each script's name, directory, and command are stored only at:

`~/Library/Application Support/ScriptDeck/scripts.json`

That file lives outside the project folder. Committing or pushing this repo does not upload your script list or the original script files. Those files stay in the directories you chose when you added them.

## Debug and Release

A Release build is not required to put this project on git. Git stores the source.

- **Debug** is the app Xcode runs with `Cmd + R`. Use it while developing.
- **Release** is the optimized app for everyday use outside Xcode, such as a copy in `/Applications`.

Build Release only when you want that standalone app. The command is in [Build & Run](#build--run).

## Architecture & Key Technical Decisions

- **Native macOS UI**: SwiftUI + AppKit (`@Observable`, `@MainActor`), single-window dark dashboard (`#1B1E26` base), system fonts, SF Symbols, and standard macOS window controls. Minimum supported OS: **macOS 14.0 (Sonoma)**.
- **Process Management (`Foundation.Process` + `ScriptDeckLauncher`)**:
  - `Foundation.Process` manages process lifecycle, working directory, merged environment, `/dev/null` `stdin`, PTY `stdout`/`stderr` capture, and `terminationHandler` callbacks (no polling).
  - Because `Foundation.Process` does not expose `POSIX_SPAWN_SETPGROUP` / `setpgid` before `exec`, ScriptDeck bundles a minimal native C helper (`ScriptDeckLauncher`, located at `ScriptDeck.app/Contents/MacOS/ScriptDeckLauncher`). `ScriptDeckLauncher` calls `setpgid(0, 0)` to place each script into its own isolated process group (`pgid == pid`) and immediately replaces itself with the target executable via `execv`.
- **Non-Sandboxed Local Distribution**:
  - App Sandbox is disabled (`com.apple.security.app-sandbox = false`) because ScriptDeck launches arbitrary user-chosen local binaries/interpreters (Python venvs, Node, shell scripts) in arbitrary working directories and signals their process groups.
  - ScriptDeck never requests `sudo` and never stores administrator passwords.
  - Configuration is persisted as atomic JSON at `~/Library/Application Support/ScriptDeck/scripts.json` with user-only POSIX permissions (`0700` directory, `0600` file).
- **Bounded In-Memory Live Output (Latest 50 Lines)**:
  - Each script runs with `stdin` redirected to `/dev/null` (`FileHandle.nullDevice`) and `stdout`/`stderr` attached to a non-blocking PTY drained continuously in memory via `ScriptOutputBuffer(maxLines: 50)`.
  - Clicking any script row (or choosing **View Output…** from its `···` menu) opens a live viewer showing at most the latest 50 lines without writing log files to disk or accumulating unbounded memory.

## Project Structure

```text
script-deck/
├── ScriptDeck.xcodeproj/           # Xcode project & shared ScriptDeck scheme
├── ScriptDeck/
│   ├── App/
│   │   ├── ScriptDeckApp.swift     # Single Window scene
│   │   ├── AppDelegate.swift       # Dock reopen & Quit confirmation lifecycle
│   │   └── StatusBarController.swift # Menu bar icon and script popover
│   ├── Models/
│   │   ├── ScriptConfiguration.swift
│   │   ├── ScriptOutputBuffer.swift
│   │   ├── ScriptRuntimeState.swift
│   │   └── ScriptValidation.swift
│   ├── Services/
│   │   ├── ScriptStore.swift       # Atomic user-only JSON persistence
│   │   ├── ProcessManager.swift    # Process group launch/stop/termination & PTY capture
│   │   └── DashboardViewModel.swift
│   ├── Views/
│   │   ├── Theme.swift
│   │   ├── DashboardView.swift
│   │   ├── ScriptRowView.swift
│   │   ├── ScriptEditorView.swift
│   │   ├── ScriptOutputSheetView.swift
│   │   ├── MenuBarPanelView.swift  # Menu bar script summary panel
│   │   └── Previews/PreviewFixtures.swift
│   ├── Resources/Info.plist
│   └── ScriptDeck.entitlements
├── ScriptDeckLauncher/
│   └── main.c                      # Minimal setpgid(0,0) + execv helper
├── ScriptDeckTests/                # Unit & process-management XCTest suite
└── test-scripts/                   # Manual acceptance test scripts
```

## Build & Run

### Using Xcode

1. Open `ScriptDeck.xcodeproj` in Xcode.
2. Select the `ScriptDeck` scheme and `My Mac` destination.
3. Press `Cmd + R` to build and run, or `Cmd + U` to run the `ScriptDeckTests` suite.

### Using Command Line (`xcodebuild`)

```bash
# Build Release app
xcodebuild -project ScriptDeck.xcodeproj -scheme ScriptDeck -configuration Release -derivedDataPath build build

# Launch the built app
open build/Build/Products/Release/ScriptDeck.app

# Run all unit tests
xcodebuild -project ScriptDeck.xcodeproj -scheme ScriptDeck -configuration Debug -derivedDataPath build test
```

## Adding Scripts (Examples)

Add / Edit script requires only 3 fields: **Name**, **Directory**, and **Command**. Commands execute inside `Directory` via `/bin/zsh -lc` inside an isolated `ScriptDeckLauncher` process group (`stdin` → `/dev/null`, `stdout`/`stderr` → latest 50-line in-memory PTY buffer).

### 1. Node.js / `npm run dev`

- **Name**: `Web Frontend`
- **Directory**: `/Users/me/web-app`
- **Command**: `npm run dev`

### 2. Python Script (with Virtual Environment)

- **Name**: `Data sync`
- **Directory**: `/Users/me/project`
- **Command**: `.venv/bin/python3 sync.py --interval 60`

### 3. Shell Script (`.sh`)

- **Name**: `Model pipeline`
- **Directory**: `/Users/me/project`
- **Command**: `./run-model.sh`

## `PATH` & Shell Environment

- ScriptDeck runs commands via `/bin/zsh -lc` and ensures standard developer directories (`/opt/homebrew/bin`, `/opt/homebrew/sbin`, `/usr/local/bin`, `/usr/bin`, `/bin`, `/usr/sbin`, `/sbin`) are present in `PATH` so tools like `npm`, `node`, and `python3` work when launched from Finder or Dock.
- When `BROWSER` is unset, ScriptDeck resolves the current macOS default `https://` browser (`NSWorkspace.shared.urlForApplication(toOpen:)`) and sets `BROWSER` to that app path so dev servers (such as Vite and Create React App) open the system default browser instead of preferring Google Chrome when Chrome is running. Explicit overrides like `BROWSER=none npm run dev` are preserved.
- Interactive shell config (`~/.zshrc`) is not loaded automatically; `~/.zprofile` (login shell) is loaded by `zsh -l`.

## Stop & Quit Behavior

- **Stop**:
  1. Sends `SIGTERM` to the script's isolated process group (`-pgid`), stopping the script and foreground child processes it spawned without affecting other Terminal processes of the same name.
  2. Waits up to **5 seconds** for the entire process group to exit.
  3. If any process in that group is still alive after 5 seconds, escalates to `SIGKILL` for the process group.
  4. User-initiated stops transition the row to `Stopped` (not `Failed`).
- **Closing the Window vs. Quitting**:
  - Closing the main window (`Cmd+W` or the red close button) hides ScriptDeck from the Dock and leaves it running in the background. The menu bar icon and any running scripts stay active. Choose **Open** in the menu bar panel to bring the window and Dock icon back.
  - Quitting ScriptDeck (**Quit** in the menu bar panel, `Cmd+Q`, or Dock Quit while the window is open) when scripts are active displays a confirmation prompt (**Stop scripts and quit?**). Choosing **Stop & Quit** blocks new starts, stops all active script process groups, and exits once they have terminated.
  - On relaunch, saved configurations are loaded, and scripts are **never** auto-started.

## Menu Bar

While ScriptDeck is running, a terminal icon stays in the macOS menu bar.

- The icon shows a count while any script is starting, running, or stopping.
- Click the icon to open a panel listing each script's name, status, elapsed time, and command. **Start** and **Stop** work from the panel.
- **Open** brings the main window and Dock icon back.
- **Quit** quits the app. If scripts are running, ScriptDeck asks before stopping them.
- Closing the main window leaves ScriptDeck running in the background: no Dock icon, menu bar icon still visible, scripts still running.

## Supported Scope & Limitations

- Supports non-interactive, foreground local scripts (`stdin` is attached to `/dev/null`).
- Does **not** support scripts requiring interactive prompts or `sudo` passwords.
- Does **not** guarantee reliable termination of processes that explicitly daemonize (`setsid`), double-fork out of their process group, or delegate work to external background services (`launchd`, Docker, etc.).
- Does **not** recover or manage child processes if ScriptDeck itself is force-killed (`kill -9`) or crashes.
- Does **not** import or adopt processes already running in Terminal.app or iTerm2.

## Resource Usage & Measurement

ScriptDeck avoids WebViews, system-wide `ps` polling, log buffers, and continuous idle animations. A single 1-second timer runs only while at least one script is active.

### How to Measure

Compare `ScriptDeck.app` idle vs. active with test scripts using `ps` (separating GUI app and script child processes):

```bash
# GUI app process
ps -p <SCRIPTDECK_PID> -o pid,rss,%cpu,comm

# Child script process group
ps -g <SCRIPT_PGID> -o pid,pgid,rss,%cpu,command
```

### Observed Measurements (Release Build on macOS 27.2.1, arm64)

- **GUI App (`ScriptDeck`, idle)**: `74,912 KB` RSS, `0.0%` CPU
- **GUI App (`ScriptDeck`, sampled while 3 `ScriptDeckLauncher` child script groups ran concurrently)**: `74,848 KB` RSS, `0.0%` CPU
- **Child Script Groups (separate processes via `ScriptDeckLauncher`, `stdin`/`stdout`/`stderr` → `/dev/null`)**:
  - `continuous_worker.sh` (`zsh` + `sleep 1`): `2,720 KB` + `912 KB` RSS, `0.0%` CPU
  - `parent_with_child.sh` (`zsh` + `sleep 300`): `2,704 KB` + `912 KB` RSS, `0.0%` CPU
  - `noisy_output.sh` (`zsh` tight loop writing to `/dev/null`): `2,752 KB` RSS, `100.0%` CPU (GUI app memory remained flat with zero pipe buffering)
