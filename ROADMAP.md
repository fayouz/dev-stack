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

- [x] **Compose découpé** (14 octobre) : services répartis par fonction dans `compose/` (proxy, databases, monitoring, backups, hoppscotch, tools, dashboard), assemblés par `docker-compose.traefik.yaml` avec `include:`. Configuration résolue identique à l'ancienne.

- [x] **Mises à jour WUD sans reformatage** (14 octobre) : mode rollback (remplacement du seul tag dans le fichier du service, indiqué par le label `wud.compose.file`), retour arrière automatique si le conteneur n'est pas sain dans les 5 minutes.

- [x] **Healthchecks sur Traefik et MariaDB** (14 octobre) : Traefik via `/ping`, MariaDB via le script de l'image ; restic et Organizr attendent une MariaDB saine. Portainer n'en a pas : son image ne contient aucun outil pour l'interroger.

- [x] **Versions figées** (14 octobre) : les images en `latest` pointent sur la version exacte qui tournait (même image), WUD suit leurs tags. Seul Organizr reste en `latest` (aucune version publiée), suivi par digest.

- [x] **MariaDB à la demande** (14 octobre) : `make mariadb` / `make mariadb-stop` ou la page Services. La sauvegarde ignore le dump quand elle est arrêtée. Elle est jointe sous le nom unique `docker-master-mariadb` : `mariadb` désignait aussi la base de planning-dcs, que la sauvegarde a pu viser (snapshot `24ec8da5` du 14 octobre, et possiblement d'autres quand les deux tournaient).

- [x] **MariaDB 13.0** : mise à jour via WUD le 9 octobre, `mariadb-upgrade` passé le 12 octobre après une sauvegarde fraîche.

- [x] **Oracle recréé à vide** (13 octobre) : l'ancienne base corrompue (`ORA-01578`) est abandonnée, sa copie reste dans le volume `docker-master_oracle_data_copie_20260929` (3,3 Go, à supprimer quand plus utile). Toujours à la demande (profil `on-demand`), utilisateur applicatif `RGZ` sur `XEPDB1`.

- [x] **HTTPS pour la dev-stack** (`*.dev.localhost`) : autorité locale restreinte à ce domaine (`make certs`), installée dans Windows et WSL. Redirection automatique depuis HTTP ; les autres projets (`*.localhost`) restent en HTTP.

- [x] **SSO via tinyauth (OIDC) pour Portainer et WUD** : connexion automatique avec la session du login unique. Portainer retombe sur son compte `admin` (pas de création automatique de comptes) ; WUD donne le rôle admin à l'utilisateur tinyauth `admin`. Les logins locaux restent en secours. La configuration OAuth de Portainer est dans sa base : à refaire dans *Settings > Authentication* si ses données sont réinitialisées. Hoppscotch et Dockge gardent les identifiants alignés (pas d'OIDC générique).

## À régler en priorité

- [ ] **Postgres 16 → 18** de `hoppscotch-db` : bloqué dans WUD, à faire volontairement (dump puis restauration).
- [ ] **Renforcer les mots de passe MariaDB et Oracle**, aujourd'hui `root` / `password`.
- [ ] **Enregistrer le mot de passe du login unique** (tinyauth) dans un gestionnaire de mots de passe. `.env` n'en contient que le hash.
- [ ] **Enregistrer `RESTIC_PASSWORD`** dans un gestionnaire de mots de passe. Sans lui, les sauvegardes sont irrécupérables.
- [ ] **Hoppscotch** : se connecter une fois sur `/admin` pour devenir administrateur de l'instance (le compte `admin@dev.localhost` ne l'est pas encore).
- [ ] **Compte Docker Hub pour WUD** (`WUD_REGISTRY_HUB_PUBLIC_LOGIN` / `WUD_REGISTRY_HUB_PUBLIC_PASSWORD`). WUD interroge Docker Hub directement pour lister les versions, et le cache d'images ne l'aide pas.

## Améliorations de l'existant

### Robustesse

- [ ] **Copie des sauvegardes Restic hors de la VM** : `/mnt/c/...`, NAS ou S3. Aujourd'hui, le dépôt est sur le même disque que les données.
- [ ] **Limites mémoire (`mem_limit`)** sur Oracle et les autres services gourmands.

### Dashboard Nuxt (`mnt/dashboard/`)

- [x] **Tiroir de détail par service** (page Services) : historique CPU / RAM (15 min à 24 h) et logs en direct.
- [x] **Bouton « Mettre à jour »** dans la liste des mises à jour, via le déclencheur `dockercompose.stack` de WUD (confirmation, alerte pour les versions majeures).
- [x] **Bouton « Sauvegarder maintenant »** : le dashboard dépose une demande que le conteneur `restic` exécute (pas d'exec Docker).
- [x] **Page « Vulnérabilités »** alimentée par Trivy (analyse quotidienne des images en cours d'exécution, ou à la demande).

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

- service dans le fichier `compose/<fonction>.yaml` adapté (ou un nouveau fichier ajouté à l'`include:` de `docker-compose.traefik.yaml`) ;
- réseau `stack_network` (déclaré en bas du fichier) ;
- labels Traefik `Host(\`${SUBDOMAIN}-<nom>.${DOMAIN}\`)`, entrypoint `websecure` et `tls=true` ;
- label `dashboard.category=stack` (infrastructure) ou `dashboard.category=tools` (outil avec interface), pour son classement dans le dashboard ;
- labels `glance.*` ;
- labels `wud.watch=true`, `wud.compose.file=/project/compose/<fichier>.yaml`, plus `wud.tag.include` (tag de version ; `latest` seulement si aucune version n'est publiée, avec `wud.watch.digest=true`) ;
- `make sync-hosts` pour ajouter le domaine au fichier hosts de Windows.
