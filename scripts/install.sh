#!/bin/sh
set -eu

APP_NAME="Miransas Pulse"
LABEL="com.miransas.pulse"
PROJECT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BIN_SOURCE="$PROJECT_DIR/bin/miransas_agent"
INSTALL_DIR="$HOME/.local/bin"
INSTALL_BIN="$INSTALL_DIR/miransas-pulse"
LAUNCH_DIR="$HOME/Library/LaunchAgents"
PLIST_PATH="$LAUNCH_DIR/$LABEL.plist"

if [ ! -x "$BIN_SOURCE" ]; then
    echo "[install] Binary bulunamadi, once derleniyor..."
    make -C "$PROJECT_DIR" clean all
fi

mkdir -p "$INSTALL_DIR" "$LAUNCH_DIR"
cp "$BIN_SOURCE" "$INSTALL_BIN"
chmod 755 "$INSTALL_BIN"

cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$INSTALL_BIN</string>
        <string>--menubar</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$HOME/Library/Logs/miransas-pulse.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/miransas-pulse.err.log</string>
</dict>
</plist>
PLIST

launchctl unload "$PLIST_PATH" >/dev/null 2>&1 || true
launchctl load "$PLIST_PATH"

echo "[install] $APP_NAME kuruldu."
echo "[install] Binary: $INSTALL_BIN"
echo "[install] LaunchAgent: $PLIST_PATH"
echo "[install] HUD test: $INSTALL_BIN --hud"
