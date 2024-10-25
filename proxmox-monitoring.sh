#!/bin/bash

# Konfiguration
BOT_TOKEN="HIER_BOT_TOKEN_EINFÜGEN"
GROUP_ID="HIER_GRUPPEN_ID"

# Funktion zum Senden von Telegram Nachrichten
send_telegram() {
    local message="$1"
    local url="https://api.telegram.org/bot${BOT_TOKEN}/sendMessage"
    curl -s -X POST "$url" \
        -d "chat_id=${GROUP_ID}" \
        -d "text=${message}" \
        -d "parse_mode=HTML"
}

# Funktion zum Prüfen der Festplattennutzung
check_disk_space() {
    local threshold=90  # Warnung ab 90% Nutzung
    local disks=$(df -h | grep '^/dev/' | awk '{print $6 ":" $5}' | sed 's/%//')
    
    while IFS=: read -r mount usage; do
        if [ "${usage}" -gt "${threshold}" ]; then
            send_telegram "🚨 <b>Warnung: Speicherplatz kritisch</b>
Mount: ${mount}
Nutzung: ${usage}%"
        fi
    done <<< "${disks}"
}

# Funktion zum Prüfen der RAM-Nutzung
check_memory() {
    local threshold=90  # Warnung ab 90% Nutzung
    local memory=$(free | grep Mem | awk '{print ($3/$2 * 100)}' | cut -d. -f1)
    
    if [ "${memory}" -gt "${threshold}" ]; then
        local free_mem=$(free -h | grep "Mem:" | awk '{print $4}')
        send_telegram "🚨 <b>Warnung: Arbeitsspeicher kritisch</b>
Nutzung: ${memory}%
Frei: ${free_mem}"
    fi
}

# Funktion zum Prüfen der CPU-Last
check_cpu_load() {
    local threshold=80  # Warnung ab 80% Last
    local cpu_load=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d. -f1)
    
    if [ "${cpu_load}" -gt "${threshold}" ]; then
        send_telegram "🚨 <b>Warnung: CPU-Last kritisch</b>
Last: ${cpu_load}%"
    fi
}

# Funktion zum Prüfen der SMART-Status der Festplatten
check_smart_status() {
    local disks=$(lsblk -d -n -o NAME | grep '^sd')
    
    for disk in ${disks}; do
        local smart_status=$(smartctl -H "/dev/${disk}" | grep "SMART overall-health" | awk '{print $6}')
        if [ "${smart_status}" != "PASSED" ]; then
            send_telegram "🚨 <b>Warnung: SMART-Status kritisch</b>
Festplatte: /dev/${disk}
Status: ${smart_status}"
        fi
    done
}

# Funktion zum Prüfen der ZFS Pool Status (falls vorhanden)
check_zfs_status() {
    if command -v zpool >/dev/null 2>&1; then
        local pools=$(zpool list -H -o name,health | grep -v ONLINE)
        if [ ! -z "${pools}" ]; then
            send_telegram "🚨 <b>Warnung: ZFS Pool Problem</b>
${pools}"
        fi
    fi
}

# Funktion zum Prüfen der Dienste
check_services() {
    local services="pvedaemon pveproxy pvestatd"
    
    for service in ${services}; do
        if ! systemctl is-active --quiet "${service}"; then
            send_telegram "🚨 <b>Warnung: Proxmox Dienst ausgefallen</b>
Service: ${service}"
        fi
    done
}

# Funktion zum Prüfen der VM/CT Status
check_vm_status() {
    local vms=$(qm list | tail -n +2 | awk '{if ($3 == "stopped") print $1}')
    if [ ! -z "${vms}" ]; then
        send_telegram "ℹ️ <b>Info: Gestoppte VMs gefunden</b>
VM IDs: ${vms}"
    fi
}

# Hauptfunktion zum Ausführen aller Checks
run_checks() {
    check_disk_space
    check_memory
    check_cpu_load
    check_smart_status
    check_zfs_status
    check_services
    check_vm_status
}

# Führe alle Checks aus
run_checks