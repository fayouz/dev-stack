#!/usr/bin/env bash
# Configure le daemon Docker pour tirer les images Docker Hub via le cache local
# (service registry-cache). À lancer avec sudo : make registry-mirror
#
# - sauvegarde /etc/docker/daemon.json et conserve tous les réglages existants ;
# - ajoute "registry-mirrors" et "live-restore" (les conteneurs survivent à un
#   redémarrage du daemon, ce qui évite de couper brutalement les bases Oracle) ;
# - valide la configuration avant de l'appliquer ;
# - recharge le daemon à chaud (SIGHUP) : aucun conteneur n'est redémarré.
set -euo pipefail

CONFIG=/etc/docker/daemon.json
MIRROR=http://127.0.0.1:5000

if [ "$(id -u)" -ne 0 ]; then
    echo "À lancer avec sudo : sudo $0" >&2
    exit 1
fi
if ! curl -sf --noproxy '*' "$MIRROR/v2/" >/dev/null; then
    echo "Le cache $MIRROR ne répond pas : démarrer d'abord le service registry-cache (make up)." >&2
    exit 1
fi

CANDIDATE=$(mktemp)
trap 'rm -f "$CANDIDATE"' EXIT

python3 - "$CONFIG" "$MIRROR" "$CANDIDATE" <<'PY'
import json, os, sys
config_path, mirror, out = sys.argv[1:]
config = json.load(open(config_path)) if os.path.exists(config_path) else {}
mirrors = config.get("registry-mirrors", [])
if mirror not in mirrors:
    mirrors.insert(0, mirror)
config["registry-mirrors"] = mirrors
config["live-restore"] = True
json.dump(config, open(out, "w"), indent=2)
PY

if ! dockerd --validate --config-file "$CANDIDATE" >/dev/null; then
    echo "Configuration invalide, rien n'a été modifié." >&2
    exit 1
fi

if [ -f "$CONFIG" ]; then
    BACKUP="$CONFIG.$(date +%Y%m%d-%H%M%S).bak"
    cp -p "$CONFIG" "$BACKUP"
    echo "Sauvegarde : $BACKUP"
fi
install -m 644 "$CANDIDATE" "$CONFIG"
systemctl reload docker

sleep 1
echo "Miroirs actifs : $(docker info --format '{{json .RegistryConfig.Mirrors}}')"
echo "Live restore   : $(docker info --format '{{.LiveRestoreEnabled}}')"
