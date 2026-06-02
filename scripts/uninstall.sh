#!/bin/sh
set -eu

LABEL="com.miransas.pulse"
INSTALL_BIN="$HOME/.local/bin/miransas-pulse"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"

launchctl unload "$PLIST_PATH" >/dev/null 2>&1 || true
rm -f "$PLIST_PATH"
rm -f "$INSTALL_BIN"

echo "[uninstall] Miransas Pulse kaldirildi."
