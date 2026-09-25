#!/bin/sh
set -eu

repository="${RESTIC_REPOSITORY:-/repository}"
interval="${RESTIC_INTERVAL:-86400}"

if ! restic snapshots --repo "$repository" >/dev/null 2>&1; then
  echo "Initializing Restic repository at $repository"
  restic init --repo "$repository"
fi

backup() {
  echo "Starting Restic backup"
  restic backup --repo "$repository" \
    /sources/mariadb \
    /sources/oracle \
    /sources/portainer
}

backup

if [ "${BACKUP_ONCE:-0}" = "1" ]; then
  exit 0
fi

while :; do
  sleep "$interval"
  backup
done
