#!/usr/bin/env bash
# Expose les projets de PROJECTS_DIR à Dockge sous forme de liens symboliques
# dans mnt/dockge/stacks. Usage : make dockge-sync
#
# Pourquoi des liens : Dockge n'accepte que des noms de stack en minuscules
# ([a-z0-9_-]) et associe une stack à son projet Compose en cours par le nom.
# Chaque lien porte donc le nom du projet Compose (clé `name:` du fichier, sinon
# le nom du dossier normalisé) et pointe vers le vrai dossier, qui reste intact.
# Quand deux dossiers déclarent le même projet (copies "develop"), le nom revient
# à celui qui tourne, sinon au plus court ; l'autre prend son nom de dossier.
#
# Idempotent : ne crée, ne remplace et ne supprime que des liens symboliques.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PROJECTS_DIR=${PROJECTS_DIR:-$(dirname "$ROOT")}
STACKS_DIR="$ROOT/mnt/dockge/stacks"
mkdir -p "$STACKS_DIR"

docker compose ls --all --format json > "$STACKS_DIR/.compose-ls.json" 2>/dev/null || echo '[]' > "$STACKS_DIR/.compose-ls.json"

python3 - "$PROJECTS_DIR" "$STACKS_DIR" "$(basename "$ROOT")" <<'PY'
import json, os, re, sys

projects_dir, stacks_dir, self_name = sys.argv[1:]
FILES = ["compose.yaml", "docker-compose.yaml", "docker-compose.yml", "compose.yml"]
running = json.load(open(os.path.join(stacks_dir, ".compose-ls.json")))
os.remove(os.path.join(stacks_dir, ".compose-ls.json"))

def normalize(name):
    return re.sub(r"[^a-z0-9_-]", "-", name.lower()).strip("-")

def project_name(folder, compose_file):
    match = re.search(r"(?m)^name:\s*[\"']?([^\"'\s]+)", open(compose_file).read())
    name = match.group(1) if match else None
    if name and "${" in name:  # name: ${VAR:-defaut}
        default = re.search(r"\$\{[A-Za-z_]+:-([^}]+)\}", name)
        name = default.group(1) if default else None
    return normalize(name or folder)

candidates = {}
for folder in sorted(os.listdir(projects_dir)):
    path = os.path.join(projects_dir, folder)
    if folder == self_name or not os.path.isdir(path):
        continue
    compose = next((os.path.join(path, f) for f in FILES if os.path.isfile(os.path.join(path, f))), None)
    if compose:
        is_running = any(f"{path}/" in p.get("ConfigFiles", "") for p in running)
        candidates.setdefault(project_name(folder, compose), []).append((not is_running, len(folder), folder))

wanted = {}
copies = []
for name, folders in candidates.items():
    folders.sort()
    wanted[name] = folders[0][2]
    copies += [folder for _, _, folder in folders[1:]]
# Les copies passent après tous les noms de projet, pour ne jamais en écraser un
for folder in sorted(copies):
    name, n = normalize(folder), 2
    while name in wanted:
        name, n = f"{normalize(folder)}-{n}", n + 1
    wanted[name] = folder

for entry in os.listdir(stacks_dir):
    link = os.path.join(stacks_dir, entry)
    if os.path.islink(link) and entry not in wanted:
        os.remove(link)
        print(f"  - {entry} (supprimé)")

for name, folder in sorted(wanted.items()):
    link, target = os.path.join(stacks_dir, name), os.path.join(projects_dir, folder)
    if os.path.islink(link) and os.readlink(link) == target:
        continue
    if os.path.exists(link) and not os.path.islink(link):
        print(f"  ! {name} : un vrai dossier existe déjà (stack créée dans Dockge), ignoré")
        continue
    if os.path.islink(link):
        os.remove(link)
    os.symlink(target, link)
    print(f"  + {name} -> {folder}")

print(f"{len(wanted)} projets exposés à Dockge dans {stacks_dir}")
PY
