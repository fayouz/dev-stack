#!/usr/bin/env bash
set -euo pipefail

mkdir -p /status
rm -f /status/running

# Demandes déposées par le dashboard (bouton « Analyser maintenant »), qui
# tourne sous un autre utilisateur : le dossier doit lui être accessible en écriture
mkdir -p /requests && chmod 1777 /requests
# Première analyse dès le démarrage
[ -f /status/vulnerabilities.json ] || touch /requests/scan
/scripts/requests.sh > /proc/1/fd/1 2>&1 &

# Les sorties des tâches vont dans les logs du conteneur (docker logs trivy)
echo "${TRIVY_CRON} /scripts/scan.sh > /proc/1/fd/1 2>&1" > /etc/crontabs/root

echo "Planning : analyse '${TRIVY_CRON}'"
exec crond -f -l 8
