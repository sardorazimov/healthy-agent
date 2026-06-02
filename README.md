# Miransas Pulse

Miransas Pulse, macOS icin hafif bir sistem ve uygulama sagligi izleme agent'i olarak tasarlaniyor. Su an CPU/RAM metriklerini okuyabilir, UDP ile JSON gonderebilir ve ekranda kucuk transparan bir health paneli gosterebilir.

Hedef urun fikri: Windows'taki uygulama/gecmis kullanim hissine yakin, ama daha sade bir macOS health overlay'i. Hangi uygulama calisiyor, ne kadar sure acik kaldi, ne kadar CPU/RAM kullaniyor ve sistemi ne yoruyor sorularina cevap verecek.

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
./bin/miransas_agent --hud
```

`--hud` ekranda kucuk transparan health panelini acar ve birkac saniye sonra kapatir.

Terminalde yardim:

```bash
./bin/miransas_agent --help
```

## Kurulum

Kullanici hesabina kurmak ve arka plan servisini baslatmak icin:

```bash
make install
```

Bu komut:

- binary'yi `~/.local/bin/miransas-pulse` yoluna kopyalar
- `~/Library/LaunchAgents/com.miransas.pulse.plist` dosyasini uretir
- LaunchAgent'i `launchctl` ile baslatir
- loglari `~/Library/Logs/miransas-pulse.log` ve `~/Library/Logs/miransas-pulse.err.log` dosyalarina yazar

Kurulumdan sonra HUD test etmek icin:

```bash
~/.local/bin/miransas-pulse --hud
```

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

Bu komut LaunchAgent'i durdurur, plist dosyasini ve kurulu binary'yi siler.

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

Terminalde surekli calisma:

```bash
./bin/miransas_agent --foreground
```

HUD kisayolu:

```bash
make hud
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

## Durum

Calisan prototip:

- CPU/RAM okuma
- UDP JSON gonderimi
- transparan macOS HUD
- kullanici LaunchAgent kurulumu

Siradaki urunlesme adimlari:

- process/app listesi okuma
- app bazinda CPU/RAM ve calisma suresi
- HUD icinde en cok kaynak kullanan uygulamalar
- local gunluk kullanim kaydi
- menubar uygulamasi veya ayarlar paneli

## Isim

Bu projenin son adi icin onerim: **Miransas Pulse**.

Sebep: "Pulse" sistemin nabzini, uygulama sagligini ve canli kaynak kullanimini iyi anlatiyor. Teknik binary adi simdilik `miransas_agent`, kurulu komut adi ise `miransas-pulse`.
