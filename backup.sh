#!/bin/bash

set -euo pipefail

vm_to_backup="$1"
backup_mode="$2"

DIR_LOCAL="/data/local_backup/$vm_to_backup"

if [ -z "$(ls -A "$DIR_LOCAL")" ]
then
    newest=$(date +"%Y-%m-%d-%H-%M-%S")
    mkdir -p "$DIR_LOCAL/$newest_backup"
else
    newest=$(ls "$DIR_LOCAL" | sort | tail -n 1)
fi


virtnbdbackup -d "$vm_to_backup" -l "$2" -o "$DIR_LOCAL/$newest" --compress

# mount le nas1

# copier vers le nas1

# umount le nas1

# mount le nas2
# copier vers le nas2
# umount le nas2
