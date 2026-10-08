#!/usr/bin/env bash
# Lance les analyses demandées depuis le dashboard (fichier /requests/scan)
while sleep 5; do
    if [ -f /requests/scan ]; then
        rm -f /requests/scan
        echo "Analyse demandée depuis le dashboard"
        /scripts/scan.sh || true
    fi
done
