# Erweitertes Proxmox Local Monitoring Script

Ein umfassendes Bash-Script zur lokalen Überwachung eines Proxmox-Hosts mit Telegram-Benachrichtigungen. Das Script überwacht verschiedene System- und Hardwaremetriken und sendet Benachrichtigungen bei Überschreitung definierter Schwellwerte.

## Features

- Überwachung von System-Ressourcen (CPU, RAM, Speicherplatz)
- SMART-Status-Überwachung der Festplatten
- CPU-Temperatur-Monitoring
- ZFS-Pool-Status und Scrub-Alter-Überprüfung
- Backup-Status-Überwachung
- Inode-Nutzung-Überwachung
- Proxmox-Service-Status-Überwachung
- Telegram-Benachrichtigungen bei Problemen
- Vermeidung von Benachrichtigungs-Spam durch Status-Tracking
- Automatische Log-Rotation

## Voraussetzungen

- Proxmox VE Host
- smartmontools
- curl
- Telegram-Bot-Token und Chat-ID

## Installation

1. Installieren Sie die benötigten Abhängigkeiten:
```bash
apt-get update
apt-get install smartmontools curl
```

2. Kopieren Sie das Script auf Ihren Proxmox-Host:
```bash
cp proxmox_local_monitor.sh /usr/local/bin/
chmod +x /usr/local/bin/proxmox_local_monitor.sh
```

3. Passen Sie die Konfigurationsvariablen am Anfang des Scripts an:
```bash
nano /usr/local/bin/proxmox_local_monitor.sh
```

4. Richten Sie einen Cron-Job ein:
```bash
crontab -e
```
Fügen Sie folgende Zeile hinzu für stündliche Ausführung:
```
0 * * * * /usr/local/bin/proxmox_local_monitor.sh
```

## Konfiguration

### Schwellwerte
Passen Sie die Schwellwerte am Anfang des Scripts nach Ihren Bedürfnissen an:
```bash
# Schwellwerte
CPU_THRESHOLD=80        # in Prozent
RAM_THRESHOLD=80        # in Prozent
STORAGE_THRESHOLD=80    # in Prozent
INODE_THRESHOLD=80      # in Prozent
TEMP_THRESHOLD=65       # in Grad Celsius
SMART_THRESHOLD=10      # Anzahl reallocated sectors
ZFS_SCRUB_DAYS=30      # Maximales Alter des letzten Scrubs
BACKUP_AGE_HOURS=26    # Maximales Alter des letzten Backups
```

### Telegram-Bot Einrichtung
1. Erstellen Sie einen neuen Bot über den [@BotFather](https://t.me/botfather)
2. Kopieren Sie den Bot-Token
3. Starten Sie eine Konversation mit Ihrem Bot
4. Rufen Sie https://api.telegram.org/bot<IHR_BOT_TOKEN>/getUpdates auf
5. Kopieren Sie die Chat-ID aus der Antwort

### Logging
Die Logs werden in `/var/log/proxmox_monitor.log` gespeichert und automatisch nach 7 Tagen gelöscht.

## Überwachte Metriken

### System-Ressourcen
- CPU-Auslastung
- RAM-Auslastung
- Speicherplatz-Nutzung
- Inode-Nutzung
- CPU-Temperatur

### Hardware
- SMART-Status aller Festplatten
- Reallocated Sectors Count
- Festplatten-Temperatur (falls verfügbar)

### ZFS (falls vorhanden)
- Pool-Status
- Scrub-Alter
- Fehler und Warnungen

### Backups
- Alter des letzten Backups (PBS)
- Backup-Fehler

### Dienste
- pve-cluster
- pvedaemon
- pveproxy
- pvestatd
- pvescheduler

## Fehlerbehebung

### Häufige Probleme

1. Script wird nicht ausgeführt:
   - Überprüfen Sie die Berechtigungen: `chmod +x /usr/local/bin/proxmox_local_monitor.sh`
   - Überprüfen Sie den Cron-Job: `grep proxmox_local_monitor /var/log/syslog`

2. Keine Telegram-Nachrichten:
   - Überprüfen Sie Bot-Token und Chat-ID
   - Testen Sie den Bot manuell: `curl -s -X POST "https://api.telegram.org/bot<TOKEN>/sendMessage" -d chat_id="<CHAT_ID>" -d text="Test"`

3. SMART-Fehler:
   - Installieren Sie smartmontools: `apt-get install smartmontools`
   - Überprüfen Sie die Festplatten-Berechtigungen

### Logs überprüfen
```bash
tail -f /var/log/proxmox_monitor.log
```

## Lizenz

Dieses Projekt ist unter der MIT-Lizenz lizenziert - siehe die [LICENSE](LICENSE) Datei für Details.

## Beitragen

Beiträge sind willkommen! Bitte erstellen Sie einen Fork des Projekts und einen Pull Request mit Ihren Änderungen.