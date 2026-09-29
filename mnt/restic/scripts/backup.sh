#!/usr/bin/env bash
set -euo pipefail

on_error() {
    /scripts/status.sh error "Échec à la ligne $1"
    /scripts/notify.sh "[restic] Échec de la sauvegarde" \
        "La sauvegarde a échoué à la ligne $1. Voir : docker logs restic"
}
trap 'on_error $LINENO' ERR

echo "=== Sauvegarde du $(date '+%F %T') ==="

echo "--- MariaDB (dump)"
mariadb-dump -h mariadb -uroot -p"${MARIADB_ROOT_PASSWORD}" --skip-ssl \
    --all-databases --single-transaction --routines --events --triggers \
    | restic backup --stdin --stdin-filename mariadb-all.sql --tag mariadb

echo "--- Fichiers (Portainer, exports Oracle)"
restic backup /source/portainer /source/oracle-dumps --tag files

echo "--- Rétention"
restic forget --prune --keep-daily 7 --keep-weekly 4 --keep-monthly 6

/scripts/status.sh ok
echo "=== Sauvegarde terminée ==="
