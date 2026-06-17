# Miransas Pulse Healthy-agent 

Miransas Pulse, macOS icin hafif bir sistem ve uygulama sagligi izleme agent'idir. CPU/RAM metriklerini okur, process listesini izler, local SQLite'a yazar ve menubar'da canli health score gosterir. Ayrica local bir HTTP API (`/health`, `/metrics`, `/stream` SSE) sunar.

## Gereksinimler

- macOS
- Xcode Command Line Tools

Command Line Tools yoksa:

```bash
xcode-select --install
```

## Hemen Deneme

```bash
make
./bin/miransas_agent --menubar
```

`--menubar` menubar'da canli health score'u ve top process'leri gosterir.

`--hud` ile birkac saniyelik transparan health paneli acabilirsin:

```bash
./bin/miransas_agent --hud
```

Terminalde yardim:

```bash
./bin/miransas_agent --help
```

## Kurulum

Kullanici hesabina kurmak ve menubar'da arka plan servisini baslatmak icin:

```bash
make install
```

Bu komut:

- binary'yi `~/.local/bin/miransas-pulse` yoluna kopyalar
- `~/Library/LaunchAgents/com.miransas.pulse.plist` dosyasini uretir (`--menubar` modunda)
- LaunchAgent'i `launchctl` ile baslatir
- loglari `~/Library/Logs/miransas-pulse.log` ve `~/Library/Logs/miransas-pulse.err.log` dosyalarina yazar

Servis durumunu gormek icin:

```bash
launchctl list | grep com.miransas.pulse
```

Loglari izlemek icin:

```bash
tail -f ~/Library/Logs/miransas-pulse.log
```

## Kaldirma

```bash
make uninstall
```

## Gelistirme Komutlari

Derleme:

```bash
make
```

Temizleme:

```bash
make clean
```

Tek UDP paket gonderip cikma:

```bash
./bin/miransas_agent --once
```

Terminalde surekli calisma (storage + API server ile):

```bash
./bin/miransas_agent --foreground
```

HUD kisayolu:

```bash
make hud
```

## .app Bundle (opsiyonel)

Menubar uygulamasini standart bir macOS `.app` paketi olarak uretmek icin:

```bash
make bundle
```

Bu komut `bin/Miransas Pulse.app` altinda standart bir `.app` bundle olusturur:

- `Contents/MacOS/miransas_agent` — binary
- `Contents/Info.plist` — `CFBundleIdentifier=com.miransas.pulse`, `LSUIElement=true` (dock'ta gorunmez, sadece menubar)
- `Contents/Resources/AppIcon.icns` — varsa repo'daki `assets/AppIcon.icns` kopyalanir
- ad-hoc `codesign -` ile imzalanir

Bundle'i acmak:

```bash
open "bin/Miransas Pulse.app"
```

### Ozel ikon ekleme

`assets/AppIcon.icns` dosyasini repo koku altinda olusturursan `make bundle` otomatik kopyalar.
PNG'den `.icns` uretmek icin macOS yerlesik araclari:

```bash
mkdir -p AppIcon.iconset
sips -z 16 16     icon.png --out AppIcon.iconset/icon_16x16.png
sips -z 32 32     icon.png --out AppIcon.iconset/icon_16x16@2x.png
sips -z 32 32     icon.png --out AppIcon.iconset/icon_32x32.png
sips -z 64 64     icon.png --out AppIcon.iconset/icon_32x32@2x.png
sips -z 128 128   icon.png --out AppIcon.iconset/icon_128x128.png
sips -z 256 256   icon.png --out AppIcon.iconset/icon_128x128@2x.png
sips -z 256 256   icon.png --out AppIcon.iconset/icon_256x256.png
sips -z 512 512   icon.png --out AppIcon.iconset/icon_256x256@2x.png
sips -z 512 512   icon.png --out AppIcon.iconset/icon_512x512.png
sips -z 1024 1024 icon.png --out AppIcon.iconset/icon_512x512@2x.png
iconutil -c icns AppIcon.iconset -o assets/AppIcon.icns
```

`make bundle`'i tekrar calistir.

## Local API

`--foreground` modunda local HTTP API `127.0.0.1:9876` portunda dinler.

- `GET /health` ve `GET /metrics` — guncel snapshot'i JSON olarak doner
- `GET /stream` — Server-Sent Events (SSE), her `INTERVAL_SEC`'de guncel snapshot

Tarayicidan test:

```javascript
const es = new EventSource('http://127.0.0.1:9876/stream');
es.onmessage = (e) => console.log(JSON.parse(e.data));
```

## UDP Hedefi

Varsayilan hedef `include/agent.h` icinde tanimlidir:

```c
#define TARGET_IP "127.0.0.1"
#define TARGET_PORT 9999
```

Giden paket formati:

```json
{"node":"Miransas-Node-01","cpu_usage_percent":0.00,"total_ram_mb":8192,"free_ram_mb":225}
```
