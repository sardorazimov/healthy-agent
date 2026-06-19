CC = gcc
CFLAGS = -Wall -Wextra -O3 -Iinclude
LDFLAGS = -framework Cocoa -framework QuartzCore -framework IOKit -framework CoreWLAN -framework SystemConfiguration -lpthread
SRC_DIR = src
BUILD_DIR = build
BIN_DIR = bin

C_SRC = $(wildcard $(SRC_DIR)/*.c)
M_SRC = $(wildcard $(SRC_DIR)/*.m)
OBJ = $(C_SRC:$(SRC_DIR)/%.c=$(BUILD_DIR)/%.o) $(M_SRC:$(SRC_DIR)/%.m=$(BUILD_DIR)/%.o)
TARGET = $(BIN_DIR)/miransas_agent
APP_BUNDLE = $(BIN_DIR)/Miransas Pulse.app
DMG_STAGING = $(BUILD_DIR)/dmg
DMG_PATH = $(BIN_DIR)/MiransasPulse.dmg

define INFO_PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Miransas Pulse</string>
    <key>CFBundleDisplayName</key>
    <string>Miransas Pulse</string>
    <key>CFBundleIdentifier</key>
    <string>com.miransas.pulse</string>
    <key>CFBundleExecutable</key>
    <string>miransas_agent</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>0.1.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>11.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
</dict>
</plist>
endef
export INFO_PLIST

all: $(TARGET)

$(TARGET): $(OBJ)
	@mkdir -p $(BIN_DIR)
	$(CC) $(OBJ) $(LDFLAGS) -o $(TARGET)
	@echo "[Miransas-Build] Binary başarıyla üretildi: $(TARGET)"

$(BUILD_DIR)/%.o: $(SRC_DIR)/%.c
	@mkdir -p $(BUILD_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/%.o: $(SRC_DIR)/%.m
	@mkdir -p $(BUILD_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -rf $(BUILD_DIR) $(BIN_DIR)
	@echo "[Miransas-Build] Temizlik tamamlandı."

install: all
	./scripts/install.sh

uninstall:
	./scripts/uninstall.sh

hud: all
	$(TARGET) --hud

icon:
	@if [ ! -f assets/icon.svg ]; then \
		echo "[Miransas-Icon] assets/icon.svg yok, atlandi."; \
	else \
		set -e; \
		if command -v rsvg-convert >/dev/null 2>&1; then \
			rsvg-convert -w 1024 -h 1024 assets/icon.svg -o /tmp/miransas_icon_1024.png; \
		elif command -v qlmanage >/dev/null 2>&1; then \
			rm -f /tmp/icon.svg.png; \
			qlmanage -t -s 1024 -o /tmp assets/icon.svg >/dev/null 2>&1; \
			mv /tmp/icon.svg.png /tmp/miransas_icon_1024.png; \
		else \
			echo "[Miransas-Icon] HATA: rsvg-convert gerekli. brew install librsvg" >&2; \
			exit 1; \
		fi; \
		rm -rf assets/AppIcon.iconset; \
		mkdir -p assets/AppIcon.iconset; \
		for spec in "16 icon_16x16" "32 icon_16x16@2x" "32 icon_32x32" "64 icon_32x32@2x" "128 icon_128x128" "256 icon_128x128@2x" "256 icon_256x256" "512 icon_256x256@2x" "512 icon_512x512" "1024 icon_512x512@2x"; do \
			set -- $$spec; \
			sips -z $$1 $$1 /tmp/miransas_icon_1024.png --out "assets/AppIcon.iconset/$$2.png" >/dev/null; \
		done; \
		iconutil -c icns assets/AppIcon.iconset -o assets/AppIcon.icns; \
		rm -rf assets/AppIcon.iconset; \
		rm -f /tmp/miransas_icon_1024.png; \
		echo "[Miransas-Icon] assets/AppIcon.icns uretildi"; \
	fi

bundle: all icon
	rm -rf "$(APP_BUNDLE)"
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	cp $(TARGET) "$(APP_BUNDLE)/Contents/MacOS/miransas_agent"
	printf '%s\n' "$$INFO_PLIST" > "$(APP_BUNDLE)/Contents/Info.plist"
	@if [ -f assets/AppIcon.icns ]; then \
		cp assets/AppIcon.icns "$(APP_BUNDLE)/Contents/Resources/AppIcon.icns"; \
		echo "[Miransas-Bundle] Icon kopyalandi."; \
	else \
		echo "[Miransas-Bundle] assets/AppIcon.icns bulunamadi, ikon olmadan paketleniyor."; \
	fi
	codesign --force --deep --sign - "$(APP_BUNDLE)"
	@echo "[Miransas-Bundle] App bundle hazir: $(APP_BUNDLE)"

dmg: bundle
	rm -rf "$(DMG_STAGING)"
	rm -f "$(DMG_PATH)"
	mkdir -p "$(DMG_STAGING)"
	cp -R "$(APP_BUNDLE)" "$(DMG_STAGING)/"
	ln -s /Applications "$(DMG_STAGING)/Applications"
	hdiutil create -volname "Miransas Pulse" -srcfolder "$(DMG_STAGING)" -ov -format UDZO "$(DMG_PATH)"
	@echo "[Miransas-DMG] Hazir: $(DMG_PATH)"

.PHONY: all clean install uninstall hud icon bundle dmg
