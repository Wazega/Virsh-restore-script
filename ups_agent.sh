#!/bin/bash

LOG_FILE=/var/log/ups_monitor.log
FLAG="/tmp/UPS_LB"
LOCK_FILE="/tmp/ups_agent.lock"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" >> "$LOG_FILE"
}



check_flag () {
    if [ -f "/tmp/UPS_LB" ]
    then
        log "$UPSNAME est en Low Battery, flag déjà créer"
        log "Vérification de l'état de la battery des 2 UPS"
    else
        log "$UPSNAME est en Low Battery, création du flag"
        touch "$FLAG"
        exit 1
    fi
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



low_batterie () {

    status_ups1=$(upsc UPS1 ups.status 2>/dev/null)
    charge_ups1=$(upsc UPS1 battery.runtime 2>/dev/null)

    status_ups2=$(upsc UPS2 ups.status 2>/dev/null)
    charge_ups2=$(upsc UPS2 battery.runtime 2>/dev/null)

    # UPS 1 -> LOWBATT
    # UPS 2 -> LOWBATT
    if [[ "$status_ups1" == *LB* && "$status_ups2" == *LB* ]]
    then
        log "État critique les deux UPS sont en Low Battery"
        log "Arrêt des VMs"
        stop_vm
        exit 1
    fi

    # UPS 1 -> -        |  UPS 1 -> LOWBATT
    # UPS 2 -> LOWBATT  |  UPS 2 -> -
    if [[ ! ( "$status_ups1" == *LB* && "$status_ups2" == *LB* ) ]]; then
        log "Seul un des deux UPS est en Low Battery"
        log "Fin du script, mais conservation du flag"
        exit 1
    fi

}



online () {
    while :
    do
        status_ups1=$(upsc UPS1 ups.status 2>/dev/null)
        charge_ups1=$(upsc UPS1 battery.runtime 2>/dev/null)

        status_ups2=$(upsc UPS2 ups.status 2>/dev/null)
        charge_ups2=$(upsc UPS2 battery.runtime 2>/dev/null)

        # UPS 1 -> LB     | UPS 1 -> -
        # UPS 2 -> -      | UPS 2 -> LB
        if [[ "$status_ups1" == *LB* || "$status_ups2" == *LB* ]]; then
            log "Au moins un UPS est en Low Battery, flag conservé, pas de redémarrage"
            [ -f "$FLAG" ] || touch "$FLAG"
            exit 1
        fi

        if [ -f "$FLAG" ]; then
            log "Les deux UPS ne sont plus en Low Battery, suppression du flag"
            rm -f "$FLAG"
        fi

        # UPS 1 -> ONLINE && runtime > 2400s
        # UPS 2 -> ONLINE && runtime > 2400s
        if [[ -n "$charge_ups1" && -n "$charge_ups2" && "$charge_ups1" -gt 4000 && "$charge_ups2" -gt 4000 ]]
        then
            log "Les deux UPS sont rechargés (>2400s de runtime), redémarrage des VMs"
            start_vm
            exit 1
        fi

        log "En attente de charge suffisante (UPS1: ${charge_ups1:-?}s, UPS2: ${charge_ups2:-?}s)"
        sleep 2
    done
}



# Mise en place d'un verrou pour éviter duplication
exec 200>"$LOCK_FILE"
flock -w 200 200 || { log "Verrou non obtenu pour $UPSNAME après 200s, exécution ignorée"; exit 1; }



case "$NOTIFYTYPE" in
    ONLINE)
        echo "$UPSNAME est passé en ONLINE"
        online
        ;;
    LOWBATT)
        echo "$UPSNAME est passé en LOW BATTERY"
        check_flag
        low_batterie
        ;;
esac