#!/bin/bash

# proxmox_local_monitor.sh
# Erweitertes Monitoring-Script für lokale Proxmox-Überwachung inkl. VMs und Dienste

# Konfigurationsvariablen
# Laden der parameters Datei
if ! source ./parameters; then
  echo "Fehler: Die Datei 'parameters' konnte nicht gesourced werden."
  exit 1
fi
# Laden der telegram-config Datei
if ! source ./telegram-config; then
  echo "Fehler: Die Datei 'telegram-config' konnte nicht gesourced werden."
  exit 1
fi

mkdir -p "$STATE_DIR"

# Logging-Funktion
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Funktion zum Senden von Telegram-Nachrichten
send_telegram_message() {
    local message="$1"
    local formatted_message=$(echo -e "$message" | sed 's/\\n/%0A/g')
    formatted_message="🖥️ <b>Host:</b> ${HOSTNAME}%0A${formatted_message}"
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d chat_id="${TELEGRAM_CHAT_ID}" \
    -d parse_mode="HTML" \
    -d text="${formatted_message}" > /dev/null
}

# Funktion zum Überprüfen und Senden einer regelmäßigen Statusnachricht
check_and_send_status_message() {
    local interval=${STATUS_INTERVAL:-3600}  # Standard: 3600 Sekunden (1 Stunde), wenn nicht anders definiert
    local last_status_file="$STATE_DIR/last_status_time"
    local current_time=$(date +%s)

    # Überprüfen, wann die letzte Statusnachricht gesendet wurde
    if [ -f "$last_status_file" ]; then
        local last_status_time=$(cat "$last_status_file")
        local time_diff=$((current_time - last_status_time))
        if [ "$time_diff" -ge "$interval" ]; then
            alerts="${alerts}ℹ️ Das Überwachungsskript läuft noch.\n"
            echo "$current_time" > "$last_status_file"
        fi
    else
        # Wenn die Datei nicht existiert, Statusnachricht senden und Datei erstellen
        alerts="${alerts}ℹ️ Das Überwachungsskript läuft noch.\n"
        echo "$current_time" > "$last_status_file"
    fi
}

# Funktion zum Senden von Systeminformationen in regelmäßigen Abständen
send_system_info() {
    local interval=${SYSTEM_INFO_INTERVAL:-86400}  # Standard: 86400 Sekunden (24 Stunden), wenn nicht anders definiert
    local last_info_file="$STATE_DIR/last_info_time"
    local current_time=$(date +%s)

    # Überprüfen, ob die Datei existiert, und erstellen, falls nicht
    if [ ! -f "$last_info_file" ]; then
        echo "$current_time" > "$last_info_file"
    fi

    local last_info_time=$(cat "$last_info_file")
    local time_diff=$((current_time - last_info_time))
    if [ "$time_diff" -ge "$interval" ]; then
        # Sammeln der SMART-Daten der Festplatten
        local system_info=""
        for disk in $(lsblk -dnp -o NAME); do
            if smartctl -H "$disk" > /dev/null 2>&1; then
                local smart_status
                smart_status=$(smartctl -H "$disk" | grep -i "smart overall-health" | awk '{print $NF}')
                local reallocated
                reallocated=$(smartctl -A "$disk" | grep "Reallocated_Sector_Ct" | awk '{print $10}')
                system_info="${system_info}Festplatte: ${disk}\nSMART-Status: ${smart_status}\nReallocated Sectors: ${reallocated}\n\n"
            fi
        done

        # Weitere Systeminformationen können hier hinzugefügt werden

        send_telegram_message "Systeminformationen:%0A${system_info}"
        echo "$current_time" > "$last_info_file"
    fi
}

# Funktion zum Überprüfen und Senden einer regelmäßigen Statusnachricht
check_and_send_status_message() {
    local interval=${STATUS_INTERVAL:-3600}  # Standard: 3600 Sekunden (1 Stunde), wenn nicht anders definiert
    local last_status_file="$STATE_DIR/last_status_time"
    local current_time=$(date +%s)
    local status_message=""

    # Überprüfen, wann die letzte Statusnachricht gesendet wurde
    if [ -f "$last_status_file" ]; then
        local last_status_time=$(cat "$last_status_file")
        local time_diff=$((current_time - last_status_time))
        if [ "$time_diff" -ge "$interval" ]; then
            status_message="ℹ️ Das Überwachungsskript läuft noch.\n"
            echo "$current_time" > "$last_status_file"
        fi
    else
        # Wenn die Datei nicht existiert, Statusnachricht senden und Datei erstellen
        status_message="ℹ️ Das Überwachungsskript läuft noch.\n"
        echo "$current_time" > "$last_status_file"
    fi

    echo "$status_message"
}

# Funktion zum Prüfen der Proxmox-Dienste
check_pve_services() {
    local alerts=""
    local services=(
        "pve-cluster:Cluster Service"
        "pvedaemon:API Daemon"
        "pveproxy:Web Interface"
        "pvestatd:Status Daemon"
        "pvescheduler:Task Scheduler"
        #"corosync:Cluster Communication"
        "proxmox-backup:Backup Service"
        "vz:Container Management"
        "qemu-server:VM Management"
        "ceph.target:Ceph Storage"
        "pve-firewall:Firewall"
    )
    
    for service_info in "${services[@]}"; do
        IFS=':' read -r service description <<< "$service_info"
        if systemctl is-enabled "$service" &>/dev/null; then
            if ! systemctl is-active --quiet "$service"; then
                alerts="${alerts}⚠️ ${description} (${service}) ist nicht aktiv\n"
            fi
        fi
    done
    
    # Cluster-Status prüfen
    if command -v pvecm >/dev/null; then
        local cluster_status
        cluster_status=$(pvecm status 2>&1)
        if echo "$cluster_status" | grep -qi "error\|warning"; then
            alerts="${alerts}⚠️ Cluster-Problem erkannt:\n$(echo "$cluster_status" | grep -i 'error\|warning')\n"
        fi
    fi
    
    echo "$alerts"
}

# Funktion zum Prüfen der VMs und Container
check_vms_and_containers() {
    local alerts=""
    local vm_list=""
    local ct_list=""
    
    # Status-Datei für VM/CT-Zustände
    local state_file="$STATE_DIR/vm_states"
    
    # VMs prüfen
    while IFS= read -r line; do
        local vmid status name
        vmid=$(echo "$line" | awk '{print $1}')
        status=$(echo "$line" | awk '{print $2}')
        name=$(echo "$line" | awk '{print $3}')
        
        # VM-Status tracken
        local prev_status
        prev_status=$(grep "^${vmid}:" "$state_file" 2>/dev/null | cut -d: -f2)
        
        if [ "$status" != "running" ]; then
            if [ -z "$prev_status" ] || [ "$prev_status" = "running" ]; then
                alerts="${alerts}⚠️ VM ${name} (ID: ${vmid}) ist ${status}\n"
            fi
        fi
        
        echo "${vmid}:${status}" >> "${state_file}.tmp"
        
        if [ "$status" = "running" ]; then
            # CPU- und RAM-Nutzung für laufende VMs prüfen
            local vm_stats
            vm_stats=$(qm monitor "$vmid" info cpus memory 2>/dev/null)
            if [ $? -eq 0 ]; then
                local cpu_usage
                cpu_usage=$(echo "$vm_stats" | grep "CPU" | awk '{print $2}' | tr -d '%')

                local mem_usage
                mem_usage=$(echo "$vm_stats" | grep "memory" | awk '{print $2}' | tr -d '%')

                if [ -n "$cpu_usage" ] && [ "$cpu_usage" -gt "$VM_CPU_THRESHOLD" ]; then
                alerts="${alerts}⚠️ VM ${name} (ID: ${vmid}) - Hohe CPU-Last: ${cpu_usage}%\n"
                fi

                if [ -n "$mem_usage" ] && [ "$mem_usage" -gt "$VM_RAM_THRESHOLD" ]; then
                alerts="${alerts}⚠️ VM ${name} (ID: ${vmid}) - Hohe RAM-Nutzung: ${mem_usage}%\n"
                fi

                # Festplattennutzung prüfen (via qemu-guest-agent)
                if qm agent "$vmid" ping >/dev/null 2>&1; then
                local disk_usage
                disk_usage=$(qm agent "$vmid" exec "df -h /" 2>/dev/null | awk 'NR==2 {print $5}' | tr -d '%')
                if [ -n "$disk_usage" ] && [ "$disk_usage" -gt "$VM_STORAGE_THRESHOLD" ]; then
                    alerts="${alerts}⚠️ VM ${name} (ID: ${vmid}) - Hohe Festplattennutzung: ${disk_usage}%\n"
                fi
                fi
            fi
        fi

    done < <(qm list 2>/dev/null | tail -n +2)
    
    # Container prüfen
    while IFS= read -r line; do
        local ctid status name
        ctid=$(echo "$line" | awk '{print $1}')
        status=$(echo "$line" | awk '{print $2}')
        name=$(echo "$line" | awk '{print $3}')
        
        # Container-Status tracken
        local prev_status
        prev_status=$(grep "^CT${ctid}:" "$state_file" 2>/dev/null | cut -d: -f2)
        
        if [ "$status" != "running" ]; then
            if [ -z "$prev_status" ] || [ "$prev_status" = "running" ]; then
                alerts="${alerts}⚠️ Container ${name} (ID: ${ctid}) ist ${status}\n"
            fi
        fi
        
        echo "CT${ctid}:${status}" >> "${state_file}.tmp"
        
        if [ "$status" = "running" ]; then
        # Ressourcennutzung für laufende Container prüfen
        local ct_stats
        ct_stats=$(pct exec "$ctid" -- top -bn1 2>/dev/null)
        if [ $? -eq 0 ]; then
            local cpu_usage
            cpu_usage=$(echo "$ct_stats" | grep "Cpu(s)" | awk '{print $2}' | cut -d. -f1)

            local mem_info
            mem_info=$(pct exec "$ctid" -- free -m 2>/dev/null)
            local mem_total
            local mem_used
            local mem_usage
            mem_total=$(echo "$mem_info" | awk '/Mem:/ {print $2}')
            mem_used=$(echo "$mem_info" | awk '/Mem:/ {print $3}')
            if [ -n "$mem_total" ] && [ -n "$mem_used" ] && [ "$mem_total" -gt 0 ]; then
                mem_usage=$(( (mem_used * 100) / mem_total ))

                if [ "$mem_usage" -gt "$VM_RAM_THRESHOLD" ]; then
                    alerts="${alerts}⚠️ Container ${name} (ID: ${ctid}) - Hohe RAM-Nutzung: ${mem_usage}%\n"
                fi
            fi

            # Festplattennutzung prüfen
            local disk_usage
            disk_usage=$(pct exec "$ctid" -- df -h / 2>/dev/null | awk 'NR==2 {print $5}' | tr -d '%')
            if [ -n "$disk_usage" ] && [ "$disk_usage" -gt "$VM_STORAGE_THRESHOLD" ]; then
                alerts="${alerts}⚠️ Container ${name} (ID: ${ctid}) - Hohe Festplattennutzung: ${disk_usage}%\n"
            fi
        fi
    fi
    done < <(pct list 2>/dev/null | tail -n +2)
    
    # Status-Datei aktualisieren
    mv "${state_file}.tmp" "$state_file" 2>/dev/null

    # Backup-Status prüfen
    alerts+=$(check_vm_backups)

    echo "$alerts"
}

# Funktion zum Prüfen der VM-Backup    s
check_backups() {
    local alerts=""
    local backup_dir="/var/lib/vz/dump"
    local current_time=$(date +%s)
    local MAX_BACKUP_AGE_HOURS=${MAX_BACKUP_AGE_HOURS:-24}  # Standard: 24 Stunden, wenn nicht anders definiert
    
    # PBS-Backup-Status prüfen (wenn vorhanden)
    if [ -d "/etc/proxmox-backup" ]; then
        # PBS-Backups prüfen
        if command -v proxmox-backup-client >/dev/null; then
            local pbs_status
            pbs_status=$(proxmox-backup-client list 2>/dev/null)
            if [ $? -eq 0 ]; then
                while IFS= read -r backup; do
                    local backup_time
                    backup_time=$(echo "$backup" | awk '{print $NF}')
                    local backup_age_hours=$(( (current_time - $(date -d "$backup_time" +%s)) / 3600 ))
                    
                    if [ "$backup_age_hours" -gt "$MAX_BACKUP_AGE_HOURS" ]; then
                        # Füge Tage zur besseren Lesbarkeit hinzu, wenn > 24 Stunden
                        if [ "$backup_age_hours" -gt 24 ]; then
                            local days=$((backup_age_hours / 24))
                            local remaining_hours=$((backup_age_hours % 24))
                            alerts="${alerts}⚠️ PBS-Backup ist ${days} Tage und ${remaining_hours} Stunden alt\n"
                        else
                            alerts="${alerts}⚠️ PBS-Backup ist ${backup_age_hours} Stunden alt\n"
                        fi
                    fi
                done < <(echo "$pbs_status" | grep -v "^$")
            fi
        fi
    fi
    
    # Lokale vzdump-Backups prüfen
    if [ -d "$backup_dir" ]; then
        while IFS= read -r backup_file; do
            local backup_age_hours=$(( (current_time - $(stat -c %Y "$backup_file")) / 3600 ))
            local vmid=$(echo "$backup_file" | grep -o 'vzdump-qemu-[0-9]*' | grep -o '[0-9]*')
            
            if [ "$backup_age_hours" -gt "$MAX_BACKUP_AGE_HOURS" ]; then
                # Füge Tage zur besseren Lesbarkeit hinzu, wenn > 24 Stunden
                if [ "$backup_age_hours" -gt 24 ]; then
                    local days=$((backup_age_hours / 24))
                    local remaining_hours=$((backup_age_hours % 24))
                    alerts="${alerts}⚠️ Lokales Backup für VM ${vmid} ist ${days} Tage und ${remaining_hours} Stunden alt\n"
                else
                    alerts="${alerts}⚠️ Lokales Backup für VM ${vmid} ist ${backup_age_hours} Stunden alt\n"
                fi
            fi
        done < <(find "$backup_dir" -name "vzdump-qemu-*" -type f -mtime -30)
    fi
    
    echo -e "$alerts"
}

# Funktion zum Prüfen der Storage Performance
check_storage_performance() {
    local alerts=""
    local test_file="/var/tmp/iostat_test"
    
    # IO-Stat Installation prüfen
    if ! command -v iostat >/dev/null; then
        apt-get update >/dev/null && apt-get install -y sysstat >/dev/null
    fi
    
    # Storage-Performance testen
    if command -v iostat >/dev/null; then
        local high_io_devices=""
        while IFS= read -r line; do
            local device
            local await
            device=$(echo "$line" | awk '{print $1}')
            await=$(echo "$line" | awk '{print $10}')
            
            if [[ "$await" =~ ^[0-9]+(\.[0-9]+)?$ ]] && [ $(echo "$await > 100" | bc -l) -eq 1 ]; then
                high_io_devices="${high_io_devices}${device} (${await}ms) "
            fi

        done < <(iostat -x 1 2 | tail -n +4)
        
        if [ ! -z "$high_io_devices" ]; then
            alerts="${alerts}⚠️ Hohe IO-Latenz auf: ${high_io_devices}\n"
        fi
    fi
    
    echo "$alerts"
}

# CPU-Temperatur prüfen
check_cpu_temp() {
    if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
        local temp
        temp=$(( $(cat /sys/class/hwmon/hwmon5/temp1_input) / 1000))
        if [ "$temp" -gt "$TEMP_THRESHOLD" ]; then
            echo "⚠️ CPU-Temperatur: ${temp}°C"
        fi
    fi
}

# SMART-Status prüfen
check_smart_status() {
    local alerts=""
    for disk in $(lsblk -dnp -o NAME); do
        if smartctl -H "$disk" > /dev/null 2>&1; then
            local smart_status
            smart_status=$(smartctl -H "$disk" | grep -i "smart overall-health" | awk '{print $NF}')
            local reallocated
            reallocated=$(smartctl -A "$disk" | grep "Reallocated_Sector_Ct" | awk '{print $10}')
            
            if [ "$smart_status" != "PASSED" ]; then
                alerts="${alerts}⚠️ SMART-Status für ${disk}: ${smart_status}\n"
            fi
            
            if [ ! -z "$reallocated" ] && [ "$reallocated" -gt "$SMART_THRESHOLD" ]; then
                alerts="${alerts}⚠️ Reallocated Sectors für ${disk}: ${reallocated}\n"
            fi
        fi
    done
    echo "$alerts"
}

# ZFS-Status prüfen
check_zfs_status() {
    local alerts=""
    if command -v zpool > /dev/null; then
        # Pool-Status prüfen
        local pool_status
        pool_status=$(zpool status | grep -E "state:|errors:")
        
        # Filtere den Status "state: ONLINE" und "errors: No known data errors" heraus
        pool_status=$(echo "$pool_status" | grep -v -E "state: ONLINE|errors: No known data errors")

        if [ ! -z "$pool_status" ]; then
            alerts="${alerts}⚠️ ZFS-Pool-Probleme gefunden:\n${pool_status}\n"
        fi

        # Scrub-Alter prüfen
        for pool in $(zpool list -H -o name); do
            local scrub_age
            scrub_age=$(zpool status "$pool" | grep "scan" | grep -oP "(?<=scrub on )[^)]+")
            if [ ! -z "$scrub_age" ]; then
                local days_since_scrub
                days_since_scrub=$(( ( $(date +%s) - $(date -d "$scrub_age" +%s) ) / 86400 ))
                if [ "$days_since_scrub" -gt "$ZFS_SCRUB_DAYS" ]; then
                    alerts="${alerts}⚠️ Letzter ZFS Scrub für ${pool} ist ${days_since_scrub} Tage alt\n"
                fi
            fi
        done
    fi
    echo "$alerts"
}

# System-Ressourcen prüfen
check_system_resources() {
    local alerts=""
    
    # CPU-Auslastung
    local cpu_usage
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d. -f1)
    if [ "$cpu_usage" -gt "$CPU_THRESHOLD" ]; then
        alerts="${alerts}⚠️ CPU-Auslastung: ${cpu_usage}%\n"
    fi
    
    # RAM-Auslastung
    local mem_total
    local mem_used
    local mem_usage
    mem_total=$(free -m | awk '/Mem:/ {print $2}')
    mem_used=$(free -m | awk '/Mem:/ {print $3}')
    mem_usage=$(( (mem_used * 100) / mem_total ))
    if [ "$mem_usage" -gt "$RAM_THRESHOLD" ]; then
        alerts="${alerts}⚠️ RAM-Auslastung: ${mem_usage}%\n"
    fi
    
    # Speicherplatz und Inodes
    while IFS= read -r line; do
        local usage
        local mount
        usage=$(echo "$line" | awk '{print $5}' | cut -d% -f1)
        mount=$(echo "$line" | awk '{print $6}')
        if [ "$usage" -gt "$STORAGE_THRESHOLD" ]; then
            alerts="${alerts}⚠️ Speicherplatz auf ${mount}: ${usage}%\n"
        fi
    done < <(df -h | grep -vE '^Filesystem|tmpfs|cdrom|udev')
    
    while IFS= read -r line; do
        local inode_usage
        local mount
        inode_usage=$(echo "$line" | awk '{print $5}' | cut -d% -f1)

        mount=$(echo "$line" | awk '{print $6}')
        if [[ "$inode_usage" =~ ^[0-9]+$ ]] && [ "$inode_usage" -gt "$INODE_THRESHOLD" ]; then
            alerts="${alerts}⚠️ Inode-Nutzung auf ${mount}: ${inode_usage}%\n"
        fi
    done < <(df -i | grep -vE '^Filesystem|tmpfs|cdrom|udev')
    
    echo "$alerts"
}

# Dienste-Status prüfen
check_services() {
    local alerts=""
    local services=("pvedaemon" "pveproxy" "pvestatd" "pvescheduler")
    
    for service in "${services[@]}"; do
        if ! systemctl is-active --quiet "$service"; then
            alerts="${alerts}⚠️ Service ${service} ist nicht aktiv\n"
        fi
    done
    echo "$alerts"
}

# Hauptfunktion
main() {
    local alerts=""
    
    # Systeminformationen überprüfen und senden
    send_system_info

    # Statusnachricht überprüfen und senden
    alerts+=$(check_and_send_status_message)

    # Bestehende Checks beibehalten
    echo "check_system_resources"
    alerts+=$(check_system_resources)
    echo "check_cpu_temp"
    alerts+=$(check_cpu_temp)
    echo "check_smart_status"
    alerts+=$(check_smart_status)
    echo "check_zfs_status"
    alerts+=$(check_zfs_status)
    echo "check_pve_services"
    alerts+=$(check_pve_services)
    echo "check_backups"
    alerts+=$(check_backups)
    echo "check_storage_performance"
    alerts+=$(check_storage_performance)
    echo "check_services"
    alerts+=$(check_services)

    # Wenn Alerts vorhanden sind und sich seit dem letzten Lauf geändert haben
    if [ ! -z "$alerts" ]; then
        if [ ! -f "$TEMP_FILE" ] || [ "$(cat "$TEMP_FILE")" != "$alerts" ]; then
            echo "Sende Telegram Nachricht:"
            echo "$alerts"
            send_telegram_message "$alerts"
            echo "$alerts" > "$TEMP_FILE"
            log "$alerts"
        fi
    fi
}

# Aufräumen alter Logs (älter als 7 Tage)
find "$LOG_FILE" -mtime +7 -delete 2>/dev/null

# Endlosschleife mit Schlafintervall
while true; do
    main
    sleep $SLEEP_INTERVAL  # Warten, bevor das Skript erneut ausgeführt wird
done
