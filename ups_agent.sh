#!/bin/bash

LOG_FILE=/var/log/ups_monitor.log
THRESHOLD_LOWBATT=3200
THRESHOLD_RESTARTVM=4000

LOCK_FILE="/tmp/ups_agent.lock"
FLAG_UPS1_LOWBATT="/tmp/UPS1_LOWBATT"
FLAG_UPS2_LOWBATT="/tmp/UPS2_LOWBATT"
FLAG_VM_SHUTDOWN="/tmp/VM_SHUTDOWN"



log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" >> "$LOG_FILE"
}



stop_vm () {
    local vms running_vms=()
    local max_wait=180
    local interval=5
    local elapsed=0

    vms=$(virsh -c qemu:///system list --all --name)

    while read -r vm
    do
        [ -z "$vm" ] && continue
        if virsh -c qemu:///system domstate "$vm" | grep -q running
        then
            log "Arrêt de $vm"
            virsh -c qemu:///system shutdown "$vm"
            running_vms+=("$vm")
        fi
    done <<< "$vms"

    if [ ${#running_vms[@]} -eq 0 ]; then
        log "Aucune VM à arrêter"
        return
    fi

    while [ $elapsed -lt $max_wait ]
    do
        still_running=()
        for vm in "${running_vms[@]}"
        do
            if virsh -c qemu:///system domstate "$vm" | grep -q running
            then
                still_running+=("$vm")
            fi
        done

        if [ ${#still_running[@]} -eq 0 ]; then
            log "Toutes les VMs sont arrêtées"
            return
        fi

        log "En attente du shutdown de : ${still_running[*]} (${elapsed}s/${max_wait}s)"
        sleep $interval
        elapsed=$((elapsed+interval))
        running_vms=("${still_running[@]}")
    done

    for vm in "${running_vms[@]}"
    do
        log "$vm n'a pas répondu au shutdown après ${max_wait}s, destroy forcé"
        virsh -c qemu:///system destroy "$vm"
    done
}



start_vm () {
    virsh -c qemu:///system list --all --name | while read -r vm
    do
        [ -z "$vm" ] && continue
        if virsh -c qemu:///system domstate "$vm" | grep -q "shut off"
        then
            log "Lancement de $vm"
            virsh -c qemu:///system start "$vm"
            while virsh -c qemu:///system domstate "$vm" | grep -q "shut off"
            do
                log "$vm en train de start..."
                sleep 2
            done
            log "$vm start"
        fi
    done
}



manage_flag () {
    case "$1" in
    CREATE)
        if [ ! -f "$2" ]
        then
            touch "$2"
            log "Création du flag $2"
        fi
        ;;
    REMOVE)
        if [ -f "$2" ]
        then
            rm -f "$2"
            log "Suppression du flag $2"
        fi
        ;;
    esac
}



online () {
    i=0
    while :
    do
        status_ups1=$(upsc UPS1 ups.status 2>/dev/null)
        runtime_ups1=$(upsc UPS1 battery.runtime 2>/dev/null)

        status_ups2=$(upsc UPS2 ups.status 2>/dev/null)
        runtime_ups2=$(upsc UPS2 battery.runtime 2>/dev/null)

        # Si l'un des deux repasse sur batterie pendant l'attente de recharge, on cède la main
        if [[ "$status_ups1" == *OB* || "$status_ups2" == *OB* ]]
        then
            log "Retour sur batterie détecté pendant l'attente de recharge, on cède la main"
            log "PID : $$ --  fin  -> $UPSNAME"
            exit 0
        fi

        if [[ ! -f "$FLAG_VM_SHUTDOWN" ]]
        then
            log "VMs déjà en marche, rien à faire"
            log "PID : $$ --  fin  -> $UPSNAME"
            exit 0
        fi

        # UPS1 rechargé
        if [[ -n $runtime_ups1 && $runtime_ups1 -gt $THRESHOLD_RESTARTVM ]]
        then
            manage_flag "REMOVE" "$FLAG_UPS1_LOWBATT"
        fi

        # UPS2 rechargé
        if [[ -n $runtime_ups2 && $runtime_ups2 -gt $THRESHOLD_RESTARTVM ]]
        then
            manage_flag "REMOVE" "$FLAG_UPS2_LOWBATT"
        fi

        # 2 UPS avec assez de batterie
        if [[ -n $runtime_ups1 && $runtime_ups1 -gt $THRESHOLD_RESTARTVM && -n $runtime_ups2 && $runtime_ups2 -gt $THRESHOLD_RESTARTVM ]]
        then
            log "État stable, les deux UPS ont assez de batterie"
            log "Lancement des VMs"
            manage_flag "REMOVE" "$FLAG_VM_SHUTDOWN"
            start_vm
            log "PID : $$ --  fin  -> $UPSNAME"
            exit 0
        fi

        if (( i >= 60 ))
        then
            i=0
            log "En attente de batterie suffisante pour lancer les VMs"
            log "UPS1 state : $status_ups1 | runtime : $runtime_ups1"
            log "UPS2 state : $status_ups2 | runtime : $runtime_ups2"
        fi
        ((++i))
        sleep 2
    done
}



monitore_onbatt () {
    i=0
    while :
    do
        status_ups1=$(upsc UPS1 ups.status 2>/dev/null)
        runtime_ups1=$(upsc UPS1 battery.runtime 2>/dev/null)

        status_ups2=$(upsc UPS2 ups.status 2>/dev/null)
        runtime_ups2=$(upsc UPS2 battery.runtime 2>/dev/null)

        # Si l'un des deux est revenu OL, on cède la main
        if [[ "$status_ups1" == *OL* || "$status_ups2" == *OL* ]]
        then
            log "Un des UPS est de retour en ligne"
            log "PID : $$ --  fin  -> $UPSNAME"
            exit 0
        fi

        # État réel confirmé en direct, pas de déduction par flag
        if [[ "$status_ups1" != *OB* && "$status_ups2" != *OB* ]]
        then
            log "Un seul UPS OB, rien à faire pour l'instant"
            log "PID : $$ --  fin  -> $UPSNAME"
            exit 0
        fi

        # UPS1 en low batt
        if [[ -n $runtime_ups1 && $runtime_ups1 -lt $THRESHOLD_LOWBATT ]]
        then
            manage_flag "CREATE" "$FLAG_UPS1_LOWBATT"
        fi

        # UPS2 en low batt
        if [[ -n $runtime_ups2 && $runtime_ups2 -lt $THRESHOLD_LOWBATT ]]
        then
            manage_flag "CREATE" "$FLAG_UPS2_LOWBATT"
        fi

        # 2 UPS en low batt
        if [[ -n $runtime_ups1 && $runtime_ups1 -lt $THRESHOLD_LOWBATT && -n $runtime_ups2 && $runtime_ups2 -lt $THRESHOLD_LOWBATT ]]
        then
            log "État critique, les deux UPS sont en Low Battery"
            log "Arrêt des VMs"
            manage_flag "CREATE" "$FLAG_VM_SHUTDOWN"
            stop_vm
            log "PID : $$ --  fin  -> $UPSNAME"
            exit 0
        fi

        if (( i >= 60 ))
        then
            i=0
            log "UPS1 state : $status_ups1 | runtime : $runtime_ups1"
            log "UPS2 state : $status_ups2 | runtime : $runtime_ups2"
        fi
        ((++i))
        sleep 2
    done
}



log "PID : $$ -- début -> $UPSNAME"
exec 200>"$LOCK_FILE"
flock -w 200 200 || { log "Verrou non obtenu pour $UPSNAME après 200s, exécution ignorée"; log "PID : $$ --  fin  -> $UPSNAME"; exit 0; }

case "$NOTIFYTYPE" in
    ONLINE)
        echo "$UPSNAME est passé en ONLINE"
        log "$UPSNAME est passé en ONLINE"
        online
        ;;
    ONBATT)
        echo "$UPSNAME est passé en BATTERY"
        log "$UPSNAME est passé en BATTERY"
        monitore_onbatt
        ;;
esac