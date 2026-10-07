# Makefile pour gérer Docker Compose avec Traefik
# Usage: make [command]

# Variables
COMPOSE_FILE = docker-compose.traefik.yaml
COMPOSE_FILE_AUX = docker-compose.yaml
COMPOSE_FILE_PLUMO = docker-compose.plumo.yaml
PROJECT_NAME = docker-master
NETWORK_SUBNET = 172.25.0.0/24
NETWORK_SUBNET_AUX = 172.25.1.0/24
NETWORK_GATEWAY = 172.25.0.1
NETWORK_GATEWAY_AUX = 172.25.1.1

# Couleurs pour l'affichage
GREEN = \033[0;32m
YELLOW = \033[1;33m
RED = \033[0;31m
BLUE = \033[0;34m
NC = \033[0m # No Color

.PHONY: help up down restart logs status ps build pull clean prune network migrate-network test-oracle sync-hosts sync-hosts-ps hosts \
	logs-socket-proxy logs-wud logs-dashboard logs-registry logs-prometheus logs-grafana logs-restic update-one \
	backup-now backup-snapshots backup-check backup-oracle backup-restore-test registry-mirror healthchecks-init dockge-sync

# Commande par défaut
help: ## Affiche cette aide
	@echo "$(GREEN)Makefile pour Docker Compose Traefik$(NC)"
	@echo ""
	@echo "$(YELLOW)Commandes disponibles:$(NC)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(GREEN)%-18s$(NC) %s\n", $$1, $$2}' $(MAKEFILE_LIST)

up: ## Démarre les services Traefik
	@echo "$(GREEN)Démarrage des services Traefik...$(NC)"
	docker compose -f $(COMPOSE_FILE)  -p $(PROJECT_NAME) up -d
	@echo "$(GREEN)Services démarrés avec succès!$(NC)"
	@$(MAKE) hosts

up-all: network ## Démarre TOUS les services (Traefik + auxiliaires + Plumo)
	@echo "$(GREEN)Démarrage de tous les services...$(NC)"
	@echo ""
	@echo "$(BLUE)▶️  Démarrage de Traefik...$(NC)"
	docker compose -f $(COMPOSE_FILE) -p $(PROJECT_NAME) up -d
	@sleep 2
	@echo ""
	@echo "$(BLUE)▶️  Démarrage des services auxiliaires...$(NC)"
	@if [ -f $(COMPOSE_FILE_AUX) ]; then docker compose -f $(COMPOSE_FILE_AUX) up -d 2>/dev/null || true; fi
	@sleep 2
	@echo ""
	@echo "$(BLUE)▶️  Démarrage de Plumo...$(NC)"
	@if [ -f $(COMPOSE_FILE_PLUMO) ]; then docker compose -f $(COMPOSE_FILE_PLUMO) up -d; fi
	@echo ""
	@echo "$(GREEN)✅ Tous les services sont démarrés!$(NC)"
	@$(MAKE) ps-all
	@$(MAKE) hosts

down: ## Arrête tous les services Traefik
	@echo "$(RED)Arrêt des services Traefik...$(NC)"
	docker compose -f $(COMPOSE_FILE) -p $(PROJECT_NAME) down
	@echo "$(GREEN)Services arrêtés avec succès!$(NC)"

down-all: ## Arrête TOUS les services (Traefik + auxiliaires + Plumo)
	@echo "$(RED)Arrêt de tous les services...$(NC)"
	@if [ -f $(COMPOSE_FILE_PLUMO) ]; then docker compose -f $(COMPOSE_FILE_PLUMO) down 2>/dev/null || true; fi
	@if [ -f $(COMPOSE_FILE_AUX) ]; then docker compose -f $(COMPOSE_FILE_AUX) down 2>/dev/null || true; fi
	docker compose -f $(COMPOSE_FILE) -p $(PROJECT_NAME) down
	@echo "$(GREEN)Tous les services sont arrêtés!$(NC)"

restart: ## Redémarre tous les services Traefik
	@echo "$(YELLOW)Redémarrage des services Traefik...$(NC)"
	$(MAKE) down
	$(MAKE) up

restart-all: ## Redémarre TOUS les services
	@echo "$(YELLOW)Redémarrage de tous les services...$(NC)"
	$(MAKE) down-all
	$(MAKE) up-all

logs: ## Affiche les logs de tous les services
	docker compose -f $(COMPOSE_FILE) -p $(PROJECT_NAME) logs -f

logs-traefik: ## Affiche les logs de Traefik uniquement
	docker compose -f $(COMPOSE_FILE) -p $(PROJECT_NAME) logs -f traefik

logs-portainer: ## Affiche les logs de Portainer uniquement
	docker compose -f $(COMPOSE_FILE) -p $(PROJECT_NAME) logs -f portainer

logs-adminer: ## Affiche les logs d'Adminer uniquement
	docker compose -f $(COMPOSE_FILE) -p $(PROJECT_NAME) logs -f adminer

logs-dozzle: ## Affiche les logs de Dozzle uniquement
	docker compose -f $(COMPOSE_FILE) -p $(PROJECT_NAME) logs -f dozzle

logs-mailer: ## Affiche les logs de Mailer (Mailpit) uniquement
	docker compose -f $(COMPOSE_FILE) -p $(PROJECT_NAME) logs -f mailer

logs-mariadb: ## Affiche les logs de MariaDB uniquement
	docker compose -f $(COMPOSE_FILE) -p $(PROJECT_NAME) logs -f mariadb

logs-socket-proxy: ## Affiche les logs du proxy du socket Docker
	docker compose -f $(COMPOSE_FILE) -p $(PROJECT_NAME) logs -f docker-socket-proxy

logs-wud: ## Affiche les logs de WUD (suivi des mises à jour)
	docker compose -f $(COMPOSE_FILE) -p $(PROJECT_NAME) logs -f wud

logs-dashboard: ## Affiche les logs du dashboard Nuxt
	docker compose -f $(COMPOSE_FILE) -p $(PROJECT_NAME) logs -f dashboard

logs-registry: ## Affiche les logs du cache d'images Docker Hub
	docker compose -f $(COMPOSE_FILE) -p $(PROJECT_NAME) logs -f registry-cache

logs-prometheus: ## Affiche les logs de Prometheus uniquement
	docker compose -f $(COMPOSE_FILE) -p $(PROJECT_NAME) logs -f prometheus

logs-grafana: ## Affiche les logs de Grafana uniquement
	docker compose -f $(COMPOSE_FILE) -p $(PROJECT_NAME) logs -f grafana

logs-restic: ## Affiche les logs des sauvegardes Restic
	docker compose -f $(COMPOSE_FILE) -p $(PROJECT_NAME) logs -f restic

logs-plumo: ## Affiche les logs de Plumo (backend + frontend)
	@if [ -f $(COMPOSE_FILE_PLUMO) ]; then \
		docker compose -f $(COMPOSE_FILE_PLUMO) logs -f; \
	else \
		echo "$(RED)Fichier $(COMPOSE_FILE_PLUMO) introuvable!$(NC)"; \
	fi

status: ## Affiche le statut des services Traefik
	@echo "$(GREEN)Statut des services Traefik:$(NC)"
	docker compose -f $(COMPOSE_FILE) -p $(PROJECT_NAME) ps

ps: ## Alias pour status
	$(MAKE) status

ps-all: ## Affiche le statut de TOUS les conteneurs
	@echo "$(GREEN)Statut de tous les conteneurs:$(NC)"
	@docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Networks}}" | head -1
	@docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Networks}}" | grep -v NAMES | sort

hosts: ## Liste les hôtes Traefik disponibles
	@echo "$(GREEN)Hôtes Traefik disponibles:$(NC)"
	@docker compose -f $(COMPOSE_FILE) config | grep -oP 'Host\(`\K[^`]+' | sort -u | awk '{print "  - http://" $$1}'

sync-hosts: ## Synchronise les hôtes Traefik avec le fichier hosts de Windows (Bash)
	@echo "$(YELLOW)Synchronisation des hôtes (WSL)...$(NC)"
	@chmod +x scripts/sync_hosts.sh
	@./scripts/sync_hosts.sh

sync-hosts-ps: ## Synchronise les hôtes Traefik avec le fichier hosts de Windows (PowerShell)
	@echo "$(YELLOW)Synchronisation des hôtes (PowerShell)...$(NC)"
	@powershell.exe -ExecutionPolicy Bypass -File scripts/sync_hosts.ps1

build: ## Reconstruit les images (si nécessaire)
	@echo "$(YELLOW)Reconstruction des images...$(NC)"
	docker compose -f $(COMPOSE_FILE) -p $(PROJECT_NAME) build

pull: ## Met à jour les images depuis Docker Hub
	@echo "$(YELLOW)Mise à jour des images...$(NC)"
	docker compose -f $(COMPOSE_FILE) -p $(PROJECT_NAME) pull

clean: ## Arrête les services et supprime les conteneurs
	@echo "$(RED)Nettoyage des conteneurs...$(NC)"
	docker compose -f $(COMPOSE_FILE) -p $(PROJECT_NAME) down --remove-orphans
	@echo "$(GREEN)Nettoyage terminé!$(NC)"

prune: ## Supprime les images, volumes et réseaux inutilisés
	@echo "$(RED)Suppression des ressources inutilisées...$(NC)"
	@echo "$(YELLOW)Attention: Cette commande va supprimer les ressources Docker non utilisées!$(NC)"
	@read -p "Êtes-vous sûr? [y/N] " -n 1 -r; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		echo ""; \
		docker system prune -af --volumes; \
		echo "$(GREEN)Nettoyage terminé!$(NC)"; \
	else \
		echo ""; \
		echo "$(YELLOW)Opération annulée.$(NC)"; \
	fi

network: ## Crée les réseaux bme_network s'ils n'existent pas
	@echo "$(YELLOW)Vérification des réseaux...$(NC)"
	@docker network prune -f >/dev/null 2>&1 || true
	@if ! docker network inspect bme_network >/dev/null 2>&1; then \
		echo "$(GREEN)Création du réseau bme_network ($(NETWORK_SUBNET))...$(NC)"; \
		docker network create --subnet=$(NETWORK_SUBNET) --gateway=$(NETWORK_GATEWAY) bme_network; \
		echo "$(GREEN)Réseau bme_network créé avec succès!$(NC)"; \
	else \
		echo "$(GREEN)Le réseau bme_network existe déjà.$(NC)"; \
	fi
	@if ! docker network inspect bme_network_aux >/dev/null 2>&1; then \
		echo "$(GREEN)Création du réseau bme_network_aux ($(NETWORK_SUBNET_AUX))...$(NC)"; \
		docker network create --subnet=$(NETWORK_SUBNET_AUX) --gateway=$(NETWORK_GATEWAY_AUX) bme_network_aux; \
		echo "$(GREEN)Réseau bme_network_aux créé avec succès!$(NC)"; \
	else \
		echo "$(GREEN)Le réseau bme_network_aux existe déjà.$(NC)"; \
	fi

network-info: ## Affiche les informations des réseaux Docker
	@echo "$(BLUE)📊 Informations des réseaux Docker:$(NC)"
	@echo ""
	@docker network ls | head -1
	@docker network ls | grep -E "(bme_network|bridge|host)"
	@echo ""
	@if docker network inspect bme_network >/dev/null 2>&1; then \
		echo "$(YELLOW)Détails bme_network:$(NC)"; \
		docker network inspect bme_network | grep -A 5 "IPAM" | grep -E "(Subnet|Gateway)"; \
	fi
	@echo ""
	@if docker network inspect bme_network_aux >/dev/null 2>&1; then \
		echo "$(YELLOW)Détails bme_network_aux:$(NC)"; \
		docker network inspect bme_network_aux | grep -A 5 "IPAM" | grep -E "(Subnet|Gateway)"; \
	fi

migrate-network: ## Migre les réseaux pour éviter le conflit avec Oracle (172.18.20.60)
	@echo "$(RED)⚠️  Cette commande va:$(NC)"
	@echo "  - Arrêter tous les services Docker"
	@echo "  - Supprimer les réseaux bme_network actuels"
	@echo "  - Recréer les réseaux sur $(NETWORK_SUBNET) et $(NETWORK_SUBNET_AUX)"
	@echo "  - Redémarrer tous les services"
	@echo ""
	@read -p "Continuer? [y/N] " -n 1 -r; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		echo ""; \
		echo ""; \
		$(MAKE) _do-migrate-network; \
	else \
		echo ""; \
		echo "$(YELLOW)Opération annulée.$(NC)"; \
	fi

_do-migrate-network:
	@echo "$(BLUE)🔴 Étape 1/5: Arrêt de tous les services...$(NC)"
	@$(MAKE) down-all
	@sleep 2
	@echo ""
	@echo "$(BLUE)🗑️  Étape 2/5: Suppression des anciens réseaux...$(NC)"
	@docker network rm bme_network 2>/dev/null && echo "$(GREEN)✓ bme_network supprimé$(NC)" || echo "$(YELLOW)⚠ bme_network déjà supprimé$(NC)"
	@docker network rm bme_network_aux 2>/dev/null && echo "$(GREEN)✓ bme_network_aux supprimé$(NC)" || echo "$(YELLOW)⚠ bme_network_aux déjà supprimé$(NC)"
	@docker network prune -f >/dev/null 2>&1
	@echo ""
	@echo "$(BLUE)🔧 Étape 3/5: Création des nouveaux réseaux...$(NC)"
	@docker network create --subnet=$(NETWORK_SUBNET) --gateway=$(NETWORK_GATEWAY) bme_network
	@echo "$(GREEN)✓ bme_network créé ($(NETWORK_SUBNET))$(NC)"
	@docker network create --subnet=$(NETWORK_SUBNET_AUX) --gateway=$(NETWORK_GATEWAY_AUX) bme_network_aux
	@echo "$(GREEN)✓ bme_network_aux créé ($(NETWORK_SUBNET_AUX))$(NC)"
	@echo ""
	@echo "$(BLUE)📋 Étape 4/5: Vérification de la configuration...$(NC)"
	@$(MAKE) network-info
	@echo ""
	@echo "$(BLUE)🚀 Étape 5/5: Redémarrage de tous les services...$(NC)"
	@$(MAKE) up-all
	@echo ""
	@echo "$(GREEN)✅ Migration terminée avec succès!$(NC)"
	@echo ""
	@echo "$(YELLOW)💡 Test de connectivité Oracle dans 5 secondes...$(NC)"
	@sleep 5
	@$(MAKE) test-oracle || true

test-oracle: ## Test la connectivité vers Oracle (172.18.20.60:1521)
	@echo "$(BLUE)🧪 Test de connectivité Oracle...$(NC)"
	@echo ""
	@if docker ps --format '{{.Names}}' | grep -q plumo_backend; then \
		echo "$(YELLOW)Test 1: Ping vers 172.18.20.60...$(NC)"; \
		docker exec plumo_backend ping -c 2 172.18.20.60 2>/dev/null && echo "$(GREEN)✓ Ping OK$(NC)" || echo "$(RED)✗ Ping échoué$(NC)"; \
		echo ""; \
		echo "$(YELLOW)Test 2: Connexion TCP au port 1521...$(NC)"; \
		docker exec plumo_backend nc -zv 172.18.20.60 1521 2>&1 | head -1; \
		echo ""; \
	else \
		echo "$(RED)✗ Conteneur plumo_backend introuvable. Démarrez-le avec 'make up-all'$(NC)"; \
	fi

setup: network up ## Configuration initiale complète
	@echo "$(GREEN)Configuration Traefik terminée!$(NC)"

dev: ## Mode développement avec logs en temps réel
	$(MAKE) up
	$(MAKE) logs

# Commandes de maintenance
update: pull restart ## Met à jour et redémarre les services

# Lit une variable de .env (sans le "sourcer" : des valeurs comme "0 12 * * *" le casseraient)
env_value = $$(grep '^$(1)=' .env | cut -d= -f2-)

healthchecks-init: ## Crée ou met à jour les contrôles Healthchecks de la stack (idempotent)
	@out=$$(docker exec -i \
		-e "HC_OWNER_EMAIL=admin@$(call env_value,DOMAIN)" \
		-e "HC_PING_KEY=$(call env_value,HEALTHCHECKS_PING_KEY)" \
		-e "HC_BACKUP_CRON=$(call env_value,RESTIC_CRON)" \
		-e "HC_CHECK_CRON=$(call env_value,RESTIC_CHECK_CRON)" \
		healthchecks ./manage.py shell < mnt/healthchecks/init_checks.py) || exit 1; \
	echo "$$out" | grep -v '^PING_KEY='; \
	key=$$(echo "$$out" | sed -n 's/^PING_KEY=//p'); \
	if grep -q '^HEALTHCHECKS_PING_KEY=' .env; then sed -i "s/^HEALTHCHECKS_PING_KEY=.*/HEALTHCHECKS_PING_KEY=$$key/" .env; \
	else printf 'HEALTHCHECKS_PING_KEY=%s\n' "$$key" >> .env; fi; \
	echo "$(GREEN)Clé de ping enregistrée dans .env. Recréer restic pour l'utiliser : docker compose -f $(COMPOSE_FILE) -p $(PROJECT_NAME) up -d restic$(NC)"

dockge-sync: ## Expose les projets de PROJECTS_DIR à Dockge (liens en minuscules, idempotent)
	@PROJECTS_DIR="$(call env_value,PROJECTS_DIR)" ./scripts/dockge_sync_stacks.sh

registry-mirror: ## Branche le daemon Docker sur le cache d'images (sudo, sans redémarrage)
	@sudo ./scripts/enable_registry_mirror.sh

update-one: ## Met à jour un service sans passer par WUD (make update-one s=glance)
	@if [ -z "$(s)" ]; then echo "$(RED)Usage: make update-one s=<service>$(NC)"; exit 1; fi
	docker compose -f $(COMPOSE_FILE) -p $(PROJECT_NAME) pull $(s)
	docker compose -f $(COMPOSE_FILE) -p $(PROJECT_NAME) up -d $(s)

health: ## Vérifie la santé des services
	@echo "$(GREEN)Vérification de la santé des services:$(NC)"
	@docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(traefik|portainer|adminer|plumo|dozzle|mailer|mariadb|socket-proxy|dashboard|wud|cadvisor|node-exporter|prometheus|grafana|restic)"

# Sauvegardes (Restic)
RESTIC = docker compose -f $(COMPOSE_FILE) -p $(PROJECT_NAME) exec restic

backup-now: ## Lance une sauvegarde immédiate (MariaDB, Portainer, exports Oracle)
	$(RESTIC) /scripts/backup.sh

backup-snapshots: ## Liste les snapshots de sauvegarde
	$(RESTIC) restic snapshots

backup-check: ## Vérifie l'intégrité du dépôt de sauvegarde
	$(RESTIC) restic check

backup-restore-test: ## Restaure le dernier dump MariaDB dans une base jetable et le vérifie (db=<base>)
	$(RESTIC) /scripts/restore-test.sh $(db)

backup-oracle: ## Exporte Oracle (Data Pump) puis lance une sauvegarde
	@echo "$(YELLOW)Export Data Pump d'Oracle...$(NC)"
	docker exec oracle bash -c 'expdp system/"$$ORACLE_PASSWORD"@XEPDB1 FULL=Y DIRECTORY=DATA_PUMP_DIR DUMPFILE=full_%U.dmp LOGFILE=full.log REUSE_DUMPFILES=Y'
	@mkdir -p mnt/restic/dumps
	@rm -rf mnt/restic/dumps/*
	docker cp oracle:/opt/oracle/admin/XE/dpdump/. mnt/restic/dumps/
	@$(MAKE) backup-now