# Proxmox Monitoring Script

Dieses Skript dient zur erweiterten Überwachung von Proxmox-Servern, einschließlich VMs und Diensten. Es überwacht verschiedene Systemressourcen und sendet Benachrichtigungen über Telegram.

## Funktionen des Skripts

### Konfigurationsvariablen
- **TELEGRAM_BOT_TOKEN**: Token für den Telegram-Bot.
- **TELEGRAM_CHAT_ID**: Chat-ID für Telegram-Benachrichtigungen.
- **HOSTNAME**: Hostname des Servers.
- **Schwellwerte**: CPU, RAM, Speicher, Inodes, Temperatur, SMART-Werte, ZFS-Scrub-Tage und Backup-Alter.
- **VM-Schwellwerte**: CPU, RAM, Speicher und Backup-Alter.

### Pfade
- **LOG_FILE**: Pfad zur Log-Datei.
- **TEMP_FILE**: Pfad zur temporären Datei.
- **STATE_DIR**: Verzeichnis für Statusdateien.

### Hauptfunktionen
1. **Logging**: Protokolliert Nachrichten mit Zeitstempel.
2. **Telegram-Benachrichtigungen**: Sendet Nachrichten über Telegram.
3. **Prüfung der Proxmox-Dienste**: Überprüft den Status wichtiger Proxmox-Dienste und den Cluster-Status.
4. **Prüfung der VMs und Container**: Überwacht den Status und die Ressourcennutzung von VMs und Containern.
5. **Prüfung der VM-Backups**: Überprüft das Alter der VM-Backups, sowohl lokal als auch auf Proxmox Backup Servern.
6. **Prüfung der Storage-Performance**: Testet die IO-Leistung von Speichergeräten.

## Implementierung als Systemd-Dienst

### 1. Skript vorbereiten
Stelle sicher, dass dein Skript ausführbar ist:
```bash
chmod +x /usr/local/bin/proxmox-v1.sh
```
###2. Systemd-Dienstdatei erstellen
Erstelle eine neue Dienstdatei für dein Skript:
```bash
sudo nano /etc/systemd/system/proxmox-monitor.service
```
###3. Dienstdatei konfigurieren
Füge den folgenden Inhalt in die Datei ein:
```bash
[Unit]
Description=Proxmox Monitoring Script
After=network.target

[Service]
ExecStart=/usr/local/bin/proxmox-v1.sh
WorkingDirectory=/usr/local/bin/
StandardOutput=journal
StandardError=journal
Restart=always
User=root

[Install]
WantedBy=multi-user.target
```
###4. Dienstdatei speichern und schließen
Speichere die Datei und schließe den Texteditor.

###5. Systemd-Dienst neu laden
Lade die Systemd-Dienste neu, um die neue Dienstdatei zu erkennen:
```bash
sudo systemctl daemon-reload
```
###6. Dienst starten und aktivieren
Starte den Dienst und aktiviere ihn, damit er beim Systemstart automatisch gestartet wird:
```bash
sudo systemctl start proxmox-monitor.service
sudo systemctl enable proxmox-monitor.service
```
###7. Dienststatus überprüfen
Überprüfe den Status des Dienstes, um sicherzustellen, dass er korrekt läuft:
```bash
sudo systemctl status proxmox-monitor.service
```
