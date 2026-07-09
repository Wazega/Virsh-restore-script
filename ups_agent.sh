#!/bin/bash

LOG_FILE=/var/log/ups_monitor.log
THRESHOLD_LOWBATT=3200
THRESHOLD_RESTARTVM=4000

LOCK_FILE="/tmp/ups_agent.lock"
FLAG_1UPS_OB="/tmp/1UPS_OB"
FLAG_1UPS_OL="/tmp/1UPS_OL"
FLAG_UPS1_LOWBATT="/tmp/UPS1_LOWBATT"
FLAG_UPS2_LOWBATT="/tmp/UPS2_LOWBATT"
FLAG_VM_SHUTDOWN="/tmp/VM_SHUTDOWN"



log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" >> "$LOG_FILE"
}



stop_vm () {
    local vms running_vms=()
    local max_wait=180   # 3 minutes en secondes
    local interval=5     # fréquence de vérification
    local elapsed=0

    vms=$(virsh -c qemu:///system list --all --name)

    # 1. Envoi du shutdown à toutes les VMs démarrées, en parallèle
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

    # 2. Attente que toutes les VMs s'arrêtent, jusqu'à max_wait secondes
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

    # 3. Destroy des VMs encore en cours après le délai
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

        # Vérifie que la VM est démarrée
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


        # 1 UPS ONLINE - 2e ups en train de passer OL
        if [[ -f "$FLAG_1UPS_OB" && -f "$FLAG_1UPS_OL" ]]
        then
            log "State : 2 UPS OL"
            manage_flag "REMOVE" "$FLAG_1UPS_OB"
            manage_flag "REMOVE" "$FLAG_1UPS_OL"

        # 1 UPS OB - 2e ups en train de passer OL
        elif [[ -f "$FLAG_1UPS_OB" && ! -f "$FLAG_1UPS_OL" ]]
        then
            log "State : 1 UPS OL | 1 UPS OB"
            manage_flag "CREATE" "$FLAG_1UPS_OL"
            log "PID : $$ --  fin  -> $UPSNAME"
            exit 0
        fi


        if [[ ! -f "$FLAG_VM_SHUTDOWN" ]]
        then
            log "VM déjà en marche, rien à faire"
            log "PID : $$ --  fin  -> $UPSNAME"
            exit 0
        fi

        # UPS1 en enough batt
        if [[ -n $runtime_ups1 && $runtime_ups1 -gt $THRESHOLD_RESTARTVM ]]
        then
            manage_flag "REMOVE" "$FLAG_UPS1_LOWBATT" 
        fi

        # UPS2 en low batt
        if [[ -n $runtime_ups2 && $runtime_ups2 -gt $THRESHOLD_RESTARTVM ]]
        then
            manage_flag "REMOVE" "$FLAG_UPS2_LOWBATT" 
        fi

        # 2 UPS avec assez de batterie 
        if [[ -n $runtime_ups1 && $runtime_ups1 -gt $THRESHOLD_RESTARTVM && -n $runtime_ups2 && $runtime_ups2 -gt $THRESHOLD_RESTARTVM ]]
        then
            log "État stable les deux UPS ont assez de batterie"
            log "Lancemenet des VMs"
            manage_flag "REMOVE" "$FLAG_VM_SHUTDOWN"
            start_vm
            log "PID : $$ --  fin  -> $UPSNAME"
            exit 0
        fi
        
        if (( $i >= 60 ))
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
        
        # TMP
        log "UPS1 : $status_ups1 - $runtime_ups1"
        log "UPS2 : $status_ups2 - $runtime_ups2"

        if [[ -f "$FLAG_1UPS_OL" ]]
        then
            manage_flag "REMOVE" "$FLAG_1UPS_OL"
        fi

        # 1 UPS ONLINE - 2e ups en train de passer OB
        if [[ -f "$FLAG_1UPS_OB" ]]
        then
            log "State : 2 UPS OB"

        # 1 UPS OL - 2e ups en train de passer OB
        else
            log "State : 1 UPS OL | 1 UPS OB"
            manage_flag "CREATE" "$FLAG_1UPS_OB"
            log "PID : $$ --  fin  -> $UPSNAME"
            exit 0
        fi

        if [[ ( -n $status_ups1 && $status_ups1 == *OL* ) || ( -n $status_ups2 && $status_ups2 == *OL* ) ]]
        then
            log "Un des UPS est de retour en ligne"
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
            log "État critique les deux UPS sont en Low Battery"
            log "Arrêt des VMs"
            manage_flag "CREATE" "$FLAG_VM_SHUTDOWN"
            stop_vm
            log "PID : $$ --  fin  -> $UPSNAME"
            exit 0
        fi

        if (( $i >= 60 ))
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
# Mise en place d'un verrou pour éviter duplication
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
        # check_flag
        monitore_onbatt
        ;;
esac