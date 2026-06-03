# Miransas Pulse

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
