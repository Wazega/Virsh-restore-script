#!/bin/bash

set -euo pipefail


LOG_FILE="/var/log/backup.log"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" >> "$LOG_FILE"
}


log "NAS1 mount on /mnt/nas1"
if ! mountpoint -q /mnt/nas1
then
    mount -t nfs 10.100.50.1:/volume1/SCADA1 /mnt/nas1
fi

VM_LIST=(
    "VM-Influx"
    "VM-Panorama"
    "VM-SQL"
    "VM-Dev-Pano-SCADA"
)

ID_VM=0

for vm in "${VM_LIST[@]}"
do
    log "[$vm] : Procédure de la backup pour la VM $vm"

    DIR="/home/debian/tmp/$vm"
    mkdir -p "$DIR"


    bucket_id=$(( (ID_VM + $(date +%j)) / 7 ))
    log "[$vm] : Dossier de sauvegarder créer ou choisi : $bucket_id"

    log "[$vm] : Création du dossier si il n'existe pas"
    mkdir -p "$DIR/$bucket_id"

    log "[$vm] : Réalisation de la backup pour $vm"
    virtnbdbackup -d "$vm" -l auto -o "$DIR/$bucket_id" --compress >> "$LOG_FILE" 2>&1
    log "[$vm] : Backup fini pour cette $vm"



    log "[$vm] : Vérification du bon nombre de sauvegarde (3 sauvegardes maximun)"
    count=$(find "$DIR" -maxdepth 1 -mindepth 1 -type d | wc -l)
    if (( count >= 4 ))
    then
        oldest=$(find "$DIR" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' | sort | head -n1)

        log "[$vm] : Suppression du dossier le plus vieux pour ne garder que 3 semaines de sauvegardes"
        log "[$vm] : Suppression du dossier $oldest"
        rm -rf "${DIR:?}/${oldest:?}"
    fi

    log "[$vm] : Fin de la procédure de la backup pour la VM $vm"
    ID_VM=$(( ID_VM + 1 ))

done


log "Fin des backups pour la journée"


if mountpoint -q /mnt/nas1
then
    umount /mnt/nas1
fi
log "Dossier /mnt/nas1 à été umount"

log "Fin du script pour la journée"