#!/bin/bash

# proxmox_local_monitor.sh
# Erweitertes Monitoring-Script für lokale Proxmox-Überwachung inkl. VMs und Dienste

# Konfigurationsvariablen
TELEGRAM_BOT_TOKEN="your-token"
HOSTNAME=$(hostname)
TELEGRAM_CHAT_ID="your-chat-id"

# Schwellwerte System
CPU_THRESHOLD=80        # in Prozent
RAM_THRESHOLD=80        # in Prozent
STORAGE_THRESHOLD=80    # in Prozent
INODE_THRESHOLD=80      # in Prozent
TEMP_THRESHOLD=65       # in Grad Celsius
SMART_THRESHOLD=10      # Anzahl reallocated sectors
ZFS_SCRUB_DAYS=30       # Maximales Alter des letzten Scrubs
BACKUP_AGE_HOURS=26     # Maximales Alter des letzten Backups

# Schwellwerte VMs
VM_CPU_THRESHOLD=90     # in Prozent
VM_RAM_THRESHOLD=90     # in Prozent
VM_STORAGE_THRESHOLD=85 # in Prozent
VM_BACKUP_AGE_DAYS=2    # Maximales Alter des letzten VM-Backups

# Pfade
LOG_FILE="/var/log/proxmox_monitor.log"
TEMP_FILE="/tmp/proxmox_monitor_state"
STATE_DIR="/var/lib/proxmox_monitor"
mkdir -p "$STATE_DIR"

# Logging-Funktion
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Funktion zum Senden von Telegram-Nachrichten
send_telegram_message() {
    local message="$1"
    local formatted_message="🖥️ <b>Host:</b> ${HOSTNAME}\n${message}"
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d chat_id="${TELEGRAM_CHAT_ID}" \
        -d parse_mode="HTML" \
        -d text="${formatted_message}" > /dev/null
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
        "corosync:Cluster Communication"
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

# Funktion zum Prüfen der VM-Backups
check_vm_backups() {
    local alerts=""
    local backup_dir="/var/lib/vz/dump"
    local current_time=$(date +%s)
    
    # Prüfe PBS-Backups falls verfügbar
    if command -v proxmox-backup-client >/dev/null; then
        local pbs_status
        pbs_status=$(proxmox-backup-client list 2>/dev/null)
        if [ $? -eq 0 ]; then
            while IFS= read -r backup; do
                local backup_time
                backup_time=$(echo "$backup" | awk '{print $NF}')
                local backup_age_days=$(( (current_time - $(date -d "$backup_time" +%s)) / 86400 ))
                
                if [ "$backup_age_days" -gt "$VM_BACKUP_AGE_DAYS" ]; then
                    alerts="${alerts}⚠️ PBS-Backup ist ${backup_age_days} Tage alt\n"
                fi
            done < <(echo "$pbs_status" | grep -v "^$")
        fi
    fi
    
    # Prüfe lokale vzdump-Backups
    if [ -d "$backup_dir" ]; then
        while IFS= read -r backup_file; do
            local file_age_days=$(( (current_time - $(stat -c %Y "$backup_file")) / 86400 ))
            local vmid=$(echo "$backup_file" | grep -o 'vzdump-qemu-[0-9]*' | grep -o '[0-9]*')
            
            if [ "$file_age_days" -gt "$VM_BACKUP_AGE_DAYS" ]; then
                alerts="${alerts}⚠️ Lokales Backup für VM ${vmid} ist ${file_age_days} Tage alt\n"
            fi
        done < <(find "$backup_dir" -name "vzdump-qemu-*" -type f -mtime -30)
    fi
    
    echo "$alerts"
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
            
            if [ ! -z "$await" ] && [ $(echo "$await > 100" | bc -l) -eq 1 ]; then
                high_io_devices="${high_io_devices}${device} (${await}ms) "
            fi
        done < <(iostat -x 1 2 | tail -n +4)
        
        if [ ! -z "$high_io_devices" ]; then
            alerts="${alerts}⚠️ Hohe IO-Latenz auf: ${high_io_devices}\n"
        fi
    fi
    
    echo "$alerts"
}

# Hauptfunktion
main() {
    local alerts=""
    
    # Bestehende Checks beibehalten
    alerts+=$(check_system_resources)
    alerts+=$(check_cpu_temp)
    alerts+=$(check_smart_status)
    alerts+=$(check_zfs_status)
    alerts+=$(check_backup_status)
    
    # Neue Checks hinzufügen
    alerts+=$(check_pve_services)
    alerts+=$(check_vms_and_containers)
#    alerts+=$(check_storage_performance)
    
    # Wenn Alerts vorhanden sind und sich seit dem letzten Lauf geändert haben
    if [ ! -z "$alerts" ]; then
        if [ ! -f "$TEMP_FILE" ] || [ "$(cat "$TEMP_FILE")" != "$alerts" ]; then
            send_telegram_message "$alerts"
            echo "$alerts" > "$TEMP_FILE"
            log "$alerts"
        fi
    fi
}

# Aufräumen alter Logs (älter als 7 Tage)
find "$LOG_FILE" -mtime +7 -delete 2>/dev/null

# Script ausführen
main
