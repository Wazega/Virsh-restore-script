#!/bin/bash

set -euo pipefail

# Backup vers le NAS1 pour Influx, puis SQL

LOG_FILE="/home/corsica/log_test_Gabin.log"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" >> "$LOG_FILE"
}

log "lancement des backup...."

log "NAS1 mount on /mnt/nas1"
mount -t nfs 10.100.50.1:/volume1/SCADA1 /mnt/nas1

log "Backup de Influx"


DIR="/mnt/nas1/VM-Influx"

log "Création du repo"
if [ -z "$(ls -A "$DIR")" ]
then
    newest=$(date +"%Y-%m-%d")
    mkdir -p "$DIR/$newest_backup"
else
    newest=$(ls "$DIR" | sort | tail -n 1)
fi

log "Lancement de la backup pour Influx"
# virtnbdbackup -d VM-Influx -l full -o "$DIR_LOCAL/$newest" --compress >> log_test_Gabin.log 2>&1
log "Fin de la backup pour Influx"

log "Lancement de la backup pour SQL"
# virtnbdbackup -d VM-SQL -l full -o "$DIR_LOCAL/$newest" --compress >> log_test_Gabin.log 2>&1
log "Fin de la backup pour SQL"


umount /mnt/nas1
log "umount fait"

