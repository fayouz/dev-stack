#!/usr/bin/env bash
# Usage: status.sh <ok|error|none> [message]
# Écrit l'état des sauvegardes lu par le dashboard (mnt/restic/status/status.json)
set -uo pipefail

restic snapshots --json --latest 10 > /tmp/snapshots.json 2>/dev/null || echo '[]' > /tmp/snapshots.json

jq -n --arg result "$1" --arg message "${2:-}" --arg at "$(date -Iseconds)" \
    --slurpfile snapshots /tmp/snapshots.json \
    '{lastRun: {at: $at, result: $result, message: $message}, snapshots: $snapshots[0]}' \
    > /status/status.json.tmp \
    && mv /status/status.json.tmp /status/status.json
