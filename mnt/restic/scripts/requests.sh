#!/usr/bin/env bash
# Lance les sauvegardes demandées depuis le dashboard (fichier /requests/backup)
while sleep 5; do
    if [ -f /requests/backup ]; then
        rm -f /requests/backup
        echo "Sauvegarde demandée depuis le dashboard"
        /scripts/backup.sh || true
    fi
done
