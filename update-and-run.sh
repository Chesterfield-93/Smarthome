#!/bin/bash

git pull
cp proxmox-v1.sh /usr/local/bin/proxmox-monitor.sh 
cp parameters /usr/local/bin/
dos2unix /usr/local/bin/proxmox-monitor.sh
chmod +x /usr/local/bin/proxmox-monitor.sh
systemctl daemon-reload
systemctl restart proxmox-monitor.service
systemctl status proxmox-monitor.service

#/usr/local/bin/proxmox-monitor.sh
