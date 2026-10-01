#!/usr/bin/env bash
# Usage: hc_ping.sh <slug> [start|fail]
# Signale l'état d'une tâche à Healthchecks. Ne fait jamais échouer l'appelant :
# sans clé configurée ou si Healthchecks ne répond pas, on continue sans rien dire.
[ -n "${HEALTHCHECKS_PING_KEY:-}" ] || exit 0
suffix=${2:+/$2}
curl -fsS -m 10 --retry 3 -o /dev/null \
    "http://healthchecks:8000/ping/${HEALTHCHECKS_PING_KEY}/$1${suffix}" \
    || echo "Healthchecks injoignable (ping $1${suffix} ignoré)" >&2
exit 0
