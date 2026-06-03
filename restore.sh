#!/bin/bash

set -euo pipefail

echo "===================="
echo "Restauration d'une backup"
echo "===================="
echo " "


echo "Choix de la VM à restaurer:"
echo "--------------------"
i=1
vm_list=()

while read -r vm
do
    # virsh peut renvoyer des lignes vides → on les ignore
    [[ -z "$vm" ]] && continue

    vm_list[$i]="$vm"
    echo "$i) $vm"
    ((i++))
done < <(virsh list --all --name)
read -p "Choix de la VM: " number_vm_choice
vm_chose="${vm_list[$number_vm_choice]}"


# A ajouter le VM chose dans le file
DIR="/data/tmp_SCADA1/$vm_chose"

files=()
i=1
echo ""
echo "Choix de la semaine à restorer: "
echo "--------------------"

for file in "$DIR"/*
do
  file=$(basename "$file")
  files[$i]="$file"
  echo "$i. $file"
  ((i++))
done

read -p "Choisis un numéro : " choix

selected_file="${files[$choix]}"

echo ""
echo "Selection de la semaine $selected_file"
echo ""

BACKUP_DIR="$DIR/$selected_file"
CHECKPOINT_DIR="$BACKUP_DIR/checkpoints"

echo "$CHECKPOINT_DIR"
echo "$BACKUP_DIR"

i=1

backup=()

echo "Choissisez le jour de la restauration :"
echo "--------------------"

for file in "$CHECKPOINT_DIR"/*
do
  [ -e "$file" ] || continue

  mod_date=$(stat -c "%y" "$file" | cut -d'.' -f1)
  name=$(basename "${file%.xml}")

  echo "$i) $mod_date - $name"

  backup[$i]="$name"

  ((i++))
done
read -p "Choisis un backup : " backup_choice

echo ""
echo "Vous avez choisit : ${backup[$backup_choice]}"


# Récupération du nom de la VM
cpt_file="$(find "$BACKUP_DIR" -maxdepth 1 -type f -name '*.cpt' -printf '%f\n')"
vm_name="${cpt_file%.cpt}"


# Récupération du path de stockage des fichier qcow2
mapfile -t qcow2_files < <(
  virsh domblklist "$vm_name" --details | awk '$4 ~ /\.qcow2$/ {print $4}'
)
if [[ ${#qcow2_files[@]} -eq 0 ]]; then
  echo "Aucun fichier qcow2 trouvé"
  exit 1
fi

echo "$qcow2_files"


# Stopper/Supprimer la VM actuelle pour permettre la restauration
echo ""
echo "Arrêt de l'ancienne VM: "
echo "--------------------"

virsh destroy "$vm_name" || true
virsh undefine "$vm_name" --remove-all-storage --delete-snapshots --checkpoints-metadata --nvram || true




# On prend le parent du premier fichier (en théorie il est commun c'est on respecte les installations)
DIR_QCOW2=$(dirname "${qcow2_files[0]}")
echo "$DIR_QCOW2"

# Suppression des fichiers qcow2
for file in "${qcow2_files[@]}"; do
  echo "Suppression : $file"
  rm -f "$file"
done


# Restaurer la VM
echo ""
echo "Restauration de la VM depuis la backup ${backup[$backup_choice]}: "
echo "--------------------"
virtnbdrestore -i "$BACKUP_DIR" -o "$DIR_QCOW2" --until "${backup[$backup_choice]}"


# Relancer la VM grâce au xml
echo ""
echo "Lancement de la VM restaurer: "
echo "--------------------"
xml_file="$(find "$DIR_QCOW2" -maxdepth 1 -type f -name '*.xml' | head -n 1)"
echo "$xml_file"
virsh define "$xml_file"
virsh start "$vm_name"


rm -f "$xml_file"

echo ""
echo "Restauration terminée avec succès !"