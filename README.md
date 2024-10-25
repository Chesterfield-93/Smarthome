# Smarthome

## Proxmox Monitoring Script

Ein Bash-Script zum Monitoring von Proxmox-Hosts mit Telegram-Benachrichtigungen. Das Script überwacht CPU-, RAM- und Speicherauslastung und sendet Benachrichtigungen über einen Telegram-Bot, wenn definierte Schwellwerte überschritten werden.

### Features

- Überwachung mehrerer Proxmox-Nodes
- Monitoring von CPU-, RAM- und Speicherauslastung
- Konfigurierbare Schwellwerte
- Telegram-Benachrichtigungen bei Überschreitung der Schwellwerte
- Detailliertes Logging
- Automatische Wiederverbindung bei Verbindungsabbrüchen

### Voraussetzungen

- Bash
- curl
- jq (JSON processor)
- bc (Basic Calculator)
- Zugang zu einem Proxmox-Host
- Telegram-Bot-Token und Chat-ID

### Installation

1. Klonen Sie das Repository:
```bash
git clone https://github.com/yourusername/proxmox-monitoring.git
cd proxmox-monitoring
```

2. Machen Sie das Script ausführbar:
```bash
chmod +x proxmox_monitor.sh
```

3. Installieren Sie die benötigten Abhängigkeiten:
```bash
## Für Debian/Ubuntu
sudo apt-get update
sudo apt-get install curl jq bc

## Für CentOS/RHEL
sudo yum install curl jq bc
```

### Konfiguration

1. Öffnen Sie das Script in einem Texteditor und passen Sie die Konfigurationsvariablen an:
```bash
PROXMOX_HOST="your-proxmox-host"
PROXMOX_USER="root@pam"
PROXMOX_PASSWORD="your-password"
TELEGRAM_BOT_TOKEN="your-bot-token"
TELEGRAM_CHAT_ID="your-chat-id"

## Schwellwerte
CPU_THRESHOLD=80    # in Prozent
RAM_THRESHOLD=80    # in Prozent
STORAGE_THRESHOLD=80 # in Prozent
CHECK_INTERVAL=300  # in Sekunden
```

2. Einrichtung des Telegram-Bots:
   - Erstellen Sie einen neuen Bot über den [@BotFather](https://t.me/botfather)
   - Kopieren Sie den Bot-Token
   - Starten Sie eine Konversation mit Ihrem Bot
   - Rufen Sie https://api.telegram.org/bot<IHR_BOT_TOKEN>/getUpdates auf
   - Kopieren Sie die Chat-ID aus der Antwort

### Verwendung

Starten Sie das Script:
```bash
./proxmox_monitor.sh
```

Für den Produktiveinsatz empfiehlt sich das Ausführen als Systemd-Service:

1. Erstellen Sie eine Service-Datei:
```bash
sudo nano /etc/systemd/system/proxmox-monitor.service
```

2. Fügen Sie folgenden Inhalt ein:
```ini
[Unit]
Description=Proxmox Monitoring Service
After=network.target

[Service]
Type=simple
ExecStart=/pfad/zu/proxmox_monitor.sh
Restart=always
User=root

[Install]
WantedBy=multi-user.target
```

3. Aktivieren und starten Sie den Service:
```bash
sudo systemctl enable proxmox-monitor
sudo systemctl start proxmox-monitor
```

### Logging

Das Script protokolliert alle Aktivitäten mit Zeitstempel. Die Logs werden standardmäßig in der Konsole ausgegeben und können bei Bedarf in eine Datei umgeleitet werden:

```bash
./proxmox_monitor.sh > /var/log/proxmox-monitor.log 2>&1
```

### Alarme

Das Script sendet Benachrichtigungen über Telegram in folgenden Fällen:
- CPU-Auslastung über dem definierten Schwellwert
- RAM-Auslastung über dem definierten Schwellwert
- Speicherplatz-Auslastung über dem definierten Schwellwert
- Start des Monitoring-Services
- Verbindungsprobleme zum Proxmox-Host

### Lizenz

Dieses Projekt ist unter der MIT-Lizenz lizenziert - siehe die [LICENSE](LICENSE) Datei für Details.

### Beitragen

1. Fork das Projekt
2. Erstelle einen Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit deine Änderungen (`git commit -m 'Add some AmazingFeature'`)
4. Push zu dem Branch (`git push origin feature/AmazingFeature`)
5. Öffne einen Pull Request