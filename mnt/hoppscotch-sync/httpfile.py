"""Conversion des fichiers HTTP JetBrains (.http + http-client*.env.json) vers Hoppscotch.

Produit, pour un projet :
- une collection Hoppscotch (format v12, requêtes v17) : un dossier par répertoire
  contenant des .http, puis un dossier par fichier, puis ses requêtes ;
- une liste d'environnements (un par environnement JetBrains et par fichier d'env).

Ce qui ne se traduit pas est conservé et signalé dans la description de la requête.
"""
from __future__ import annotations

import json
import os
import re
import secrets
from dataclasses import dataclass, field
from urllib.parse import unquote_plus

# Dossiers jamais parcourus : dépendances, builds, et .idea (historique PhpStorm
# des requêtes, qui contient de vrais jetons)
SKIP_DIRS = {
    "node_modules", "vendor", ".git", ".idea", "var", "cache", ".nuxt", ".output",
    "dist", "build", ".venv", "__pycache__", "storage",
}
METHODS = {"GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS", "TRACE", "CONNECT"}
BODY_TYPES = {
    "application/json", "application/ld+json", "application/hal+json", "application/vnd.api+json",
    "application/xml", "text/xml", "text/html", "text/plain",
}
# Variables dynamiques JetBrains -> variables prédéfinies Hoppscotch
DYNAMIC = {
    "$uuid": "$guid", "$random.uuid": "$guid",
    "$timestamp": "$timestamp", "$isoTimestamp": "$isoTimestamp",
    "$randomInt": "$randomInt", "$random.integer": "$randomInt",
}


def ref_id(prefix: str) -> str:
    return f"{prefix}_{secrets.token_hex(8)}"


def convert_vars(text: str) -> str:
    """{{var}} -> <<var>> (syntaxe Hoppscotch), variables dynamiques traduites."""
    def repl(match: re.Match) -> str:
        name = match.group(1).strip()
        return f"<<{DYNAMIC.get(name, name)}>>"
    return re.sub(r"\{\{\s*([^{}]+?)\s*\}\}", repl, text)


# Lecture d'un en-tête de réponse dans un script Hoppscotch
HEADER_JS = '(__RESPONSE__.headers.find(h => h.key.toLowerCase() === String({}).toLowerCase())?.value ?? "")'


def _rewrite_call(js: str, needle: str, build) -> str:
    """Réécrit chaque appel `needle(a, b)` en build(a, b), parenthèses et chaînes comprises."""
    out, pos = [], 0
    while (start := js.find(needle, pos)) != -1:
        out.append(js[pos:start])
        i, depth, comma, quote = start + len(needle), 1, None, None
        while i < len(js) and depth:
            ch = js[i]
            if quote:
                if ch == "\\":
                    i += 1
                elif ch == quote:
                    quote = None
            elif ch in "\"'`":
                quote = ch
            elif ch in "([{":
                depth += 1
            elif ch in ")]}":
                depth -= 1
            elif ch == "," and depth == 1 and comma is None:
                comma = i
            i += 1
        if depth or comma is None:  # appel mal formé ou à un seul argument : laissé tel quel
            out.append(js[start:i])
        else:
            first, second = js[start + len(needle):comma].strip(), js[comma + 1:i - 1].strip()
            out.append(build(first, second))
        pos = i
    out.append(js[pos:])
    return "".join(out)


def _assertion(cond: str, msg: str) -> str:
    """client.assert(cond, msg) -> pw.expect ; message gardé en commentaire s'il est une simple chaîne."""
    literal = re.fullmatch(r"\"([^\"*]*)\"|'([^'*]*)'", msg.strip())
    comment = f" /* {literal.group(1) or literal.group(2)} */" if literal else ""
    return f"pw.expect({cond}).toBe(true){comment}"


def convert_script(js: str) -> tuple[str, list[str]]:
    """Script de réponse JetBrains -> script post-requête Hoppscotch (API pw)."""
    notes = []
    out = _rewrite_call(js.strip("\n"), "client.global.set(", lambda k, v: f"pw.env.set({k}, String({v}))")
    # client.assert(condition, message) -> assertion Hoppscotch (le message reste en commentaire)
    out = _rewrite_call(out, "client.assert(", _assertion)
    out = re.sub(r"\bresponse\.contentType\.mimeType\b", HEADER_JS.format('"content-type"') + '.split(";")[0].trim()', out)
    out = re.sub(r"\bresponse\.headers\.valueOf\(\s*([^)]+?)\s*\)", lambda m: HEADER_JS.format(m.group(1)), out)
    out = out.replace("client.global.get(", "pw.env.get(")
    out = out.replace("client.test(", "pw.test(")
    out = out.replace("client.log(", "console.log(")
    out = re.sub(r"\bresponse\.", "pw.response.", out)
    out = out.replace("__RESPONSE__", "pw.response")
    if re.search(r"\bclient\.(?!global|test|log)|\brequest\.", out):
        notes.append("script de réponse partiellement traduit (API JetBrains non supportée) : à vérifier")
    return out.strip(), notes


@dataclass
class Request:
    name: str
    method: str
    url: str
    headers: list[tuple[str, str]] = field(default_factory=list)
    body: str | None = None
    script: str = ""
    pre_script: str = ""
    notes: list[str] = field(default_factory=list)


def parse_http_file(path: str) -> tuple[list[Request], set[str]]:
    """Analyse un fichier .http. Renvoie les requêtes et les variables écrites par les scripts."""
    text = open(path, encoding="utf-8", errors="replace").read().replace("\r\n", "\n")
    base_dir = os.path.dirname(path)
    requests, script_vars = [], set()
    file_vars: dict[str, str] = {}

    # Blocs séparés par les lignes "###" ; le texte après ### est le nom de la requête
    blocks: list[tuple[str, list[str]]] = [("", [])]
    for line in text.split("\n"):
        if line.startswith("###"):
            blocks.append((line[3:].strip(), []))
        else:
            blocks[-1][1].append(line)

    for title, lines in blocks:
        req = _parse_block(title, lines, base_dir, file_vars)
        if req:
            script_vars.update(re.findall(r"pw\.env\.set\(\s*[\"']([^\"']+)[\"']", req.script))
            requests.append(req)
    return requests, script_vars


def _parse_block(title: str, lines: list[str], base_dir: str, file_vars: dict[str, str]) -> Request | None:
    name = title
    i = 0
    # En-tête : commentaires, # @name, @variable = valeur
    while i < len(lines):
        line = lines[i].strip()
        if not line:
            i += 1
            continue
        if line.startswith(("#", "//")):
            tag = re.match(r"(?:#|//)\s*@name\s*[= ]\s*(.+)", line)
            if tag:
                name = tag.group(1).strip()
            i += 1
            continue
        var = re.match(r"@([A-Za-z_][\w.-]*)\s*=\s*(.*)", line)
        if var:
            file_vars[var.group(1)] = var.group(2)
            i += 1
            continue
        if line.startswith("< {%"):  # script avant requête
            i += 1
            continue
        break
    if i >= len(lines):
        return None

    # Ligne de requête : [MÉTHODE] URL [HTTP/x.y], suite éventuelle sur les lignes indentées
    parts = lines[i].strip().split()
    if parts and parts[0].upper() in METHODS:
        method, url_parts = parts[0].upper(), parts[1:]
    elif parts and re.match(r"(https?://|\{\{|/)", parts[0]):
        method, url_parts = "GET", parts
    else:
        return None
    if url_parts and re.match(r"HTTP/\d", url_parts[-1]):
        url_parts = url_parts[:-1]
    url = " ".join(url_parts)
    i += 1
    while i < len(lines) and lines[i][:1] in (" ", "\t") and lines[i].strip()[:1] in ("?", "&", "/"):
        url += lines[i].strip()
        i += 1
    req = Request(name=name or f"{method} {re.sub(r'^(https?://)?[^/]*', '', url) or url}", method=method, url=url)

    # En-têtes jusqu'à la première ligne vide
    while i < len(lines) and lines[i].strip():
        line = lines[i]
        if line.strip().startswith(("#", "//")):
            i += 1
            continue
        key, sep, value = line.partition(":")
        if sep:
            req.headers.append((key.strip(), value.strip()))
        i += 1

    # Corps, puis script de réponse (> {% ... %} ou > ./fichier.js) et référence de réponse (<> ...)
    body_lines, script_lines, in_script = [], [], False
    for line in lines[i:]:
        stripped = line.strip()
        if in_script:
            if stripped.endswith("%}"):
                script_lines.append(stripped[:-2])
                in_script = False
            else:
                script_lines.append(line)
            continue
        if stripped.startswith("> {%"):
            content = stripped[4:]
            if content.rstrip().endswith("%}"):
                script_lines.append(content.rstrip()[:-2])
            else:
                script_lines.append(content)
                in_script = True
            continue
        if re.match(r">\s*\S+\.js$", stripped):
            script_file = os.path.join(base_dir, stripped[1:].strip())
            if os.path.isfile(script_file):
                script_lines.append(open(script_file, encoding="utf-8", errors="replace").read())
            else:
                req.notes.append(f"script externe introuvable : {stripped[1:].strip()}")
            continue
        if stripped.startswith("<>"):
            continue
        if re.match(r"<\s*\S", stripped) and not stripped.startswith("<{") and not stripped.startswith("<<"):
            body_file = os.path.join(base_dir, stripped[1:].strip())
            if os.path.isfile(body_file):
                body_lines.append(open(body_file, encoding="utf-8", errors="replace").read())
                continue
            req.notes.append(f"corps lu depuis un fichier introuvable : {stripped[1:].strip()}")
            continue
        body_lines.append(line)

    body = "\n".join(body_lines).strip("\n")
    req.body = body if body.strip() else None
    if script_lines:
        req.script, notes = convert_script("\n".join(script_lines))
        req.notes += notes
    if file_vars:
        for key, value in file_vars.items():
            req.url = req.url.replace(f"{{{{{key}}}}}", value)
    return req


def _content_type(headers: list[tuple[str, str]]) -> tuple[str | None, dict[str, str]]:
    for key, value in headers:
        if key.lower() == "content-type":
            main, *params = [p.strip() for p in value.split(";")]
            opts = {}
            for p in params:
                k, _, v = p.partition("=")
                opts[k.strip().lower()] = v.strip().strip('"')
            return main.lower(), opts
    return None, {}


def _multipart(body: str, boundary: str, notes: list[str]) -> list[dict]:
    items = []
    for part in body.split(f"--{boundary}"):
        part = part.strip("\n")
        if not part or part.startswith("--"):
            continue
        head, _, value = part.partition("\n\n")
        disposition = re.search(r'name="([^"]+)"(?:;\s*filename="([^"]*)")?', head)
        if not disposition:
            continue
        key, filename = disposition.group(1), disposition.group(2)
        if filename is not None:
            notes.append(f"champ fichier « {key} » ({filename}) : à resélectionner dans Hoppscotch")
            items.append({"key": key, "value": "", "active": True, "isFile": False})
        else:
            items.append({"key": key, "value": convert_vars(value.strip("\n")), "active": True, "isFile": False})
    return items


def to_hopp_request(req: Request, source: str) -> dict:
    ctype, opts = _content_type(req.headers)
    headers = [
        {"key": k, "value": convert_vars(v), "active": True, "description": ""}
        for k, v in req.headers
        # Le type multipart (avec boundary) est recalculé par Hoppscotch
        if not (k.lower() == "content-type" and ctype == "multipart/form-data")
    ]
    body: dict = {"contentType": None, "body": None}
    if req.body is not None:
        if ctype == "multipart/form-data" and opts.get("boundary"):
            body = {"contentType": "multipart/form-data", "body": _multipart(req.body, opts["boundary"], req.notes)}
        elif ctype == "application/x-www-form-urlencoded":
            pairs = [p.partition("=") for p in req.body.replace("\n", "").split("&") if p]
            body = {"contentType": ctype, "body": "\n".join(f"{unquote_plus(k)}: {unquote_plus(v)}" for k, _, v in pairs)}
        else:
            body = {"contentType": ctype if ctype in BODY_TYPES else "text/plain", "body": convert_vars(req.body)}

    description = f"Synchronisé depuis {source}"
    if req.notes:
        description += "\n\n⚠ " + "\n⚠ ".join(dict.fromkeys(req.notes))
    return {
        "v": "17",
        "name": req.name,
        "method": req.method,
        "endpoint": convert_vars(req.url),
        "params": [],
        "headers": headers,
        "preRequestScript": "",
        "testScript": req.script,
        "auth": {"authType": "inherit", "authActive": True},
        "body": body,
        "requestVariables": [],
        "responses": {},
        "_ref_id": ref_id("req"),
        "description": description,
    }


def make_collection(name: str, requests: list[dict], folders: list[dict], description: str = "") -> dict:
    props = {
        "auth": {"authType": "inherit", "authActive": True},
        "headers": [],
        "variables": [],
        "preRequestScript": "",
        "testScript": "",
        "description": description or None,
    }
    return {
        "v": 12,
        "name": name,
        "folders": folders,
        "requests": requests,
        **props,
        "_ref_id": ref_id("coll"),
        # Propriétés de collection lues par le backend Hoppscotch à l'import
        "data": json.dumps(props),
    }


def find_files(project_dir: str) -> tuple[list[str], list[str]]:
    http_files, env_files = [], []
    for root, dirs, files in os.walk(project_dir):
        dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS and not d.startswith("."))
        for f in sorted(files):
            if f.endswith((".http", ".rest")):
                http_files.append(os.path.join(root, f))
            elif f == "http-client.env.json":
                env_files.append(os.path.join(root, f))
    return http_files, env_files


GENERIC_DIRS = {"http", "tests", "test", "api", "src", "requests", "rest", "ide", "run", "bundles", "module", "modules"}


def _short_label(rel_dir: str) -> str:
    """api/bundles/bme/printer-bundle/tests/Http -> printer-bundle"""
    parts = [p for p in rel_dir.split(os.sep) if p and p != "."]
    for part in reversed(parts):
        if part.lower() not in GENERIC_DIRS:
            return part
    return parts[0] if parts else rel_dir


def convert_project(project_dir: str, marker: str) -> tuple[dict | None, list[dict], dict]:
    """Renvoie (collection, environnements, statistiques) pour un projet."""
    project = os.path.basename(project_dir.rstrip("/"))
    http_files, env_files = find_files(project_dir)
    stats = {"files": len(http_files), "requests": 0, "warnings": 0, "errors": []}
    if not http_files:
        return None, [], stats

    by_dir: dict[str, list[dict]] = {}
    script_vars: set[str] = set()
    for path in http_files:
        rel = os.path.relpath(path, project_dir)
        try:
            reqs, written = parse_http_file(path)
        except Exception as exc:  # un fichier illisible ne bloque pas le projet
            stats["errors"].append(f"{rel} : {exc}")
            continue
        script_vars |= written
        hopp_reqs = [to_hopp_request(r, rel) for r in reqs]
        stats["requests"] += len(hopp_reqs)
        stats["warnings"] += sum(1 for r in hopp_reqs if "⚠" in r["description"])
        if hopp_reqs:
            folder = make_collection(os.path.basename(path), hopp_reqs, [], f"Fichier {rel}")
            by_dir.setdefault(os.path.dirname(rel) or ".", []).append(folder)

    # Un dossier par répertoire (chemin relatif), contenant un dossier par fichier .http
    folders = [make_collection(d, [], files) for d, files in sorted(by_dir.items()) if d != "."]
    root_files = by_dir.get(".", [])
    collection = make_collection(
        project,
        [],
        folders + root_files,
        f"{marker}\nCollection synchronisée automatiquement depuis {project_dir}. "
        "Les modifications faites ici sont écrasées à la prochaine synchronisation.",
    )

    environments = []
    # Le fichier d'environnements principal (le plus fourni) garde des noms courts ;
    # les autres sont suffixés par le dossier significatif le plus proche
    sizes = {}
    for env_path in env_files:
        try:
            sizes[env_path] = len(json.load(open(env_path, encoding="utf-8")))
        except Exception:
            sizes[env_path] = 0
    main_env = max(env_files, key=lambda f: (sizes[f], -f.count(os.sep)), default=None)
    for env_path in env_files:
        try:
            public = json.load(open(env_path, encoding="utf-8"))
        except Exception as exc:
            stats["errors"].append(f"{os.path.relpath(env_path, project_dir)} : {exc}")
            continue
        private_path = os.path.join(os.path.dirname(env_path), "http-client.private.env.json")
        private = {}
        if os.path.isfile(private_path):
            try:
                private = json.load(open(private_path, encoding="utf-8"))
            except Exception as exc:
                stats["errors"].append(f"{os.path.relpath(private_path, project_dir)} : {exc}")
        label = None if env_path == main_env else _short_label(os.path.relpath(os.path.dirname(env_path), project_dir))
        for env_name in sorted(set(public) | set(private)):
            values = {**(public.get(env_name) or {}), **(private.get(env_name) or {})}
            if not isinstance(values, dict):
                continue
            keys = {k: str(v) for k, v in values.items() if not isinstance(v, (dict, list))}
            for written in script_vars:
                keys.setdefault(written, "")
            # Environnements propres au workspace du projet : pas de préfixe de projet
            name = env_name if not label else f"{env_name} ({label})"
            environments.append({
                "name": name,
                "variables": [
                    {"key": k, "initialValue": v, "currentValue": v, "secret": False}
                    for k, v in sorted(keys.items())
                ],
            })
    return collection, environments, stats
