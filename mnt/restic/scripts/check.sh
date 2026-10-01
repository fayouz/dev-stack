#!/usr/bin/env bash
set -euo pipefail

trap '/scripts/hc_ping.sh restic-check fail; /scripts/notify.sh "[restic] Dépôt corrompu" "restic check a échoué. Voir : docker logs restic"' ERR

echo "=== Vérification du dépôt du $(date '+%F %T') ==="
/scripts/hc_ping.sh restic-check start
restic check
/scripts/hc_ping.sh restic-check
