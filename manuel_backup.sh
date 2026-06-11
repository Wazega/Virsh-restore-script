#!/bin/bash
set -euo pipefail

# ========================
# NAS disponibles
# ========================
NAS_OPTIONS=(
  "NAS1|10.100.50.1|/volume1/SCADA1|/mnt/nas1"
  "NAS2|10.100.50.11|/volume1/SCADA2|/mnt/nas2"
)

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $*"
}

# ========================
# Choix NAS avec gum
# ========================
NAS_CHOICE=$(printf "%s\n" "${NAS_OPTIONS[@]}" \
  | gum choose --header="Choisis le NAS de backup")

IFS="|" read -r NAS_NAME NAS_IP NAS_REMOTE NAS_MOUNT <<< "$NAS_CHOICE"

log "NAS choisi: $NAS_NAME ($NAS_IP)"

# ========================
# Mount NAS si besoin
# ========================
log "Mount check $NAS_MOUNT"

if ! mountpoint -q "$NAS_MOUNT"; then
  sudo mkdir -p "$NAS_MOUNT"
  sudo mount -t nfs "$NAS_IP:$NAS_REMOTE" "$NAS_MOUNT"
fi

# ========================
# Liste VM disponible sur l'host
# ========================
source /etc/backup/vm-list.conf

HOSTNAME=$(hostname)

if [[ -z "${VM_MAP[$HOSTNAME]+x}" ]]; then
  echo "Hostname inconnu: $HOSTNAME"
  exit 1
fi

IFS=' ' read -r -a VM_LIST <<< "${VM_MAP[$HOSTNAME]}"



# ========================
# Choix VM(s)
# ========================
SELECTED_VMS=$(printf "%s\n" $VM_LIST \
  | gum choose --no-limit --header="Choisis les VM à sauvegarder")

if [[ -z "$SELECTED_VMS" ]]; then
  echo "Aucune VM sélectionnée"
  exit 1
fi

# ========================
# Backup
# ========================
ID_VM=0

for vm in $SELECTED_VMS; do
  log "[$vm] Début backup"

  DIR="$NAS_MOUNT/$vm"
  mkdir -p "$DIR"

  bucket_id=$(( (ID_VM + $(date +%j)) / 7 ))
  mkdir -p "$DIR/$bucket_id"

  log "[$vm] Backup dans $DIR/$bucket_id"

  virtnbdbackup -d "$vm" -l auto -o "$DIR/$bucket_id" --compress >> "$LOG_FILE" 2>&1

  log "[$vm] Backup terminé"

  # rotation (3 dossiers max)
  count=$(find "$DIR" -maxdepth 1 -mindepth 1 -type d | wc -l)

  if (( count >= 4 )); then
    oldest=$(find "$DIR" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' | sort | head -n1)

    log "[$vm] Suppression ancien backup $oldest"
    rm -rf "$DIR/$oldest"
  fi

  ID_VM=$((ID_VM + 1))
done

# ========================
# Unmount NAS
# ========================
if mountpoint -q "$NAS_MOUNT"; then
  sudo umount "$NAS_MOUNT"
fi

log "Fin des backups"