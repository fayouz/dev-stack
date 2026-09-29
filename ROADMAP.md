# Idées d'évolution de la stack

Pistes à reprendre plus tard. Aucune n'est encore en place.

Contexte à garder en tête :

- **RAM de la VM WSL** : 15,6 Go au total, dont environ 57 % déjà utilisés.
- **Proxy d'entreprise** : il intercepte le TLS. Le daemon Docker et les conteneurs sortent directement, contrairement au shell.
- **Docker Hub** : la limite anonyme (`429 Too Many Requests`) est souvent atteinte.

## À régler en priorité

- [ ] **Oracle** (`oracle`, volume `docker-master_oracle_data`) ne démarre plus : `ORA-01578`, bloc corrompu dans `system01.dbf`.
  - Une copie du volume en l'état existe : `docker-master_oracle_data_copie_20260929`.
  - Décision à prendre : tenter une réparation, ou recréer la base à vide.
  - Ensuite, automatiser l'export Data Pump. `make backup-oracle` est manuel pour l'instant.
- [ ] **Sortir `.env` du suivi git** avec `git rm --cached .env`. Il contient tous les secrets de la stack.
- [ ] **Renforcer les mots de passe MariaDB et Oracle**, aujourd'hui `root` / `password`.
- [ ] **Enregistrer le mot de passe du dashboard et de Traefik** dans un gestionnaire de mots de passe. `.env` n'en contient que le hash.
- [ ] **Enregistrer `RESTIC_PASSWORD`** dans un gestionnaire de mots de passe. Sans lui, les sauvegardes sont irrécupérables.
- [ ] **Compte Docker Hub pour WUD** (`WUD_REGISTRY_HUB_PUBLIC_LOGIN` / `WUD_REGISTRY_HUB_PUBLIC_PASSWORD`), ou un cache `registry:2` (voir plus bas).

## Améliorations de l'existant

### Robustesse

- [ ] **Healthchecks sur Traefik, MariaDB et Portainer.** Ils s'afficheraient « sain » au lieu de « actif », et `depends_on: condition: service_healthy` deviendrait possible. L'image MariaDB fournit `healthcheck.sh`.
- [ ] **Copie des sauvegardes Restic hors de la VM** : `/mnt/c/...`, NAS ou S3. Aujourd'hui, le dépôt est sur le même disque que les données.
- [ ] **Fixer les images encore en `latest`** (Grafana, Prometheus, Dozzle, WUD, Adminer, Mailpit…). WUD verrait de vraies versions et réécrirait le compose, ce qui rend l'environnement reproductible.
- [ ] **Découper `docker-compose.traefik.yaml`** (plus de 600 lignes) en plusieurs fichiers assemblés avec `include:` : proxy, bases, monitoring, outils.
- [ ] **Limites mémoire (`mem_limit`)** sur Oracle et les autres services gourmands.

### Dashboard Nuxt (`mnt/dashboard/`)

- [ ] **Bouton « Logs »** sur chaque ligne de la page Services, qui ouvre la carte des logs sur ce service.
- [ ] **Bouton « Mettre à jour »** dans la liste des mises à jour, en appelant l'API de WUD (déclencheur `dockercompose.stack`).
- [ ] **Bouton « Sauvegarder maintenant »**, qui lance `backup.sh` dans le conteneur `restic`.
- [ ] **Mini-historique CPU/RAM** par service (page de détail ou tiroir).
- [ ] **Carte « Vulnérabilités »** alimentée par Trivy.

### Faire de la place

- [ ] **Retirer Organizr et Glance**, qui font maintenant double emploi avec le dashboard Nuxt. Ça libère de la RAM.

## Images à ajouter

Poids : 🟢 léger · 🟡 moyen · 🔴 lourd (1 Go de RAM ou plus).

### Priorité haute

| Image | Utilité | Poids |
|---|---|---|
| `registry:2` en cache de Docker Hub | Supprime les erreurs `429` : chaque image n'est téléchargée qu'une fois | 🟢 |
| `prom/alertmanager` | Alertes dans Mailpit, Teams ou ntfy : conteneur arrêté, disque à plus de 90 %, sauvegarde échouée | 🟢 |
| `binwiederhier/ntfy` | Notifications push (téléphone, bureau) pour WUD, Restic et Alertmanager | 🟢 |
| `corentinth/it-tools` | ~80 outils de dev hors ligne (JSON, JWT, base64, hash, cron, regex…), sans rien coller dans des sites externes | 🟢 |
| `verdaccio/verdaccio` | Cache et registre npm privé : `npm install` plus rapides derrière le proxy | 🟢 |

### Observabilité

| Image | Utilité | Poids |
|---|---|---|
| `grafana/loki` + `grafana/alloy` | Historique des logs de tous les services, cherchable dans Grafana | 🟡 |
| `grafana/tempo` | Traces OpenTelemetry des applis (plumo, stp) dans Grafana | 🟡 |
| `healthchecks/healthchecks` | Alerte si une tâche planifiée ne s'exécute pas (sauvegarde Restic manquée…) | 🟢 |

### Sécurité et accès

| Image | Utilité | Poids |
|---|---|---|
| Authelia ou tinyauth (forward-auth Traefik) | Un seul login pour tous les outils, au lieu de 5 identifiants différents | 🟢 |
| `vaultwarden/server` | Gestionnaire de mots de passe compatible Bitwarden, pour les secrets de la stack | 🟢 |
| `quay.io/keycloak/keycloak` | SSO et OIDC pour tester l'authentification des applis | 🟡 |
| `aquasec/trivy` | Scan de vulnérabilités des images, lancé à la demande | 🟢 |

### Bases de données et données

| Image | Utilité | Poids |
|---|---|---|
| `dbeaver/cloudbeaver` | Client SQL web qui gère Oracle, MariaDB et Postgres. Adminer ne gère pas Oracle | 🟡 |
| ORDS (`container-registry.oracle.com/database/ords`) | SQL Developer Web et API REST automatiques sur Oracle | 🟡 |
| `postgres:17-alpine` | Le dossier `mnt/postgres/` existe déjà mais aucun service ne l'utilise | 🟢 |
| `valkey/valkey` + `redis/redisinsight` | Cache et sessions, avec une interface pour parcourir les clés | 🟢 |
| `getmeili/meilisearch` | Moteur de recherche instantané | 🟡 |
| `rabbitmq:4-management-alpine` | Files de messages, avec interface d'administration | 🟡 |
| `rustfs/rustfs` ou `chrislusf/seaweedfs` | Stockage compatible S3 en local. MinIO a restreint ses images libres | 🟢 |

### Outils pour les applis PHP / Nuxt

| Image | Utilité | Poids |
|---|---|---|
| `gotenberg/gotenberg` | Génération de PDF à partir de HTML ou de fichiers Office via une API | 🟡 |
| `quay.io/soketi/soketi` | WebSockets compatibles Pusher (Laravel Echo) | 🟢 |
| `dunglas/mercure` | Serveur temps réel en SSE (Symfony, Nuxt) | 🟢 |
| `composer/satis` | Dépôt Composer privé pour les paquets PHP internes | 🟢 |
| `wiremock/wiremock` | Simulation d'API externes | 🟢 |

### Outils de dev et collaboration

| Image | Utilité | Poids |
|---|---|---|
| `ghcr.io/gchq/cyberchef` | Encodages, décodages et transformations en chaîne | 🟢 |
| `hoppscotch/hoppscotch` | Client d'API façon Postman, auto-hébergé | 🟡 |
| `swaggerapi/swagger-ui` | Documentation interactive des API OpenAPI | 🟢 |
| `excalidraw/excalidraw` / `jgraph/drawio` | Schémas d'architecture qui restent en local | 🟢 |
| `gitea/gitea` + `gitea/act_runner` | Git et CI locaux, façon GitHub Actions | 🟡 |
| `n8nio/n8n` | Automatisations visuelles (webhooks, Teams, tâches planifiées) | 🟡 |

### Tests

| Image | Utilité | Poids |
|---|---|---|
| `ghcr.io/browserless/chromium` | Chrome headless partagé : tests end-to-end, captures, PDF | 🟡 |
| `ghcr.io/shopify/toxiproxy` | Simulation de latence et de coupures réseau vers les bases | 🟢 |
| `localstack/localstack` | Émulation de services AWS (S3, SQS, Lambda…) | 🟡 |

### Lourds, à réserver à un vrai besoin

| Image | Utilité | Poids |
|---|---|---|
| `sonatype/nexus3` | Cache tout-en-un (Docker, npm, Composer, Maven). Remplace `registry:2` et Verdaccio | 🔴 |
| `sonarqube:community` | Analyse de qualité du code PHP et JS/TS | 🔴 |

## Pour l'ajout d'un service

Suivre les conventions du compose :

- réseau `bme_network` ;
- labels Traefik `Host(\`${SUBDOMAIN}-<nom>.${DOMAIN}\`)` ;
- labels `glance.*` ;
- labels `wud.watch=true`, plus `wud.tag.include` (tag de version) ou `wud.watch.digest=true` (tag `latest`) ;
- `make sync-hosts` pour ajouter le domaine au fichier hosts de Windows.
