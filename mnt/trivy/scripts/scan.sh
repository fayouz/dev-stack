#!/usr/bin/env bash
# Analyse les images des conteneurs en cours d'exécution (vulnérabilités connues
# des paquets système et des dépendances) et écrit le résumé lu par le dashboard
# dans /status/vulnerabilities.json. Les images sont lues via le proxy du socket,
# en lecture seule : rien n'est tiré ni modifié.
set -uo pipefail

# Une seule analyse à la fois (planning et demandes du dashboard)
exec 9>/tmp/scan.lock
if ! flock -n 9; then
    echo "Une analyse est déjà en cours"
    exit 0
fi
touch /status/running
trap 'rm -f /status/running' EXIT

echo "=== Analyse des vulnérabilités du $(date '+%F %T') ==="
trivy image --download-db-only --quiet || echo "Base de vulnérabilités non mise à jour, la précédente est utilisée"

if ! curl -sf "${DOCKER_HOST/tcp:/http:}/containers/json" > /tmp/containers.json; then
    echo "API Docker injoignable" >&2
    exit 1
fi
# Une entrée par image, avec les conteneurs qui l'utilisent
jq -c 'group_by(.Image) | map({image: .[0].Image, containers: map(.Names[0] | ltrimstr("/")) | sort}) | .[]' \
    /tmp/containers.json > /tmp/images.jsonl

# Vulnérabilités dédoublonnées (un paquet peut apparaître dans plusieurs couches)
SUMMARY='[.Results[]?.Vulnerabilities[]?] | unique_by(.VulnerabilityID + "|" + .PkgName) as $v
| $entry + {
    error: null,
    counts: (reduce $v[] as $x ({CRITICAL: 0, HIGH: 0, MEDIUM: 0, LOW: 0, UNKNOWN: 0}; .[$x.Severity] += 1)),
    fixable: ($v | map(select((.FixedVersion // "") != "")) | length),
    top: ($v | map(select(.Severity == "CRITICAL" or .Severity == "HIGH"))
        | sort_by(if .Severity == "CRITICAL" then 0 else 1 end, .PkgName)
        | .[:30]
        | map({id: .VulnerabilityID, severity: .Severity, pkg: .PkgName, installed: .InstalledVersion,
               fixed: (if (.FixedVersion // "") == "" then null else .FixedVersion end), title: (.Title // "")}))
  }'

: > /tmp/results.jsonl
while read -r entry; do
    image=$(jq -r .image <<< "$entry")
    echo "--- ${image}"
    if trivy image --image-src docker --scanners vuln --skip-db-update --quiet \
            --timeout 20m --format json --output /tmp/report.json "$image" 2> /tmp/error.txt; then
        jq -c --argjson entry "$entry" "$SUMMARY" /tmp/report.json >> /tmp/results.jsonl
    else
        cat /tmp/error.txt >&2
        jq -cn --argjson entry "$entry" --arg error "$(tail -c 300 /tmp/error.txt)" \
            '$entry + {error: $error, counts: {CRITICAL: 0, HIGH: 0, MEDIUM: 0, LOW: 0, UNKNOWN: 0}, fixable: 0, top: []}' \
            >> /tmp/results.jsonl
    fi
done < /tmp/images.jsonl

jq -s --arg at "$(date -Iseconds)" \
    '{scannedAt: $at, images: sort_by(-.counts.CRITICAL, -.counts.HIGH, .image)}' /tmp/results.jsonl \
    > /status/vulnerabilities.json.tmp \
    && mv /status/vulnerabilities.json.tmp /status/vulnerabilities.json
echo "=== Analyse terminée : $(wc -l < /tmp/results.jsonl) image(s) ==="
