"""Synchronisation continue des fichiers HTTP JetBrains (.http) des projets vers Hoppscotch.

Sens unique : les fichiers sont la référence. Chaque projet de PROJECTS_DIR qui
contient des .http a son workspace Hoppscotch (une équipe du nom du projet) : ses
répertoires y deviennent les collections racines, ses environnements JetBrains les
environnements de l'équipe. Tout est recréé à chaque modification, mais seuls les
collections et environnements créés par ce service (repérés par un marqueur) sont
modifiés ou supprimés ; une équipe n'est jamais supprimée.

Authentification : session Hoppscotch de HOPP_EMAIL, ouverte par lien magique lu
dans Mailpit (stack de dev locale), puis renouvelée avec le refresh token.
"""
from __future__ import annotations

import hashlib
import http.cookiejar
import json
import logging
import os
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any

from inotify_simple import INotify, flags

from httpfile import SKIP_DIRS, convert_project

PROJECTS_DIR = os.environ.get("PROJECTS_DIR", "/projects")
HOPP_BACKEND = os.environ.get("HOPP_BACKEND", "http://hoppscotch:80/backend").rstrip("/")
HOPP_EMAIL = os.environ["HOPP_EMAIL"]
MAILPIT_URL = os.environ.get("MAILPIT_URL", "http://mailer:8025").rstrip("/")
STATE_DIR = os.environ.get("STATE_DIR", "/state")
EXCLUDE = {p.strip() for p in os.environ.get("EXCLUDE_PROJECTS", "").split(",") if p.strip()}
DEBOUNCE = float(os.environ.get("DEBOUNCE_SECONDS", "2"))
FULL_RESCAN = float(os.environ.get("FULL_RESCAN_SECONDS", "600"))
MARKER = "hoppscotch-sync:"

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s", datefmt="%H:%M:%S")
log = logging.getLogger("hoppscotch-sync")


class HoppscotchError(Exception):
    pass


class Hoppscotch:
    """Client minimal de l'API Hoppscotch (REST d'authentification + GraphQL)."""

    def __init__(self) -> None:
        os.makedirs(STATE_DIR, exist_ok=True)
        self.cookies = http.cookiejar.LWPCookieJar(os.path.join(STATE_DIR, "cookies.txt"))
        if os.path.exists(self.cookies.filename):
            self.cookies.load(ignore_discard=True, ignore_expires=True)
        self.opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(self.cookies))

    def _request(self, method: str, url: str, body: Any = None, timeout: int = 30) -> tuple[int, Any]:
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(url, data=data, method=method, headers={"Content-Type": "application/json"})
        try:
            with self.opener.open(req, timeout=timeout) as res:
                raw = res.read()
                status = res.status
        except urllib.error.HTTPError as err:
            raw, status = err.read(), err.code
        self.cookies.save(ignore_discard=True, ignore_expires=True)
        try:
            return status, json.loads(raw) if raw else None
        except json.JSONDecodeError:
            return status, raw.decode(errors="replace")

    # --- authentification -------------------------------------------------
    def _login_magic_link(self) -> None:
        log.info("Connexion à Hoppscotch par lien magique (%s)", HOPP_EMAIL)
        before = {m["ID"] for m in self._magic_messages()}
        status, res = self._request("POST", f"{HOPP_BACKEND}/v1/auth/signin?origin=web", {"email": HOPP_EMAIL})
        if status >= 300 or not isinstance(res, dict) or "deviceIdentifier" not in res:
            raise HoppscotchError(f"signin refusé ({status}) : {res}")
        token = self._wait_magic_token(before)
        status, res = self._request("POST", f"{HOPP_BACKEND}/v1/auth/verify",
                                    {"token": token, "deviceIdentifier": res["deviceIdentifier"]})
        if status >= 300:
            raise HoppscotchError(f"vérification du lien refusée ({status}) : {res}")
        log.info("Session Hoppscotch ouverte")

    def _magic_messages(self) -> list[dict]:
        query = urllib.parse.quote(f'to:{HOPP_EMAIL} subject:"Sign in to Hoppscotch"')
        with urllib.request.urlopen(f"{MAILPIT_URL}/api/v1/search?query={query}&limit=20", timeout=10) as res:
            return json.load(res).get("messages", [])

    def _wait_magic_token(self, before: set[str]) -> str:
        """Lit dans Mailpit le lien magique arrivé après la demande, puis supprime le message."""
        for _ in range(30):
            for msg in self._magic_messages():
                if msg["ID"] in before:
                    continue
                with urllib.request.urlopen(f"{MAILPIT_URL}/api/v1/message/{msg['ID']}", timeout=10) as res:
                    detail = json.load(res)
                match = re.search(r"token=([A-Za-z0-9_.-]+)", detail.get("HTML", "") + detail.get("Text", ""))
                if match:
                    req = urllib.request.Request(f"{MAILPIT_URL}/api/v1/messages", method="DELETE",
                                                 data=json.dumps({"IDs": [msg["ID"]]}).encode(),
                                                 headers={"Content-Type": "application/json"})
                    urllib.request.urlopen(req, timeout=10).close()
                    return match.group(1)
            time.sleep(1)
        raise HoppscotchError("lien magique introuvable dans Mailpit")

    def _refresh(self) -> bool:
        status, _ = self._request("GET", f"{HOPP_BACKEND}/v1/auth/refresh")
        return status < 300

    def graphql(self, query: str, variables: dict | None = None) -> dict:
        for attempt in range(3):
            status, res = self._request("POST", f"{HOPP_BACKEND}/graphql", {"query": query, "variables": variables or {}})
            if status >= 500 or not isinstance(res, dict):
                raise HoppscotchError(f"GraphQL indisponible ({status})")
            errors = res.get("errors") or []
            if not errors:
                return res["data"]
            if any("auth/" in str(e.get("message")) or e.get("extensions", {}).get("code") == "FORBIDDEN" for e in errors):
                if attempt == 0 and self._refresh():
                    continue
                self._login_magic_link()
                continue
            raise HoppscotchError("; ".join(str(e.get("message")) for e in errors))
        raise HoppscotchError("authentification impossible")

    # --- opérations ---------------------------------------------------------
    def root_collections(self) -> list[dict]:
        found, cursor = [], None
        while True:
            data = self.graphql(
                "query($cursor: ID) { rootRESTUserCollections(cursor: $cursor, take: 100) { id title data } }",
                {"cursor": cursor},
            )["rootRESTUserCollections"]
            found += data
            if len(data) < 100:
                return found
            cursor = data[-1]["id"]

    def environments(self) -> list[dict]:
        return self.graphql("{ me { environments { id name isGlobal } } }")["me"]["environments"]

    def my_teams(self) -> list[dict]:
        found, cursor = [], None
        while True:
            data = self.graphql("query($cursor: ID) { myTeams(cursor: $cursor) { id name myRole } }", {"cursor": cursor})["myTeams"]
            found += data
            if len(data) < 10:
                return found
            cursor = data[-1]["id"]

    def team_root_collections(self, team_id: str) -> list[dict]:
        found, cursor = [], None
        while True:
            data = self.graphql(
                "query($team: ID!, $cursor: ID) { rootCollectionsOfTeam(teamID: $team, cursor: $cursor, take: 100) { id title data } }",
                {"team": team_id, "cursor": cursor},
            )["rootCollectionsOfTeam"]
            found += data
            if len(data) < 100:
                return found
            cursor = data[-1]["id"]

    def team_environments(self, team_id: str) -> list[dict]:
        return self.graphql("query($team: ID!) { team(teamID: $team) { teamEnvironments { id name } } }",
                            {"team": team_id})["team"]["teamEnvironments"]


def marker_of(collection: dict) -> str | None:
    data = collection.get("data")
    try:
        description = (json.loads(data) if isinstance(data, str) else data or {}).get("description") or ""
    except (json.JSONDecodeError, AttributeError):
        return None
    match = re.match(re.escape(MARKER) + r"(\S+)", description)
    return match.group(1) if match else None


class Syncer:
    def __init__(self) -> None:
        self.hopp = Hoppscotch()
        self.state_path = os.path.join(STATE_DIR, "state.json")
        self.state: dict = json.load(open(self.state_path)) if os.path.exists(self.state_path) else {}

    def save_state(self) -> None:
        tmp = self.state_path + ".tmp"
        json.dump(self.state, open(tmp, "w"), indent=1)
        os.replace(tmp, self.state_path)

    def projects(self) -> list[str]:
        return sorted(
            p for p in os.listdir(PROJECTS_DIR)
            if p not in EXCLUDE and not p.startswith(".") and os.path.isdir(os.path.join(PROJECTS_DIR, p))
        )

    def team_for(self, project: str) -> str:
        """Équipe (workspace) du projet : celle enregistrée, sinon une du même nom, sinon créée."""
        teams = {t["id"]: t for t in self.hopp.my_teams()}
        known = self.state.get(project, {}).get("team_id")
        if known in teams:
            return known
        same_name = [t for t in teams.values() if t["name"] == project and t["myRole"] == "OWNER"]
        if same_name:
            return same_name[0]["id"]
        created = self.hopp.graphql("mutation($name: String!) { createTeam(name: $name) { id } }", {"name": project})
        log.info("[%s] workspace créé", project)
        return created["createTeam"]["id"]

    def sync_project(self, project: str, force: bool = False) -> None:
        collection, environments, stats = convert_project(os.path.join(PROJECTS_DIR, project), f"{MARKER}{project}")
        for error in stats["errors"]:
            log.warning("[%s] %s", project, error)

        # Empreinte sans les identifiants aléatoires (_ref_id) : rien à faire si rien n'a changé
        fingerprint = hashlib.sha256(
            re.sub(r'"_ref_id": "[^"]+"', "", json.dumps([collection, environments], sort_keys=True)).encode()
        ).hexdigest()
        previous = self.state.get(project, {})
        if not force and previous.get("fingerprint") == fingerprint:
            return
        if not collection and not previous.get("team_id"):
            return

        team_id = previous.get("team_id") if not collection else self.team_for(project)

        # Collections : les répertoires du projet deviennent les collections racines du workspace
        for coll in self.hopp.team_root_collections(team_id):
            if marker_of(coll) == project:
                self.hopp.graphql("mutation($id: ID!) { deleteCollection(collectionID: $id) }", {"id": coll["id"]})
        if collection:
            roots = []
            for folder in collection["folders"]:
                props = json.loads(folder["data"])
                props["description"] = f"{MARKER}{project}\n{props.get('description') or ''}".strip()
                roots.append({**folder, "description": props["description"], "data": props})
            self.hopp.graphql(
                "mutation($team: ID!, $json: String!) { importCollectionsFromJSON(teamID: $team, jsonString: $json) }",
                {"team": team_id, "json": json.dumps(roots)},
            )

        # Environnements du workspace : mise à jour par nom, création, suppression des disparus
        existing = {e["name"]: e["id"] for e in self.hopp.team_environments(team_id)}
        managed = set(previous.get("environments", []))
        wanted = {}
        for env in environments:
            variables = json.dumps(env["variables"])
            if env["name"] in existing:
                self.hopp.graphql(
                    "mutation($id: ID!, $name: String!, $vars: String!) "
                    "{ updateTeamEnvironment(id: $id, name: $name, variables: $vars) { id } }",
                    {"id": existing[env["name"]], "name": env["name"], "vars": variables},
                )
                wanted[env["name"]] = existing[env["name"]]
            else:
                created = self.hopp.graphql(
                    "mutation($team: ID!, $name: String!, $vars: String!) "
                    "{ createTeamEnvironment(teamID: $team, name: $name, variables: $vars) { id } }",
                    {"team": team_id, "name": env["name"], "vars": variables},
                )
                wanted[env["name"]] = created["createTeamEnvironment"]["id"]
        for name in managed - set(wanted):
            if name in existing:
                self.hopp.graphql("mutation($id: ID!) { deleteTeamEnvironment(id: $id) }", {"id": existing[name]})

        if collection:
            log.info("[%s] synchronisé : %d fichiers, %d requêtes (%d à vérifier), %d environnements",
                     project, stats["files"], stats["requests"], stats["warnings"], len(environments))
        else:
            log.info("[%s] plus de fichiers .http : collections et environnements retirés (workspace conservé)", project)
        self.state[project] = {"team_id": team_id, "fingerprint": fingerprint,
                               "environments": sorted(wanted), "synced_at": time.time()}
        self.save_state()

    def migrate_from_personal_workspace(self) -> None:
        """Retire ce que l'ancienne version avait créé dans l'espace personnel."""
        if self.state.get("_mode") == "teams":
            return
        removed = 0
        for coll in self.hopp.root_collections():
            if marker_of(coll):
                self.hopp.graphql("mutation($id: ID!) { deleteUserCollection(userCollectionID: $id) }", {"id": coll["id"]})
                removed += 1
        old_envs = {name for entry in self.state.values() if isinstance(entry, dict) for name in entry.get("environments", [])}
        for env in self.hopp.environments():
            if not env["isGlobal"] and env["name"] in old_envs:
                self.hopp.graphql("mutation($id: ID!) { deleteUserEnvironment(id: $id) }", {"id": env["id"]})
                removed += 1
        self.state = {"_mode": "teams"}
        self.save_state()
        log.info("Migration vers un workspace par projet : %d éléments retirés de l'espace personnel", removed)

    def sync_all(self, force: bool = False) -> None:
        known = {p for p in self.state if not p.startswith("_")}
        for project in self.projects():
            self._safe_sync(project, force)
            known.discard(project)
        for gone in known:  # projet supprimé ou exclu
            self._safe_sync(gone, force)

    def _safe_sync(self, project: str, force: bool = False) -> bool:
        try:
            self.sync_project(project, force)
            return True
        except (HoppscotchError, urllib.error.URLError, OSError) as exc:
            log.error("[%s] échec de la synchronisation : %s", project, exc)
            return False


class Watcher:
    """Surveillance inotify récursive, sans les dossiers ignorés (vendor, node_modules…)."""

    MASK = flags.CREATE | flags.MODIFY | flags.MOVED_TO | flags.MOVED_FROM | flags.DELETE | flags.CLOSE_WRITE

    def __init__(self) -> None:
        self.inotify = INotify()
        self.paths: dict[int, str] = {}

    def add_tree(self, root: str) -> None:
        """Surveille root puis ses sous-dossiers. La surveillance est posée AVANT de lister
        le contenu : un sous-dossier créé entre-temps produit un événement au lieu d'être
        manqué (mkdir -p projet/http)."""
        try:
            self.paths[self.inotify.add_watch(root, self.MASK)] = root
            entries = list(os.scandir(root))
        except OSError:
            return
        for entry in entries:
            if entry.is_dir(follow_symlinks=False) and entry.name not in SKIP_DIRS and not entry.name.startswith("."):
                self.add_tree(entry.path)

    def changed_projects(self, timeout_ms: int) -> set[str]:
        projects = set()
        for event in self.inotify.read(timeout=timeout_ms):
            parent = self.paths.get(event.wd)
            if parent is None:
                continue
            full = os.path.join(parent, event.name)
            if event.mask & flags.ISDIR and event.mask & (flags.CREATE | flags.MOVED_TO):
                if event.name not in SKIP_DIRS and not event.name.startswith("."):
                    self.add_tree(full)
            rel = os.path.relpath(full, PROJECTS_DIR)
            project = rel.split(os.sep, 1)[0]
            if project in EXCLUDE or project.startswith("."):
                continue
            # .http, fichiers d'environnement, et fichiers inclus (corps < ./x.json, scripts > ./x.js)
            if event.mask & flags.ISDIR or re.search(r"\.(http|rest|json|js)$", event.name):
                projects.add(project)
        return projects


def main() -> None:
    syncer = Syncer()
    log.info("Projets surveillés dans %s (exclus : %s)", PROJECTS_DIR, ", ".join(sorted(EXCLUDE)) or "aucun")

    # Attend que Hoppscotch réponde, puis première synchronisation complète
    while True:
        try:
            syncer.hopp.graphql("{ me { email } }")
            break
        except (HoppscotchError, urllib.error.URLError, OSError) as exc:
            log.warning("Hoppscotch pas encore prêt (%s), nouvel essai dans 10 s", exc)
            time.sleep(10)
    syncer.migrate_from_personal_workspace()
    syncer.sync_all()

    watcher = Watcher()
    watcher.add_tree(PROJECTS_DIR)
    log.info("Surveillance active : %d dossiers", len(watcher.paths))

    pending: set[str] = set()
    last_full = time.time()
    while True:
        changed = watcher.changed_projects(timeout_ms=int(DEBOUNCE * 1000))
        if changed:
            pending |= changed
            continue  # attend que les enregistrements successifs se calment
        for project in sorted(pending):
            if not syncer._safe_sync(project):
                continue  # réessaiera au prochain parcours complet
            pending.discard(project)
        pending.clear()
        if time.time() - last_full > FULL_RESCAN:
            watcher.add_tree(PROJECTS_DIR)  # repose les surveillances éventuellement manquées
            syncer.sync_all()
            last_full = time.time()


if __name__ == "__main__":
    main()
