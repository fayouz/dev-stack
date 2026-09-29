#!/usr/bin/env bash
# Restaure une base du dernier dump MariaDB dans une base jetable
# "restore_test", puis compare son nombre de tables avec la base d'origine.
set -euo pipefail

SRC=${1:-${MARIADB_DATABASE:-db_master}}
DB=restore_test
MYSQL=(mariadb -h mariadb -uroot -p"${MARIADB_ROOT_PASSWORD}" --skip-ssl)
count_tables() {
    "${MYSQL[@]}" -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$1'"
}

echo "--- Extraction du dernier dump"
restic dump latest --tag mariadb /mariadb-all.sql > /tmp/restore.sql
tail -n 1 /tmp/restore.sql | grep -q '^-- Dump completed' \
    || { echo "ÉCHEC : dump tronqué" >&2; exit 1; }
echo "Dump complet : $(wc -c < /tmp/restore.sql) octets"

echo "--- Import de la base ${SRC} dans ${DB}"
"${MYSQL[@]}" -e "DROP DATABASE IF EXISTS ${DB}; CREATE DATABASE ${DB};"
# Garde l'en-tête du dump puis la seule section de la base source
awk -v db="$SRC" '
    BEGIN { keep = 1 }
    /^-- Current Database: / { keep = ($0 ~ "`" db "`") }
    keep && !/^(CREATE DATABASE|USE )/ { print }
' /tmp/restore.sql | "${MYSQL[@]}" "${DB}"

EXPECTED=$(count_tables "${SRC}")
RESTORED=$(count_tables "${DB}")
"${MYSQL[@]}" -e "DROP DATABASE ${DB}"
rm -f /tmp/restore.sql

echo "Tables : ${RESTORED} restaurées / ${EXPECTED} attendues"
[ "${RESTORED}" -eq "${EXPECTED}" ] || { echo "ÉCHEC" >&2; exit 1; }
echo "Restauration OK"
