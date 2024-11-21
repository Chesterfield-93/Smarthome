#!/bin/bash

git pull
cp proxmox-v1.sh /usr/local/bin/proxmox-monitor.sh 
cp parameters /usr/local/bin/
dos2unix /usr/local/bin/proxmox-monitor.sh
chmod +x /usr/local/bin/proxmox-monitor.sh
systemctl daemon-reload
systemctl stop proxmox-monitor.service
rm /var/lib/proxmox_monitor/last_info_time
rm /var/lib/proxmox_monitor/last_status_time
systemctl start proxmox-monitor.service
systemctl status proxmox-monitor.service

#/usr/local/bin/proxmox-monitor.sh
