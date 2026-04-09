## ══════════════════════════════════════════════════════════════════════════════
## KHIDMETI BACKEND — Makefile (POSIX — Linux / macOS / WSL / GitHub Codespaces)
##
## Works on any POSIX shell environment: Linux, macOS, WSL, GitHub Codespaces.
## Windows native CMD/PowerShell: use WSL or Git Bash.
##
## ══════════════════════════════════════════════════════════════════════════════

SHELL := /bin/bash

## ── OS + tool detection ───────────────────────────────────────────────────────
OS   := $(shell uname -s 2>/dev/null || echo Windows_NT)

ifeq ($(OS),Darwin)
  OPEN_CMD := open
else ifeq ($(OS),Windows_NT)
  OPEN_CMD := start
else
  ## Linux / Codespaces / WSL — xdg-open may not be available in headless env
  OPEN_CMD := $(shell command -v xdg-open 2>/dev/null || echo "echo [URL] ")
endif

HOST     := $(shell hostname)
DATETIME := $(shell date +%Y%m%d-%H%M%S)

.DEFAULT_GOAL := help
.PHONY: help start stop restart build rebuild logs logs-api logs-mongo logs-redis \
        logs-qdrant logs-minio logs-nginx health status ai-status dns \
        ai-switch-gemini ai-switch-ollama ai-switch-vllm ollama-pull \
        minio-buckets minio-console minio-list \
        test-api test-ai test-upload firewall backup backup-mongo \
        restore list-backups shell-api shell-mongo shell-redis shell-minio \
        shell-qdrant mongo-stats redis-info redis-flush clean-logs clean \
        prod-start prod-update

## ══════════════════════════════════════════════════════════════════════════════
## AIDE
## ══════════════════════════════════════════════════════════════════════════════

help: ## Afficher l'aide
	@echo ""
	@echo "══════════════════════════════════════════════"
	@echo "  KHIDMETI - Commandes disponibles"
	@echo "══════════════════════════════════════════════"
	@echo ""
	@echo "  [SERVICES]"
	@echo "  start              Demarrer tous les services (AI=gemini par defaut)"
	@echo "  start-local        Demarrer avec Ollama (16GB RAM requis)"
	@echo "  start-gpu          Demarrer avec vLLM  (GPU NVIDIA requis)"
	@echo "  stop               Arreter tous les services"
	@echo "  restart            Redemarrer tous les services"
	@echo "  build              Builder l'image NestJS"
	@echo "  rebuild            Rebuild + redemarrer"
	@echo ""
	@echo "  [LOGS]"
	@echo "  logs               Tous les logs en temps reel"
	@echo "  logs-api           Logs NestJS uniquement"
	@echo "  logs-mongo         Logs MongoDB uniquement"
	@echo "  logs-redis         Logs Redis uniquement"
	@echo "  logs-qdrant        Logs Qdrant uniquement"
	@echo "  logs-minio         Logs MinIO uniquement"
	@echo "  logs-nginx         Logs nginx uniquement"
	@echo ""
	@echo "  [DIAGNOSTIC]"
	@echo "  health             Verifier la sante de tous les services"
	@echo "  status             Statut des conteneurs Docker"
	@echo "  ai-status          Afficher le provider AI actif"
	@echo "  dns                Afficher les URLs et la config reseau"
	@echo ""
	@echo "  [IA]"
	@echo "  ai-switch-gemini   Basculer sur Gemini API (defaut, internet)"
	@echo "  ai-switch-ollama   Basculer sur Ollama   (local, 16GB RAM)"
	@echo "  ai-switch-vllm     Basculer sur vLLM     (GPU, 16GB VRAM)"
	@echo "  ollama-pull        Telecharger les modeles Ollama"
	@echo ""
	@echo "  [MINIO]"
	@echo "  minio-buckets      Creer les buckets MinIO manuellement"
	@echo "  minio-console      Ouvrir la console MinIO dans le navigateur"
	@echo ""
	@echo "  [TESTS]"
	@echo "  test-api           Tester les endpoints principaux"
	@echo "  test-ai            Tester l'extraction d'intention IA"
	@echo "  test-upload        Tester l'upload d'image"
	@echo ""
	@echo "  [SAUVEGARDE]"
	@echo "  backup             Sauvegarder MongoDB + MinIO"
	@echo "  restore            Restaurer (BACKUP_DATE=YYYYMMDD-HHMMSS)"
	@echo ""
	@echo "  [DEBUG]"
	@echo "  shell-api          Shell dans le conteneur NestJS"
	@echo "  shell-mongo        mongosh dans MongoDB"
	@echo "  shell-redis        redis-cli dans Redis"
	@echo "  shell-minio        mc (MinIO client) dans le conteneur minio-init"
	@echo ""
	@echo "  [NETTOYAGE]"
	@echo "  clean              Supprimer volumes + donnees (destructif!)"
	@echo "  clean-logs         Vider les logs uniquement"
	@echo ""

## ══════════════════════════════════════════════════════════════════════════════
## GESTION DES SERVICES
## ══════════════════════════════════════════════════════════════════════════════

start: ## Demarrer (AI_PROVIDER=gemini par defaut)
	@echo ""
	@echo "══════════════════════════════════════════════"
	@echo "  Demarrage de Khidmeti Backend..."
	@echo "══════════════════════════════════════════════"
	@mkdir -p logs backups/mongodb backups/minio data/mongodb data/redis data/qdrant data/minio
	@if [ ! -f .env ]; then \
		cp .env.example .env; \
		echo "⚠️  ATTENTION: .env cree depuis .env.example — configurez-le!"; \
	fi
	@docker compose up -d
	@echo ""
	@echo "  Attente du demarrage des services (15s)..."
	@sleep 15
	@$(MAKE) health
	@echo ""
	@$(MAKE) dns

start-local: ## Demarrer avec Ollama (16GB RAM requis)
	@echo ""
	@echo "══════════════════════════════════════════════"
	@echo "  Demarrage avec Ollama (AI local)..."
	@echo "  Requis: 16GB RAM minimum"
	@echo "══════════════════════════════════════════════"
	@docker compose -f docker-compose.yml -f docker-compose.local.yml up -d
	@echo "  Telechargement des modeles Ollama..."
	@sleep 20
	@$(MAKE) ollama-pull
	@$(MAKE) health

start-gpu: ## Demarrer avec vLLM (GPU NVIDIA requis)
	@echo ""
	@echo "══════════════════════════════════════════════"
	@echo "  Demarrage avec vLLM (GPU)..."
	@echo "  Requis: GPU NVIDIA 16GB VRAM + HF_TOKEN dans .env"
	@echo "══════════════════════════════════════════════"
	@docker compose -f docker-compose.yml -f docker-compose.gpu.yml up -d
	@$(MAKE) health

stop: ## Arreter tous les services
	@echo "Arret de Khidmeti..."
	@docker compose down
	@echo "✅ Services arretes."

stop-local: ## Arreter le stack Ollama
	@docker compose -f docker-compose.yml -f docker-compose.local.yml down

stop-gpu: ## Arreter le stack vLLM
	@docker compose -f docker-compose.yml -f docker-compose.gpu.yml down

restart: stop ## Redemarrer
	@sleep 3
	@$(MAKE) start

build: ## Builder l'image NestJS
	@echo "Build de l'image API..."
	@docker compose build --no-cache api
	@echo "✅ Build termine."

rebuild: build start ## Rebuild complet + redemarrage

## ══════════════════════════════════════════════════════════════════════════════
## LOGS
## ══════════════════════════════════════════════════════════════════════════════

logs: ## Tous les logs
	@docker compose logs --tail=100 -f

logs-api: ## Logs NestJS
	@docker compose logs -f api

logs-mongo: ## Logs MongoDB
	@docker compose logs -f mongo

logs-redis: ## Logs Redis
	@docker compose logs -f redis

logs-qdrant: ## Logs Qdrant
	@docker compose logs -f qdrant

logs-minio: ## Logs MinIO
	@docker compose logs -f minio

logs-nginx: ## Logs nginx
	@docker compose logs -f nginx

## ══════════════════════════════════════════════════════════════════════════════
## DIAGNOSTIC
## ══════════════════════════════════════════════════════════════════════════════

health: ## Verifier la sante de tous les services
	@echo ""
	@echo "══════════════════════════════════════════════"
	@echo "  Etat des services Khidmeti"
	@echo "══════════════════════════════════════════════"
	@echo ""
	@echo -n "  NestJS API  (port 3000) : "; \
	  code=$$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/health 2>/dev/null); \
	  [ "$$code" = "200" ] && echo "✅ OK (HTTP $$code)" || echo "❌ HORS LIGNE (HTTP $$code)"
	@echo -n "  nginx       (port 80)   : "; \
	  code=$$(curl -s -o /dev/null -w "%{http_code}" http://localhost/health 2>/dev/null); \
	  [ "$$code" = "200" ] && echo "✅ OK (HTTP $$code)" || echo "❌ HORS LIGNE (HTTP $$code)"
	@echo -n "  MongoDB     (port 27017): "; \
	  docker exec khidmeti-mongo mongosh --quiet --eval "db.adminCommand('ping').ok" >/dev/null 2>&1 \
	  && echo "✅ OK" || echo "❌ HORS LIGNE"
	@echo -n "  Redis       (port 6379) : "; \
	  docker exec khidmeti-redis redis-cli -a "$$(grep REDIS_PASSWORD .env | cut -d= -f2)" ping >/dev/null 2>&1 \
	  && echo "✅ OK" || echo "❌ HORS LIGNE"
	@echo -n "  Qdrant      (port 6333) : "; \
	  code=$$(curl -s -o /dev/null -w "%{http_code}" http://localhost:6333/healthz 2>/dev/null); \
	  [ "$$code" = "200" ] && echo "✅ OK (HTTP $$code)" || echo "❌ HORS LIGNE (HTTP $$code)"
	@echo -n "  MinIO API   (port 9001) : "; \
	  code=$$(curl -s -o /dev/null -w "%{http_code}" http://localhost:9001/minio/health/live 2>/dev/null); \
	  [ "$$code" = "200" ] && echo "✅ OK (HTTP $$code)" || echo "❌ HORS LIGNE (HTTP $$code)"
	@echo -n "  MinIO UI    (port 9002) : "; \
	  code=$$(curl -s -o /dev/null -w "%{http_code}" http://localhost:9002 2>/dev/null); \
	  [ "$$code" != "" ] && echo "✅ OK (HTTP $$code)" || echo "❌ HORS LIGNE"
	@echo ""

status: ## Statut des conteneurs
	@echo ""
	@docker ps -a --filter "name=khidmeti" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
	@echo ""

ai-status: ## Afficher le provider AI actif
	@echo ""
	@echo "══════════════════════════════════════════════"
	@echo "  Provider IA actif"
	@echo "══════════════════════════════════════════════"
	@docker exec khidmeti-api printenv AI_PROVIDER 2>/dev/null || echo "  (conteneur non demarre)"
	@echo ""

dns: ## Afficher les URLs
	@echo ""
	@echo "══════════════════════════════════════════════"
	@echo "  URLs des services Khidmeti  [host: $(HOST)]"
	@echo "══════════════════════════════════════════════"
	@echo ""
	@echo "  API REST:          http://$(HOST):3000"
	@echo "  API via nginx:     http://$(HOST):80"
	@echo "  Swagger docs:      http://$(HOST):3000/api/docs"
	@echo "  Qdrant dashboard:  http://$(HOST):6333/dashboard"
	@echo "  MinIO console:     http://$(HOST):9002"
	@echo "  MinIO API (S3):    http://$(HOST):9001"
	@echo ""
	@echo "══════════════════════════════════════════════"
	@echo "  Config Flutter"
	@echo "══════════════════════════════════════════════"
	@echo ""
	@echo "  API_BASE_URL=http://$(HOST):80"
	@echo ""

## ══════════════════════════════════════════════════════════════════════════════
## GESTION DE L'IA
## ══════════════════════════════════════════════════════════════════════════════

ai-switch-gemini: ## Basculer sur Gemini
	@echo "Bascule vers Gemini API..."
	@sed -i 's/^AI_PROVIDER=.*/AI_PROVIDER=gemini/' .env
	@docker compose up -d --no-deps api
	@echo "✅ Provider IA: GEMINI"

ai-switch-ollama: ## Basculer sur Ollama
	@echo "Bascule vers Ollama..."
	@sed -i 's/^AI_PROVIDER=.*/AI_PROVIDER=ollama/' .env
	@docker compose -f docker-compose.yml -f docker-compose.local.yml up -d
	@echo "✅ Provider IA: OLLAMA"

ai-switch-vllm: ## Basculer sur vLLM
	@echo "Bascule vers vLLM..."
	@sed -i 's/^AI_PROVIDER=.*/AI_PROVIDER=vllm/' .env
	@docker compose -f docker-compose.yml -f docker-compose.gpu.yml up -d
	@echo "✅ Provider IA: VLLM"

ollama-pull: ## Telecharger les modeles Ollama
	@echo "Telechargement des modeles Ollama..."
	@docker exec khidmeti-ollama ollama pull gemma4:e2b
	@docker exec khidmeti-ollama ollama pull nomic-embed-text
	@echo "✅ Modeles telecharges."

## ══════════════════════════════════════════════════════════════════════════════
## MINIO
## ══════════════════════════════════════════════════════════════════════════════

minio-buckets: ## Creer les buckets MinIO manuellement
	@echo "Creation des buckets MinIO..."
	@MINIO_ACCESS_KEY=$$(grep MINIO_ACCESS_KEY .env | cut -d= -f2); \
	MINIO_SECRET_KEY=$$(grep MINIO_SECRET_KEY .env | cut -d= -f2); \
	docker exec khidmeti-minio-init /bin/sh -c "\
		mc alias set local http://minio:9001 $$MINIO_ACCESS_KEY $$MINIO_SECRET_KEY; \
		mc mb --ignore-existing local/profile-images; \
		mc mb --ignore-existing local/service-media; \
		mc mb --ignore-existing local/audio-recordings; \
		mc anonymous set download local/profile-images; \
		echo Buckets OK"
	@echo "✅ Buckets MinIO crees."

minio-console: ## Ouvrir la console MinIO
	@$(OPEN_CMD) http://localhost:9002 2>/dev/null || echo "  → http://localhost:9002"

minio-list: ## Lister tous les fichiers dans les buckets
	@MINIO_ACCESS_KEY=$$(grep MINIO_ACCESS_KEY .env | cut -d= -f2); \
	MINIO_SECRET_KEY=$$(grep MINIO_SECRET_KEY .env | cut -d= -f2); \
	echo ""; \
	echo "Bucket: profile-images"; \
	docker run --rm --network khidmeti-network minio/mc:latest \
		sh -c "mc alias set local http://minio:9001 $$MINIO_ACCESS_KEY $$MINIO_SECRET_KEY && mc ls local/profile-images"; \
	echo ""; \
	echo "Bucket: service-media"; \
	docker run --rm --network khidmeti-network minio/mc:latest \
		sh -c "mc alias set local http://minio:9001 $$MINIO_ACCESS_KEY $$MINIO_SECRET_KEY && mc ls local/service-media"

## ══════════════════════════════════════════════════════════════════════════════
## TESTS API
## ══════════════════════════════════════════════════════════════════════════════

test-api: ## Tester les endpoints principaux
	@echo ""
	@echo "══════════════════════════════════════════════"
	@echo "  Tests API Khidmeti"
	@echo "══════════════════════════════════════════════"
	@echo ""
	@echo -n "  [1] Health check: "; \
	  curl -s http://localhost:3000/health && echo ""
	@echo -n "  [2] Swagger disponible (HTTP): "; \
	  curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/api/docs && echo ""
	@echo -n "  [3] /workers endpoint (HTTP): "; \
	  curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/workers && echo ""
	@echo ""
	@echo "  NOTE: La plupart des endpoints requierent un token Firebase Bearer."
	@echo "  Swagger UI: http://localhost:3000/api/docs"
	@echo ""

test-ai: ## Tester l'extraction d'intention IA
	@echo ""
	@echo "Test de l'extraction IA..."
	@echo "Usage: make test-ai TOKEN=xxx"
	@echo ""
	@if [ -z "$(TOKEN)" ]; then \
		echo "ERREUR: TOKEN non defini."; \
	else \
		curl -s -X POST http://localhost:3000/ai/extract-intent \
		  -H "Authorization: Bearer $(TOKEN)" \
		  -H "Content-Type: application/json" \
		  -d '{"text": "j ai une fuite d eau sous l evier"}'; \
	fi
	@echo ""

test-upload: ## Tester l'upload d'image
	@echo ""
	@echo "Test upload image vers MinIO..."
	@echo "Usage: make test-upload TOKEN=xxx FILE=/chemin/image.jpg"
	@echo ""
	@if [ -z "$(TOKEN)" ] || [ -z "$(FILE)" ]; then \
		echo "ERREUR: TOKEN et FILE requis."; \
	else \
		curl -s -X POST http://localhost:3000/media/upload/image \
		  -H "Authorization: Bearer $(TOKEN)" \
		  -F "file=@$(FILE)"; \
	fi
	@echo ""

## ══════════════════════════════════════════════════════════════════════════════
## PARE-FEU (Linux: ufw | macOS: pfctl | Codespaces: no-op)
## ══════════════════════════════════════════════════════════════════════════════

firewall: ## Afficher les commandes pare-feu pour votre OS
	@echo ""
	@echo "══════════════════════════════════════════════"
	@echo "  Configuration Pare-feu"
	@echo "  OS detecte: $(OS)"
	@echo "══════════════════════════════════════════════"
	@echo ""
ifeq ($(OS),Linux)
	@echo "  # Ubuntu/Debian (ufw):"
	@echo "  sudo ufw allow 3000/tcp   # API NestJS"
	@echo "  sudo ufw allow 80/tcp     # nginx"
	@echo "  sudo ufw allow 6333/tcp   # Qdrant"
	@echo "  sudo ufw allow 9001/tcp   # MinIO API"
	@echo "  sudo ufw allow 9002/tcp   # MinIO Console"
	@echo "  sudo ufw allow 27017/tcp  # MongoDB"
	@echo ""
	@echo "  # RHEL/CentOS (firewalld):"
	@echo "  sudo firewall-cmd --permanent --add-port=3000/tcp"
	@echo "  sudo firewall-cmd --permanent --add-port=80/tcp"
	@echo "  sudo firewall-cmd --permanent --add-port=6333/tcp"
	@echo "  sudo firewall-cmd --permanent --add-port=9001/tcp"
	@echo "  sudo firewall-cmd --permanent --add-port=9002/tcp"
	@echo "  sudo firewall-cmd --reload"
else ifeq ($(OS),Darwin)
	@echo "  # macOS: Docker Desktop expose les ports automatiquement."
	@echo "  # Aucune configuration pare-feu requise."
else
	@echo "  # Codespaces/WSL: utilisez l'onglet PORTS dans VS Code"
	@echo "  # pour forwarder les ports 3000, 80, 6333, 9001, 9002."
endif
	@echo ""

## ══════════════════════════════════════════════════════════════════════════════
## SAUVEGARDE ET RESTAURATION
## ══════════════════════════════════════════════════════════════════════════════

backup: ## Sauvegarder MongoDB + MinIO
	@echo ""
	@echo "══════════════════════════════════════════════"
	@echo "  Sauvegarde Khidmeti — $(DATETIME)"
	@echo "══════════════════════════════════════════════"
	@mkdir -p backups/mongodb/$(DATETIME) backups/minio/$(DATETIME)
	@MONGO_USER=$$(grep MONGO_ROOT_USER .env | cut -d= -f2); \
	MONGO_PASS=$$(grep MONGO_ROOT_PASSWORD .env | cut -d= -f2); \
	echo "  [1/2] Sauvegarde MongoDB..."; \
	docker exec khidmeti-mongo mongodump \
	  --username "$$MONGO_USER" --password "$$MONGO_PASS" \
	  --authenticationDatabase admin --db khidmeti \
	  --out /tmp/backup_$(DATETIME); \
	docker cp khidmeti-mongo:/tmp/backup_$(DATETIME) backups/mongodb/$(DATETIME); \
	echo "  ✅ MongoDB → backups/mongodb/$(DATETIME)"
	@MINIO_KEY=$$(grep MINIO_ACCESS_KEY .env | cut -d= -f2); \
	MINIO_SECRET=$$(grep MINIO_SECRET_KEY .env | cut -d= -f2); \
	echo "  [2/2] Sauvegarde MinIO..."; \
	docker run --rm --network khidmeti-network \
	  -v "$$(pwd)/backups/minio/$(DATETIME):/backup" minio/mc:latest \
	  sh -c "mc alias set local http://minio:9001 $$MINIO_KEY $$MINIO_SECRET \
	    && mc mirror local/profile-images /backup/profile-images \
	    && mc mirror local/service-media   /backup/service-media"; \
	echo "  ✅ MinIO → backups/minio/$(DATETIME)"
	@echo ""
	@echo "  Sauvegarde complete: $(DATETIME)"

backup-mongo: ## Sauvegarder MongoDB uniquement
	@mkdir -p backups/mongodb/$(DATETIME)
	@MONGO_USER=$$(grep MONGO_ROOT_USER .env | cut -d= -f2); \
	MONGO_PASS=$$(grep MONGO_ROOT_PASSWORD .env | cut -d= -f2); \
	docker exec khidmeti-mongo mongodump \
	  --username "$$MONGO_USER" --password "$$MONGO_PASS" \
	  --authenticationDatabase admin --db khidmeti \
	  --out /tmp/backup_$(DATETIME); \
	docker cp khidmeti-mongo:/tmp/backup_$(DATETIME) backups/mongodb/$(DATETIME); \
	echo "✅ MongoDB sauvegarde: backups/mongodb/$(DATETIME)"

restore: ## Restaurer MongoDB (BACKUP_DATE=YYYYMMDD-HHMMSS)
	@if [ -z "$(BACKUP_DATE)" ]; then \
		echo "ERREUR: BACKUP_DATE non defini."; \
		echo "Usage: make restore BACKUP_DATE=20250101-120000"; \
		echo ""; \
		echo "Sauvegardes disponibles:"; \
		ls backups/mongodb/ 2>/dev/null || echo "  (aucune)"; \
		exit 1; \
	fi
	@echo "Restauration depuis backups/mongodb/$(BACKUP_DATE)..."
	@MONGO_USER=$$(grep MONGO_ROOT_USER .env | cut -d= -f2); \
	MONGO_PASS=$$(grep MONGO_ROOT_PASSWORD .env | cut -d= -f2); \
	docker cp backups/mongodb/$(BACKUP_DATE) khidmeti-mongo:/tmp/restore_$(BACKUP_DATE); \
	docker exec khidmeti-mongo mongorestore \
	  --username "$$MONGO_USER" --password "$$MONGO_PASS" \
	  --authenticationDatabase admin --db khidmeti --drop \
	  /tmp/restore_$(BACKUP_DATE)/khidmeti
	@echo "✅ Restauration terminee."

list-backups: ## Lister les sauvegardes disponibles
	@echo ""
	@echo "Sauvegardes MongoDB:"
	@ls backups/mongodb/ 2>/dev/null || echo "  (aucune)"
	@echo ""
	@echo "Sauvegardes MinIO:"
	@ls backups/minio/ 2>/dev/null || echo "  (aucune)"
	@echo ""

## ══════════════════════════════════════════════════════════════════════════════
## SHELL ET DEBUG
## ══════════════════════════════════════════════════════════════════════════════

shell-api: ## Shell dans le conteneur NestJS
	@docker exec -it khidmeti-api /bin/sh

shell-mongo: ## mongosh dans MongoDB
	@MONGO_USER=$$(grep MONGO_ROOT_USER .env | cut -d= -f2); \
	MONGO_PASS=$$(grep MONGO_ROOT_PASSWORD .env | cut -d= -f2); \
	docker exec -it khidmeti-mongo mongosh -u "$$MONGO_USER" -p "$$MONGO_PASS" \
	  --authenticationDatabase admin khidmeti

shell-redis: ## redis-cli dans Redis
	@REDIS_PASS=$$(grep REDIS_PASSWORD .env | cut -d= -f2); \
	docker exec -it khidmeti-redis redis-cli -a "$$REDIS_PASS"

shell-minio: ## mc client MinIO
	@MINIO_KEY=$$(grep MINIO_ACCESS_KEY .env | cut -d= -f2); \
	MINIO_SECRET=$$(grep MINIO_SECRET_KEY .env | cut -d= -f2); \
	docker run -it --rm --network khidmeti-network minio/mc:latest \
	  sh -c "mc alias set local http://minio:9001 $$MINIO_KEY $$MINIO_SECRET && sh"

shell-qdrant: ## Ouvrir le dashboard Qdrant
	@$(OPEN_CMD) http://localhost:6333/dashboard 2>/dev/null || echo "  → http://localhost:6333/dashboard"

mongo-stats: ## Statistiques MongoDB
	@echo ""
	@MONGO_USER=$$(grep MONGO_ROOT_USER .env | cut -d= -f2); \
	MONGO_PASS=$$(grep MONGO_ROOT_PASSWORD .env | cut -d= -f2); \
	docker exec khidmeti-mongo mongosh -u "$$MONGO_USER" -p "$$MONGO_PASS" \
	  --authenticationDatabase admin khidmeti --quiet --eval "db.stats()"

redis-info: ## Informations Redis
	@echo ""
	@REDIS_PASS=$$(grep REDIS_PASSWORD .env | cut -d= -f2); \
	docker exec khidmeti-redis redis-cli -a "$$REDIS_PASS" INFO server
	@echo ""
	@echo "  Cles en cache:"
	@REDIS_PASS=$$(grep REDIS_PASSWORD .env | cut -d= -f2); \
	docker exec khidmeti-redis redis-cli -a "$$REDIS_PASS" DBSIZE

redis-flush: ## Vider le cache Redis
	@echo "Vidage du cache Redis..."
	@REDIS_PASS=$$(grep REDIS_PASSWORD .env | cut -d= -f2); \
	docker exec khidmeti-redis redis-cli -a "$$REDIS_PASS" FLUSHALL
	@echo "✅ Cache Redis vide."

## ══════════════════════════════════════════════════════════════════════════════
## NETTOYAGE
## ══════════════════════════════════════════════════════════════════════════════

clean-logs: ## Vider les fichiers de logs
	@echo "Nettoyage des logs..."
	@find logs/ -name "*.log" -delete 2>/dev/null || true
	@echo "✅ Logs nettoyes."

clean: ## Supprimer volumes et donnees (DESTRUCTIF)
	@echo ""
	@echo "══════════════════════════════════════════════"
	@echo "  ⚠️  ATTENTION - OPERATION DESTRUCTIVE"
	@echo "  Ceci va supprimer TOUTES les donnees:"
	@echo "  MongoDB, Redis, Qdrant, MinIO"
	@echo "══════════════════════════════════════════════"
	@echo ""
	@read -p "Confirmer la suppression? [y/N] " CONFIRM; \
	if [ "$$CONFIRM" = "y" ] || [ "$$CONFIRM" = "Y" ]; then \
		docker compose down -v --remove-orphans; \
		docker system prune -f; \
		rm -rf data/mongodb data/redis data/qdrant data/minio; \
		echo "✅ Nettoyage termine."; \
	else \
		echo "Annule."; \
	fi

## ══════════════════════════════════════════════════════════════════════════════
## PRODUCTION
## ══════════════════════════════════════════════════════════════════════════════

prod-start: ## Demarrer en mode production
	@echo "Demarrage production..."
	@docker compose up -d
	@echo "✅ Mode production actif."

prod-update: ## Mettre a jour l'API sans downtime
	@echo "Mise a jour de l'API..."
	@docker compose build --no-cache api
	@docker compose up -d --no-deps --build api
	@echo "✅ API mise a jour."
