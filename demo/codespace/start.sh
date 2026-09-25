#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE_FILE="$ROOT_DIR/docker-compose.traefik.yaml"
LOCAL_OVERRIDE="$ROOT_DIR/docker-compose.local.yaml"
PROJECT_NAME="docker-master"
ENV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$ENV_DIR/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  ENV_FILE="$ENV_DIR/.env.example"
fi

cd "$ROOT_DIR"

DOMAIN="$(sed -n 's/^DOMAIN=//p' "$ENV_FILE" | head -n 1 | tr -d '\r')"
SUBDOMAIN="$(sed -n 's/^SUBDOMAIN=//p' "$ENV_FILE" | head -n 1 | tr -d '\r')"

for network in bme_network bme_network_aux; do
  if ! docker network inspect "$network" >/dev/null 2>&1; then
    echo "Creating external network: $network"
    docker network create "$network" >/dev/null
  fi
done

echo "Validating Docker Compose configuration..."
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" -f "$LOCAL_OVERRIDE" config --quiet

echo "Starting the demo stack..."
docker compose --profile local --env-file "$ENV_FILE" -f "$COMPOSE_FILE" -f "$LOCAL_OVERRIDE" -p "$PROJECT_NAME" up -d

echo
echo "Demo stack started. Open one of these URLs:"
echo "  Traefik: http://local-traefik.${DOMAIN:-domain.com}"
echo "  Glance:  http://${SUBDOMAIN:-local}-glance.${DOMAIN:-domain.com}"
echo "  Grafana: http://${SUBDOMAIN:-local}-grafana.${DOMAIN:-domain.com}"
echo
echo "Useful checks:"
echo "  docker compose -f docker-compose.traefik.yaml -p $PROJECT_NAME ps"
echo "  make logs-grafana"
