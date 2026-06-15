# Fonctionnement des scripts

Ce README décrit l'utilisation et le fonctionnement des scripts `backup.sh`, `manual_backup.sh` et `restore.sh`.

L'ensemble des scripts est situé dans le répertoire `/home/corsicasole/script`.

Le fichier de configuration définissant l'ordre de sauvegarde des machines virtuelles (VM) se trouve à l'emplacement suivant : `/etc/backup/vm-list.conf`.

## Sommaire

1. [Script `backup.sh`](#script-backupsh)

   * [Utilisation](#utilisation)
   * [Fonctionnement](#fonctionnement)
2. [Script `manual_backup.sh`](#script-manual_backupsh)

   * [Utilisation](#utilisation-1)
3. [Script `restore.sh`](#script-restoresh)

   * [Utilisation](#utilisation-2)

---

## Script `backup.sh`

### Utilisation

Ce script est exécuté automatiquement par le service `cron` et n'est pas destiné à être lancé manuellement par un utilisateur.

Il permet d'effectuer les sauvegardes de l'ensemble des machines virtuelles.

Les journaux (logs) sont disponibles dans les fichiers suivants :

* Logs du script de sauvegarde : `/var/log/backup.log`
* Logs du service Cron : `/var/log/cron-backup.log`

### Fonctionnement

Ce script est exécuté quotidiennement à des horaires différents selon le serveur :

| Serveur | Heure des sauvegardes |
| ------- | --------------------- |
| ADM     | 17h00                 |
| SRV-01  | 01h00                 |
| SRV-02  | 09h00                 |

Aucune intervention utilisateur n'est nécessaire.

---

## Script `manual_backup.sh`

Ce script permet de réaliser la sauvegarde d'une machine virtuelle sélectionnée par l'utilisateur.

> **Attention :** En dehors de la période de sauvegarde quotidienne, ce script peut être utilisé à tout moment.

### Utilisation

> **Important :** L'exécution de ce script nécessite les privilèges `root`.

```bash
./manual_backup.sh
```

Le script est interactif et vous guide à travers les différentes options disponibles.

Une fois les paramètres sélectionnés, la sauvegarde est lancée automatiquement.

---

## Script `restore.sh`

Ce script permet de restaurer une machine virtuelle à partir d'une sauvegarde existante.

> **Attention :** Toutes les données de la machine virtuelle à remplacer seront supprimées de manière définitive avant la restauration.

### Utilisation

> **Important :** L'exécution de ce script nécessite les privilèges `root`.

```bash
./restore.sh
```

Le script est interactif et vous guide à travers les différentes étapes de restauration.

À la fin de l'opération, la machine virtuelle restaurée est automatiquement démarrée et opérationnelle.
