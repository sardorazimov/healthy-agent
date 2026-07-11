# Miransas Pulse (miransas_agent)

A lightweight system performance monitoring utility and daemon for macOS, powered primarily by Objective-C (Cocoa/AppKit) for native UI integration and C for low-level POSIX metric collection. Miransas Pulse tracks system health, metrics, and process snapshots in real-time, delivering them via a local REST/SSE API, a transparent HUD, and a native macOS Menubar integration.

## Features

* **Native Menubar App:** Runs silently in the background with a live health score indicator utilizing AppKit / `NSStatusBar`.
* **Transparent HUD:** An on-demand, non-intrusive health panel for quick system snapshots.
* **Daemonized Operation:** Managed robustly via macOS `launchd` for automatic startup and crash recovery (KeepAlive).
* **Objective-C & C Hybrid Architecture:** Native Cocoa runtime performance combined with a minimal footprint for continuous background execution.
* **Network Broadcasting:** Broadcasts system metrics via API for external aggregation.

## Installation

Miransas Pulse includes automated shell scripts to build the binary and register it as a macOS `LaunchAgent`.

```bash
# Clone the repository
git clone [https://github.com/Miransas/healthy-agent.git](https://github.com/Miransas/healthy-agent.git)
cd healthy-agent

# Build and install the daemon
chmod +x scripts/install.sh
./scripts/install.sh
Upon installation, the agent is moved to ~/.local/bin/miransas-pulse, and a .plist file is loaded into ~/Library/LaunchAgents/com.miransas.pulse.plist. The Menubar app will start automatically.

Usage
If you prefer to run the agent manually or test specific features, you can use the following flags:

Bash
miransas-pulse [OPTIONS]

Options:
  --foreground    Run in the terminal, outputting logs to stdout/stderr.
  --once          Send a single metric packet and exit.
  --hud           Show the transparent health panel (HUD).
  --menubar       Start the macOS menubar application (live health score).
  --api-port      Local REST/SSE API port (Default: 9876).
  --help          Show help message.
Uninstallation
To completely remove the background service and binaries from your system:

Bash
chmod +x scripts/uninstall.sh
./scripts/uninstall.sh
Architecture
Core & UI: Objective-C utilizing Cocoa frameworks (AppKit, CoreFoundation).

Metrics: C-based low-level POSIX system calls.

Persistence: Uses file-locking (/tmp/miransas-pulse.lock) to prevent multiple background instances.