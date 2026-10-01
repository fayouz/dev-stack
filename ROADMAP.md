# Idées d'évolution de la stack

Suivi des évolutions de la stack : ce qui est fait, ce qui reste à régler, et les pistes pour plus tard.

Contexte à garder en tête :

- **RAM de la VM WSL** : 15,6 Go au total, dont environ 57 % déjà utilisés.
- **Proxy d'entreprise** : il intercepte le TLS. Le daemon Docker et les conteneurs sortent directement, contrairement au shell.
- **Docker Hub** : la limite anonyme (`429 Too Many Requests`) est souvent atteinte.

## Déjà en place

- [x] **it-tools** (`ghcr.io/corentinth/it-tools`) : outils de dev hors ligne.

- [x] **Login unique tinyauth** (`ghcr.io/tinyauthapp/tinyauth:v5`) devant les outils sans login propre, avec connexion automatique à Grafana. Il impose un domaine à deux niveaux : `DOMAIN=dev.localhost`, car les navigateurs refusent un cookie posé sur `localhost`.

- [x] **Hoppscotch** (`hoppscotch/hoppscotch`, avec `hoppscotch-db` en Postgres 16) : client d'API sur `local-hoppscotch.${DOMAIN}`. L'appli fonctionne sans compte. Pour activer les comptes (synchronisation des collections, équipes), terminer l'assistant de `/admin` avec le SMTP de Mailpit (`smtp://mailer:1025`).

- [x] **Cache d'images** (`registry-cache`, `registry:3.1.2`) sur `127.0.0.1:5000`, avec `mirror.gcr.io` comme source : plus de limite `429`. Le branchement du daemon se fait avec `make registry-mirror` (sudo, rechargement à chaud).

- [x] **WireMock** (`wiremock/wiremock:3.13.2`) : simulation d'API externes. Stubs versionnés dans `mnt/wiremock/mappings`, appel interne sur `http://wiremock:8080`, administration (`/__admin`) derrière le login unique.

- [x] **Healthchecks** (`healthchecks/healthchecks:v4.4`) : surveille la sauvegarde et la vérification Restic, avec alertes dans Mailpit. Interface derrière le login unique ; `/ping` et `/api` ouverts. Contrôles créés par `make healthchecks-init`.

## À régler en priorité

- [ ] **Oracle** (`oracle`, volume `docker-master_oracle_data`) ne démarre plus : `ORA-01578`, bloc corrompu dans `system01.dbf`.
  - Une copie du volume en l'état existe : `docker-master_oracle_data_copie_20260929`.
  - Décision à prendre : tenter une réparation, ou recréer la base à vide.
  - Ensuite, automatiser l'export Data Pump. `make backup-oracle` est manuel pour l'instant.
- [ ] **Sortir `.env` du suivi git** avec `git rm --cached .env`. Il contient tous les secrets de la stack.
- [ ] **Renforcer les mots de passe MariaDB et Oracle**, aujourd'hui `root` / `password`.
- [ ] **Enregistrer le mot de passe du login unique** (tinyauth) dans un gestionnaire de mots de passe. `.env` n'en contient que le hash.
- [ ] **Enregistrer `RESTIC_PASSWORD`** dans un gestionnaire de mots de passe. Sans lui, les sauvegardes sont irrécupérables.
- [ ] **Compte Docker Hub pour WUD** (`WUD_REGISTRY_HUB_PUBLIC_LOGIN` / `WUD_REGISTRY_HUB_PUBLIC_PASSWORD`). WUD interroge Docker Hub directement pour lister les versions, et le cache d'images ne l'aide pas.

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
| `prom/alertmanager` | Alertes dans Mailpit, Teams ou ntfy : conteneur arrêté, disque à plus de 90 %, sauvegarde échouée | 🟢 |
| `binwiederhier/ntfy` | Notifications push (téléphone, bureau) pour WUD, Restic et Alertmanager | 🟢 |
| `verdaccio/verdaccio` | Cache et registre npm privé : `npm install` plus rapides derrière le proxy | 🟢 |

### Observabilité

| Image | Utilité | Poids |
|---|---|---|
| `grafana/loki` + `grafana/alloy` | Historique des logs de tous les services, cherchable dans Grafana | 🟡 |
| `grafana/tempo` | Traces OpenTelemetry des applis (plumo, stp) dans Grafana | 🟡 |

### Sécurité et accès

| Image | Utilité | Poids |
|---|---|---|
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

### Outils de dev et collaboration

| Image | Utilité | Poids |
|---|---|---|
| `ghcr.io/gchq/cyberchef` | Encodages, décodages et transformations en chaîne | 🟢 |
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
| `sonatype/nexus3` | Cache tout-en-un (Docker, npm, Composer, Maven). Remplacerait `registry-cache` et Verdaccio | 🔴 |
| `sonarqube:community` | Analyse de qualité du code PHP et JS/TS | 🔴 |

## Pour l'ajout d'un service

Suivre les conventions du compose :

- réseau `bme_network` ;
- labels Traefik `Host(\`${SUBDOMAIN}-<nom>.${DOMAIN}\`)` ;
- label `dashboard.category=stack` (infrastructure) ou `dashboard.category=tools` (outil avec interface), pour son classement dans le dashboard ;
- labels `glance.*` ;
- labels `wud.watch=true`, plus `wud.tag.include` (tag de version) ou `wud.watch.digest=true` (tag `latest`) ;
- `make sync-hosts` pour ajouter le domaine au fichier hosts de Windows.
