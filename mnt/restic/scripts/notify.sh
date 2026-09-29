#!/usr/bin/env bash
# Usage: notify.sh "<sujet>" "<message>" — envoie un mail à Mailpit
set -uo pipefail

printf 'From: %s\nTo: %s\nSubject: %s\n\n%s\n' \
    "${BACKUP_MAIL_FROM}" "${BACKUP_MAIL_TO}" "$1" "$2" \
    | curl -sS --url smtp://mailer:1025 \
        --mail-from "${BACKUP_MAIL_FROM}" \
        --mail-rcpt "${BACKUP_MAIL_TO}" \
        --upload-file - \
    || echo "Envoi du mail impossible" >&2
