#!/usr/bin/env bash
set -euo pipefail

path="docker-compose.yaml"
if [[ ! -f "$path" ]]; then
  echo "File not found: $path" >&2
  exit 1
fi

content="$(cat "$path")"

fail=0
check() {
  local desc="$1" pattern="$2"
  if ! printf '%s' "$content" | grep -Eq "$pattern"; then
    echo "Missing: $desc ($pattern)" >&2
    fail=$((fail+1))
  fi
}

check "Compose version 3.9" "version:[[:space:]]*['\"]?3\.9['\"]?"
check "services section" "^services:[[:space:]]*$"
check "nginx-proxy service" "^[[:space:]]+nginx-proxy:[[:space:]]*$"
check "nginx-proxy image" "image:[[:space:]]*jwilder/nginx-proxy"
check "nginx-proxy port 80" "\"?80:80\"?"
check "nginx-proxy port 443" "\"?443:443\"?"
check "portainer service" "^[[:space:]]+portainer:[[:space:]]*$"
check "portainer image" "image:[[:space:]]*portainer/portainer-ce:latest"
check "portainer port 9000" "\"?9000:9000\"?"

# Check top-level volumes contains portainer_data
if ! awk 'BEGIN{insec=0;found=0} /^[^[:space:]]/{insec = ($0 ~ /^volumes:/)} insec==1 && $0 ~ /^[[:space:]]*portainer_data:[[:space:]]*$/ {found=1} END{exit(found?0:1)}' "$path"; then
  echo "Missing: named volume portainer_data in top-level volumes" >&2
  fail=$((fail+1))
fi

# Check networks.bme_network.external == true
if ! awk 'BEGIN{innet=0;inbme=0;ext=0} /^[^[:space:]]/{innet = ($0 ~ /^networks:/); inbme=0} innet==1 && $0 ~ /^[[:space:]]*bme_network:[[:space:]]*$/ {inbme=1} innet==1 && inbme==1 && $0 ~ /^[[:space:]]*external:[[:space:]]*true[[:space:]]*$/ {ext=1} END{exit(ext?0:1)}' "$path"; then
  echo "Missing: networks.bme_network.external=true" >&2
  fail=$((fail+1))
fi

if [[ $fail -gt 0 ]]; then
  echo "docker-compose.yaml failed $fail checks" >&2
  exit 1
fi

echo "docker-compose.yaml structure validated."
