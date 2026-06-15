#!/bin/bash

echo "Arrêt des VMs..."

virsh list --all --name | while read -r vm
do
    [ -z "$vm" ] && continue

    echo ""
    # Vérifie que la VM est démarrée
    if virsh domstate "$vm" | grep -q running
    then
        echo "Arrêt de $vm"
        virsh shutdown "$vm"

        while virsh domstate "$vm" | grep -q running
        do
            echo "$vm en train de shutdown..."
            sleep 2
        done

        echo "$vm arrêtée"
    fi
done

echo ""
echo "Arrêt du serveur dans 5s:"

for i in $(seq 5 -1 0)
do
    echo "$i..."
    sleep 1
done

echo "Arrêt du serveur"
shutdown -h now