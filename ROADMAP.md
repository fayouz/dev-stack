# Idées d'évolution de la stack

Suivi des évolutions de la stack : ce qui est fait, ce qui reste à régler, et les pistes pour plus tard.
Dernière mise à jour : 8 octobre 2026.

Contexte à garder en tête :

- **RAM de la VM WSL** : 15,6 Go au total, dont environ 10 Go utilisés avec toutes les stacks.
- **Charge** : une cinquantaine de conteneurs toutes stacks confondues. Lister les conteneurs peut prendre plusieurs secondes quand la machine est chargée.
- **Proxy d'entreprise** : il intercepte le TLS. Le daemon Docker et les conteneurs sortent directement, contrairement au shell.
- **Docker Hub** : la limite anonyme (`429 Too Many Requests`) de l'IP de l'entreprise est souvent épuisée ; les pulls passent par le cache local (`registry-cache`).

## Déjà en place

- [x] **it-tools** (`ghcr.io/corentinth/it-tools`) : outils de dev hors ligne.

- [x] **Login unique tinyauth** (`ghcr.io/tinyauthapp/tinyauth:v5`) devant les outils sans login propre, avec connexion automatique à Grafana. Il impose un domaine à deux niveaux : `DOMAIN=dev.localhost`, car les navigateurs refusent un cookie posé sur `localhost`.

- [x] **Hoppscotch** (`hoppscotch/hoppscotch`, avec `hoppscotch-db` en Postgres 16) : client d'API sur `local-hoppscotch.${DOMAIN}`. L'appli fonctionne sans compte. Pour activer les comptes (synchronisation des collections, équipes), terminer l'assistant de `/admin` avec le SMTP de Mailpit (`smtp://mailer:1025`).

- [x] **Cache d'images** (`registry-cache`, `registry:3.1.2`) sur `127.0.0.1:5000`, avec `mirror.gcr.io` comme source : plus de limite `429`. Le branchement du daemon se fait avec `make registry-mirror` (sudo, rechargement à chaud).

- [x] **WireMock** (`wiremock/wiremock:3.13.2`) : simulation d'API externes. Stubs versionnés dans `mnt/wiremock/mappings`, appel interne sur `http://wiremock:8080`, administration (`/__admin`) derrière le login unique.

- [x] **Healthchecks** (`healthchecks/healthchecks:v4.4`) : surveille la sauvegarde et la vérification Restic, avec alertes dans Mailpit. Interface derrière le login unique ; `/ping` et `/api` ouverts. Contrôles créés par `make healthchecks-init`.

- [x] **Dockge** (`louislam/dockge:1.5.0`) : gestion des projets Compose de `PROJECTS_DIR` (éditer, démarrer, arrêter, mettre à jour). Il voit les projets via des liens en minuscules dans `mnt/dockge/stacks` : relancer `make dockge-sync` après avoir ajouté un projet. Derrière le login unique et son propre compte. Pas d'autocomplétion ni d'IA : à revoir avec code-server si besoin.

- [x] **Synchro `.http` → Hoppscotch** (`hoppscotch-sync`) : chaque projet de `PROJECTS_DIR` qui a des fichiers HTTP JetBrains a son workspace Hoppscotch (une équipe), avec ses répertoires en collections et ses environnements, mis à jour quelques secondes après chaque enregistrement. Un projet supprimé vide son workspace sans le supprimer. Sens unique : les fichiers font foi, et les modifications faites dans Hoppscotch sont écrasées. Voir `make logs-hoppscotch-sync`.

- [x] **Charge maîtrisée** : cAdvisor limité aux métriques CPU, mémoire et réseau et plafonné à 1 cœur (il en saturait 4) ; Dozzle à la demande (`make dozzle`, ou bouton Démarrer du dashboard), car il coûte ~20 % de CPU à dockerd et à containerd tant qu'il tourne.

- [x] **Dashboard résistant à un Docker lent** : une seule requête Docker partagée, la dernière liste connue en secours, et un bandeau qui indique son âge.

- [x] **`.env` sorti du suivi git**, fichiers personnels d'IDE et d'agents IA ignorés.

- [x] **Mêmes identifiants partout** : `admin` + le mot de passe du login unique pour WUD, Portainer et Dockge. Session Hoppscotch portée à 90 jours (connexion par lien e-mail une fois par trimestre).

- [x] **Images mises à jour** (8 octobre) : Traefik v3.7, Portainer 2.45.2, Hoppscotch 2026.9.0, nouvelles versions d'Adminer, Glance, Mailpit et WUD. MariaDB 13 et Postgres 18 volontairement écartés (versions majeures).

- [x] **Oracle mis en pause** : hors du démarrage automatique (profil `on-demand`), en attendant la décision.

- [x] **HTTPS pour la dev-stack** (`*.dev.localhost`) : autorité locale restreinte à ce domaine (`make certs`), installée dans Windows et WSL. Redirection automatique depuis HTTP ; les autres projets (`*.localhost`) restent en HTTP.

- [x] **SSO via tinyauth (OIDC) pour Portainer et WUD** : connexion automatique avec la session du login unique. Portainer retombe sur son compte `admin` (pas de création automatique de comptes) ; WUD donne le rôle admin à l'utilisateur tinyauth `admin`. Les logins locaux restent en secours. La configuration OAuth de Portainer est dans sa base : à refaire dans *Settings > Authentication* si ses données sont réinitialisées. Hoppscotch et Dockge gardent les identifiants alignés (pas d'OIDC générique).

## À régler en priorité

- [ ] **MariaDB 12 → 13** (majeure) : à faire volontairement, après une sauvegarde fraîche, pas depuis WUD. (Postgres 16 → 18 de `hoppscotch-db` est désormais bloqué dans WUD.)
- [ ] **Oracle** (`oracle`, volume `docker-master_oracle_data`, **en pause**) ne démarre plus : `ORA-01578`, bloc corrompu dans `system01.dbf`.
  - Une copie du volume en l'état existe : `docker-master_oracle_data_copie_20260929`.
  - Décision à prendre : tenter une réparation, ou recréer la base à vide.
  - Ensuite, automatiser l'export Data Pump. `make backup-oracle` est manuel pour l'instant.
- [ ] **Renforcer les mots de passe MariaDB et Oracle**, aujourd'hui `root` / `password`.
- [ ] **Enregistrer le mot de passe du login unique** (tinyauth) dans un gestionnaire de mots de passe. `.env` n'en contient que le hash.
- [ ] **Enregistrer `RESTIC_PASSWORD`** dans un gestionnaire de mots de passe. Sans lui, les sauvegardes sont irrécupérables.
- [ ] **Hoppscotch** : se connecter une fois sur `/admin` pour devenir administrateur de l'instance (le compte `admin@dev.localhost` ne l'est pas encore).
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

- [x] **Organizr et Glance à la demande** : ils font double emploi avec le dashboard Nuxt et ne démarrent plus automatiquement (profil `on-demand`, à lancer depuis la page Services).

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
