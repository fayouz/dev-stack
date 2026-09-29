#!/usr/bin/env bash
set -euo pipefail

trap '/scripts/notify.sh "[restic] Dépôt corrompu" "restic check a échoué. Voir : docker logs restic"' ERR

echo "=== Vérification du dépôt du $(date '+%F %T') ==="
restic check
