CC = gcc
CFLAGS = -Wall -Wextra -O3 -Iinclude
LDFLAGS = -framework Cocoa -lpthread
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

bundle: all
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

.PHONY: all clean install uninstall hud bundle dmg
