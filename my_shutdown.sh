#!/bin/bash

LOG_FILE="/var/log/ups.log"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" >> "$LOG_FILE"
}

log "Arrêt des VMs..."

virsh list --all --name | while read -r vm
do
    [ -z "$vm" ] && continue

    log ""
    # Vérifie que la VM est démarrée
    if virsh domstate "$vm" | grep -q running
    then
        log "Arrêt de $vm"
        virsh shutdown "$vm"

        while virsh domstate "$vm" | grep -q running
        do
            log "$vm en train de shutdown..."
            sleep 2
        done

        log "$vm arrêtée"
    fi
done

log ""
log "Arrêt immédiat du serveur"
shutdown -h now
