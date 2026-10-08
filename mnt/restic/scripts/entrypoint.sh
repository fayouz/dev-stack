#!/usr/bin/env bash
set -euo pipefail

if [ -z "${RESTIC_PASSWORD:-}" ]; then
    echo "RESTIC_PASSWORD est vide : définis-le dans .env" >&2
    exit 1
fi

# Initialise le dépôt au premier démarrage seulement
if ! restic cat config >/dev/null 2>&1; then
    echo "Initialisation du dépôt restic dans ${RESTIC_REPOSITORY}"
    restic init
fi

# État initial pour le dashboard, conservé s'il existe déjà
[ -f /status/status.json ] || /scripts/status.sh none
rm -f /status/running

# Demandes déposées par le dashboard (bouton « Sauvegarder maintenant »), qui
# tourne sous un autre utilisateur : le dossier doit lui être accessible en écriture
mkdir -p /requests && chmod 1777 /requests
/scripts/requests.sh > /proc/1/fd/1 2>&1 &

# Les sorties des tâches vont dans les logs du conteneur (docker logs restic)
cat > /etc/crontabs/root <<EOF
${RESTIC_CRON} /scripts/backup.sh > /proc/1/fd/1 2>&1
${RESTIC_CHECK_CRON} /scripts/check.sh > /proc/1/fd/1 2>&1
EOF

echo "Planning : backup '${RESTIC_CRON}', check '${RESTIC_CHECK_CRON}'"
exec crond -f -l 8
