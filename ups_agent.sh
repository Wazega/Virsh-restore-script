#!/bin/bash

LOG_FILE=/var/log/ups_monitor.log
FLAG="/tmp/UPS_LB"


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
    virsh -c qemu:///system list --all --name | while read -r vm
    do
        [ -z "$vm" ] && continue

        # Vérifie que la VM est démarrée
        if virsh -c qemu:///system domstate "$vm" | grep -q running
        then
            i=0
            log "Arrêt de $vm"
            virsh -c qemu:///system shutdown "$vm"

            while virsh -c qemu:///system domstate "$vm" | grep -q running
            do
                log "$vm en train de shutdown..."
                sleep 2
                i=$((i+1))
                if [[ $i == 10 ]]
                then
                    virsh -c qemu:///system destroy "$vm"
                fi
            done

            log "$vm arrêtée"
        fi
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

    while :
        do
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
        sleep 2
    done
}



online () {
    while :
    do
        status_ups1=$(upsc UPS1 ups.status 2>/dev/null)
        charge_ups1=$(upsc UPS1 battery.runtime 2>/dev/null)

        status_ups2=$(upsc UPS2 ups.status 2>/dev/null)
        charge_ups2=$(upsc UPS2 battery.runtime 2>/dev/null)

        # UPS 1 -> Online | UPS 1 -> -
        # UPS 2 -> -      | UPS 2 -> Online
        if [[ "$status_ups1" != *LB* && "$status_ups2" != *LB* ]]; then
            if [ -f "/tmp/UPS_LB" ]
            then
                log "Les UPS ne sont plus en Low Battery"
                log "Suppression du flag"
                rm -rf "$FLAG"
                exit 1
            fi
        fi

        # UPS 1 -> ONLINE
        # UPS 2 -> ONLINE
        if [[ ( "$status_ups1" == *OL*  && "$charge_ups1" -gt 2400 ) || ( "$status_ups2" == *OL* && "$charge_ups2" -gt 2400 ) ]]
        then
            log "Au moins un UPS est ONLINE avec une charge > 40 %, redémarrage des VMs"
            log "Redémarrage des VMs"
            start_vm
            exit 1
        fi

        sleep 2
    done
}



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