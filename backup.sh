#!/bin/bash

set -euo pipefail

LOG_FILE="/var/log/backup.log"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" >> "$LOG_FILE"
}

if [ "$(date +%u)" -eq 4 ]
then
    log "Réalisation d'une backup FULL"
    mode="full"
else
    mode="inc"
fi


log "NAS1 mount on /mnt/nas1"
if ! mountpoint -q /mnt/nas1
then
    mount -t nfs 10.100.50.1:/volume1/SCADA1 /mnt/nas1
fi


# readarray -t VM_LIST < <(virsh list --all --name | grep -v '^$')
VM_LIST=("VM-Backup")

for vm in "${VM_LIST[@]}"
do
    log "Procédure de la backup pour la VM $vm"

    DIR="/mnt/nas1/$vm"

    # Vérifier si le dossier est déjà créer, sinon le créer
    mkdir -p "$DIR"

    

    log "Création du dossier de sauvegarde si il  n'est pas initialisé"
    if [ "$mode" = "full" ]
    then
        log "Création d'un nouveau dossier pour la backup full"
        newest=$(date +"%Y-%m-%d")
        mkdir -p "$DIR/$newest"
    else
        if [ -z "$(ls -A "$DIR")" ]
        then
            newest=$(date +"%Y-%m-%d")
            mkdir -p "$DIR/$newest"
        else
            newest=$(ls "$DIR" | sort | tail -n 1)
        fi
    fi

    log "Dossier de sauvegarder créer ou choisi : $newest"

    log "Réalisation de la backup pour $vm"
    virtnbdbackup -d "$vm" -l "$mode" -o "$DIR/$newest" --compress >> "$LOG_FILE" 2>&1
    log "Backup fini pour cette $vm"

    date_of_the_day=$(date +"%Y-%m-%d")
    if [ "$newest" != "$date_of_the_day" ]
    then
        log "Changement de la date pour le dossier"
        mv "$newest" "$date_of_the_day"
    fi


    if [ "$mode" = "full" ]
    then
        log "Vérification du bon nombre de sauvegarde (3 sauvegardes maximun)"
        count=$(find "$DIR" -maxdepth 1 -mindepth 1 -type d | wc -l)
        if (( count >= 4 ))
        then
            oldest=$(find "$DIR" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' | sort | head -n1)

            log "Suppression du dossier le plus vieux pour ne garder que 3 semaines de sauvegardes"
            log "Suppression du dossier $oldest"
            rm -rf "$DIR/$oldest"
        fi
    fi

    log "Fin de la procédure de la backup pour la VM $vm"

done

log "Fin des backups pour la journée"


if mountpoint -q /mnt/nas1
then
    umount /mnt/nas1
fi
log "Dossier /mnt/nas1 à été umount"

log "Fin du script pour la journée"


