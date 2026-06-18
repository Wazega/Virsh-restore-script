#!/bin/bash

-set euo pipefail

# =========================
# VéRIFICATION LANCEMENT EN ROOT
# =========================
if [ "$EUID" -ne 0 ]; then
    echo "Ce script doit être exécuté en tant que root." >&2
    exit 1
fi


echo "===================="
echo "Restauration d'une backup"
echo "===================="
echo ""

# =========================
# CHOIX DU NAS
# =========================
echo "Choix du NAS à monter:"
echo "--------------------"
nas_chose=$(gum choose "nas1" "nas2") || exit 1
echo "NAS choisi: $nas_chose"
echo ""

# =========================
# DéTERMINER L'IP
# =========================
if [[ "$nas_chose" == "nas1" ]]; then
    ip="10.100.50.1"
else
    ip="10.100.50.11"
fi

# =========================
# RéCUPéRER LES EXPORTS NFS
# =========================
mapfile -t folders < <(showmount -e "$ip" | awk 'NR>1 {print $1}')

# =========================
# CHOIX DU DOSSIER
# =========================
echo "Choix du dossier à monter:"
echo "--------------------"
folder_chose=$(printf "%s\n" "${folders[@]}" | gum choose) || exit 1
echo "Dossier choisi: $folder_chose"
echo ""

# =========================
# MONTER LE VOLUME
# =========================
REMOTE_DIR="$folder_chose"
DIR="/mnt/$nas_chose"

if ! mountpoint -q "$DIR"
then
    mount -t nfs "$ip":"$REMOTE_DIR" "$DIR"
fi


# =========================
# CHOIX DE LA VM
# =========================
echo "Choix de la VM à restaurer:"
echo "--------------------"
vm_chose=$(find "$DIR" -maxdepth 1 -type d -printf "%f\n" | grep -v '^#recycle$' | grep -v "$nas_chose" | gum choose) || exit 1
echo "VM choisie : $vm_chose"
echo ""


weeks_display=()
weeks_paths=()
bucket_name=()

# =========================
# CONSTRUCTION DES SEMAINES A PARTIR DES BUCKETS
# =========================
for f in "$DIR/$vm_chose"/*; do
    checkpoint_dir="$f/checkpoints"
    [ -d "$checkpoint_dir" ] || continue

    initial_file=$(find "$checkpoint_dir" -type f -printf '%T@ %p\n' | sort -n | head -n 1 | cut -d' ' -f2-)
    last_file=$(find "$checkpoint_dir" -type f -printf '%T@ %p\n' | sort -nr | head -n 1 | cut -d' ' -f2-)

    [ -z "$initial_file" ] && continue

    initial_modif=$(stat -c %y "$initial_file" | cut -d' ' -f1)
    last_modif=$(stat -c %y "$last_file" | cut -d' ' -f1)

    weeks_display+=("$initial_modif → $last_modif")
    weeks_paths+=("$checkpoint_dir")
    bucket_name+=("$f")
done

# =========================
# CHOIX DE LA SEMAINE
# =========================
echo "Choix de la période à restaurer:"
echo "--------------------"

bucket_choices=()

for i in "${!weeks_display[@]}"; do
    bucket_choices+=("$(basename "${bucket_name[$i]}") : ${weeks_display[$i]}")
done

bucket_chose=$(printf "%s\n" "${bucket_choices[@]}" | gum choose) || exit 1

selected_dir=""

for i in "${!bucket_choices[@]}"
do
    if [[ "${bucket_choices[$i]}" == "$bucket_chose" ]]; then
        selected_dir="${weeks_paths[$i]}"
        break
    fi
done

# echo "$selected_dir"

# =========================
# CONSTRUCTION DES FICHIERS AVEC DATE
# =========================
files_display=()
files_paths=()

for file in "$selected_dir"/*; do
    [ -f "$file" ] || continue

    file_date=$(stat -c %y "$file" | cut -d' ' -f1)
    file_name=$(basename "$file")

    files_display+=("$file_date | $file_name")
    files_paths+=("$file")
done

# =========================
# CHOIX DU FICHIER
# =========================
echo "Choix du jour à restaurer:"
echo "--------------------"
file_choice=$(printf "%s\n" "${files_display[@]}" | gum choose) || exit 1
echo "Jour choisi: $file_choice"
echo ""


selected_file=""

for i in "${!files_display[@]}"; do
    [[ "${files_display[$i]}" == "$file_choice" ]] && selected_file="${files_paths[$i]}"
done

# =========================
# CONFIRMATION DES CHOIX
# =========================
stat_selected_file=$(stat -c %y "$selected_file" | cut -d' ' -f1)
tab=$'\t'

echo "Confirmation des paramètres:"
echo "--------------------"
echo "$tab NAS    : $tab $nas_chose"
echo "$tab FOLDER : $tab $folder_chose"
echo "$tab VM     : $tab $vm_chose"
echo "$tab File   : $tab $selected_file"
echo "$tab Date   : $tab $stat_selected_file"
echo ""
gum confirm "Confirmer les paramètres et commencer la restauration ?" && echo "Lancement de la restauration" || { echo "Procédure annulée"; exit 1; }


# =========================
# RECUPERATION DES PATH POUR LES FICHIER QCOW2
# =========================
mapfile -t qcow2_files < <(
  virsh domblklist "$vm_chose" --details | awk '$4 ~ /\.qcow2$/ {print $4}'
)


# =========================
# CHOIX DU PATH SI LA VM N'EST PLUS SUR LA MACHINE
# =========================
if [[ ${#qcow2_files[@]} -eq 0 ]]
then
    echo "VM non existante sur cette machine"
    gum confirm "Voulez-vous ajouter la VM $vm_chose sur cette machine ?" || exit 1

    echo "Chemin par défaut proposé pour le disque de la VM : $default_qcow2"
    echo ""

    if gum confirm "Voulez-vous utiliser ce chemin ? ($default_qcow2)"
    then
        qcow2_files=("$default_qcow2")
    else
        user_qcow2_path=$(gum input --placeholder "Entrez un chemin" --prompt "Path > ")

        # Vérification simple
        if [ -z "$user_qcow2_path" ]
        then
            echo "Aucun chemin fourni."
            exit 1
        fi

        # vérification que le chemin existe, sinon le créer
        if mkdir -p "$user_qcow2_path"
        then
            echo "Répertoire valide"
            qcow2_files=("$user_qcow2_path")
        else
            echo "Erreur lors de la création du répertoire" >&2
            exit 1
        fi
    fi
fi



# =========================
# SUPPRIMER VM ACTUELLE POUR PERMETTRE RESTAURATION
# =========================
echo ""
echo "Arrêt de l'ancienne VM: "
echo "--------------------"

virsh destroy "$vm_chose" || true
virsh undefine "$vm_chose" --remove-all-storage --delete-snapshots --checkpoints-metadata --nvram || true


# =========================
# SUPPRESSION DES QCOW2 DE LA VM
# =========================
DIR_QCOW2=$(dirname "${qcow2_files[0]}")
echo "$DIR_QCOW2"

for file in "${qcow2_files[@]}"; do
  echo "Suppression : $file"
  rm -f "$file"
done


# =========================
# RESTAURER LA VM
# =========================
echo ""
echo "Restauration de la VM depuis la backup $selected_file: "
echo "--------------------"
BACKUP_DIR=$(echo "$selected_file" | sed 's|/checkpoints/.*||')
right_path_until=$(basename "$selected_file" .xml)
virtnbdrestore -i "$BACKUP_DIR" -o "$DIR_QCOW2" --until "$right_path_until"


# =========================
# RELANCER LA VM
# =========================
echo ""
echo "Lancement de la VM restaurer: "
echo "--------------------"
xml_file="$(find "$DIR_QCOW2" -maxdepth 1 -type f -name '*.xml' | head -n 1)"
echo "$xml_file"
virsh define "$xml_file"
virsh start "$vm_chose"

# =========================
# SUPPRIMER LE XML TEMPORAIRE
# =========================
rm -f "$xml_file"


# =========================
# CHANGER LE NOM DU BUCKET
# =========================
bucket_dir="${selected_dir%/checkpoints}"
mv "$bucket_dir" "${bucket_dir}_old" 

# =========================
# UMOUNT LE NFS
# =========================
if mountpoint -q "$DIR"
then
    umount "$DIR"
fi

echo ""
echo "Restauration terminée avec succès !"