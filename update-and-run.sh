#!/bin/bash

cp proxmox-v1.sh /usr/local/bin/proxmox-monitor.sh 
cp parameters /usr/local/bin/
dos2unix /usr/local/bin/proxmox-monitor.sh
chmod +x /usr/local/bin/proxmox-monitor.sh
/usr/local/bin/proxmox-monitor.sh
