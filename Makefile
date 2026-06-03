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

.PHONY: all clean install uninstall hud
