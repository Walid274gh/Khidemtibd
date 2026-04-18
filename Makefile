## ══════════════════════════════════════════════════════════════════════════════
## KHIDMETI BACKEND — Makefile
## ══════════════════════════════════════════════════════════════════════════════

SHELL := /bin/bash

OS   := $(shell uname -s 2>/dev/null || echo Windows_NT)
ARCH := $(shell uname -m 2>/dev/null || echo unknown)

ifeq ($(OS),Darwin)
  OPEN_CMD := open
else ifeq ($(OS),Windows_NT)
  OPEN_CMD := start
else
  OPEN_CMD := $(shell command -v xdg-open 2>/dev/null || echo "echo 🔗 Ouvrez manuellement : ")
endif

SED_I := $(shell \
  if sed --version 2>/dev/null | grep -q GNU; then \
    echo "sed -i"; \
  else \
    echo "sed -i ''"; \
  fi)

LOCAL_IP := $(shell \
  ip route get 1 2>/dev/null | awk '{print $$7; exit}' || \
  ifconfig 2>/dev/null | awk '/inet /{print $$2}' | grep -v 127.0.0.1 | head -1 || \
  hostname -I 2>/dev/null | awk '{print $$1}' || \
  echo "127.0.0.1")

HOST     := $(shell hostname)
DATETIME := $(shell date +%Y%m%d-%H%M%S)

## Paramètre optionnel transmis aux scripts (ex: ARGS=--clear)
ARGS ?=

.DEFAULT_GOAL := help
.PHONY: help start start-local start-gpu stop restart build rebuild logs logs-api \
        logs-mongo logs-redis logs-qdrant logs-minio logs-nginx logs-mongo-ui \
        health status ai-status dns ai-switch-openrouter ai-switch-gemini \
        ai-switch-ollama ai-switch-vllm ollama-pull \
        minio-buckets minio-console minio-list test-api test-ai test-upload \
        firewall backup backup-mongo restore list-backups shell-api shell-mongo \
        shell-redis shell-minio shell-qdrant mongo-stats redis-info redis-flush \
        clean-logs clean prod-start prod-update \
        tunnel-install tunnel-quick tunnel-stop tunnel-status flutter-run \
        ngrok ngrok-install ngrok-reset \
        scripts scripts-migrations scripts-seeds

## ══════════════════════════════════════════════════════════════════════════════
## AIDE
## ══════════════════════════════════════════════════════════════════════════════

help: ## Afficher l'aide
	@echo ""
	@echo "══════════════════════════════════════════════"
	@echo "  KHIDMETI — Commandes disponibles"
	@echo "  OS : $(OS) | Architecture : $(ARCH)"
	@echo "══════════════════════════════════════════════"
	@echo ""
	@echo "  [SERVICES]"
	@echo "  start              Démarrer (AI_PROVIDER=openrouter par défaut)"
	@echo "  start-local        Démarrer avec Ollama (16 Go RAM requis)"
	@echo "  start-gpu          Démarrer avec vLLM (GPU NVIDIA requis)"
	@echo "  stop               Arrêter tous les services"
	@echo "  restart            Redémarrer tous les services"
	@echo "  build              Builder l'image NestJS"
	@echo "  rebuild            Rebuild + redémarrage"
	@echo ""
	@echo "  [LOGS]"
	@echo "  logs               Tous les logs"
	@echo "  logs-api           Logs NestJS"
	@echo "  logs-mongo         Logs MongoDB"
	@echo "  logs-mongo-ui      Logs Mongo Express (interface web)"
	@echo "  logs-redis         Logs Redis"
	@echo "  logs-qdrant        Logs Qdrant"
	@echo "  logs-minio         Logs MinIO"
	@echo "  logs-nginx         Logs nginx"
	@echo ""
	@echo "  [DIAGNOSTIC]"
	@echo "  health             Vérifier la santé des services"
	@echo "  status             Statut des conteneurs Docker"
	@echo "  ai-status          Fournisseur IA actif"
	@echo "  dns                URLs + config Flutter"
	@echo ""
	@echo "  [TUNNEL — Codespaces / WiFi distant]"
	@echo "  tunnel-quick       Quick Tunnel Cloudflare (URL aléatoire)"
	@echo "  tunnel-install     Installer cloudflared"
	@echo "  tunnel-stop        Arrêter le tunnel Cloudflare"
	@echo "  ngrok              Tunnel ngrok domaine PERMANENT (recommandé)"
	@echo "  ngrok-install      Installer ngrok"
	@echo "  ngrok-reset        Réinitialiser token/domaine ngrok"
	@echo "  flutter-run        Lancer Flutter avec l'IP locale"
	@echo ""
	@echo "  [IA]"
	@echo "  ai-switch-openrouter  Basculer sur OpenRouter (Gemma 4 gratuit)"
	@echo "  ai-switch-gemini      Basculer sur Google Gemini API"
	@echo "  ai-switch-ollama      Basculer sur Ollama (local)"
	@echo "  ai-switch-vllm        Basculer sur vLLM (GPU)"
	@echo "  ollama-pull           Télécharger les modèles Ollama"
	@echo ""
	@echo "  [SCRIPTS — Migrations + Seeds]"
	@echo "  scripts                     Exécuter TOUTES migrations + seeds"
	@echo "  scripts-migrations          Exécuter toutes les migrations"
	@echo "  scripts-seeds               Exécuter tous les seeds"
	@echo "  scripts-<nom>               Exécuter UN script précis"
	@echo "  scripts-seed-workers        Seed workers test Oran"
	@echo "  scripts-seed-workers ARGS=--clear   Re-seed propre"
	@echo "  scripts-001_phone_auth_indexes      Migration index auth"
	@echo ""
	@echo "  ── Structure attendue :"
	@echo "     scripts/migrations/*.js          → mongosh (MongoDB)"
	@echo "     apps/api/src/scripts/seeds/*.ts  → ts-node (NestJS container)"
	@echo ""
	@echo "  [MINIO]"
	@echo "  minio-buckets      Recréer les buckets MinIO"
	@echo "  minio-console      Ouvrir la console MinIO (port 9002)"
	@echo ""
	@echo "  [TESTS]"
	@echo "  test-api           Tester les endpoints principaux"
	@echo "  test-ai            Tester l'extraction d'intention IA"
	@echo ""
	@echo "  [SAUVEGARDE]"
	@echo "  backup             Sauvegarder MongoDB + MinIO"
	@echo "  restore            Restaurer (BACKUP_DATE=YYYYMMDD-HHMMSS)"
	@echo ""
	@echo "  [DEBUG]"
	@echo "  shell-api          Shell dans le conteneur NestJS"
	@echo "  shell-mongo        mongosh dans MongoDB"
	@echo "  shell-redis        redis-cli dans Redis"
	@echo "  shell-minio        mc (client MinIO)"
	@echo ""
	@echo "  [NETTOYAGE]"
	@echo "  clean              Supprimer volumes + données (destructif !)"
	@echo "  clean-logs         Vider les logs"
	@echo ""
	@echo "  Windows : scripts\\khidmeti.bat  ou  scripts\\khidmeti.ps1"
	@echo ""

## ══════════════════════════════════════════════════════════════════════════════
## GESTION DES SERVICES
## ══════════════════════════════════════════════════════════════════════════════

start: ## Démarrer (AI_PROVIDER défini dans .env)
	@echo ""
	@echo "══════════════════════════════════════════════"
	@echo "  Démarrage de Khidmeti Backend..."
	@echo "══════════════════════════════════════════════"
	@mkdir -p logs backups/mongodb backups/minio data/mongodb data/redis data/qdrant data/minio
	@if [ ! -f .env ]; then \
		cp .env.example .env 2>/dev/null || true; \
		echo "⚠️  ATTENTION : .env créé — configurez FIREBASE_* et vos clés IA"; \
	fi
	@docker compose up -d
	@echo ""
	@echo "  Attente du démarrage des services (20s)..."
	@sleep 20
	@$(MAKE) health
	@echo ""
	@$(MAKE) dns

start-local: ## Démarrer avec Ollama (16 Go RAM requis)
	@echo "Démarrage avec Ollama (IA locale)..."
	@docker compose -f docker-compose.yml -f docker-compose.local.yml up -d
	@sleep 20
	@$(MAKE) ollama-pull
	@$(MAKE) health

start-gpu: ## Démarrer avec vLLM (GPU NVIDIA requis)
	@echo "Démarrage avec vLLM (GPU)..."
	@docker compose -f docker-compose.yml -f docker-compose.gpu.yml up -d
	@$(MAKE) health

stop: ## Arrêter tous les services
	@docker compose down
	@echo "✅ Services arrêtés."

stop-local:
	@docker compose -f docker-compose.yml -f docker-compose.local.yml down

stop-gpu:
	@docker compose -f docker-compose.yml -f docker-compose.gpu.yml down

restart: stop ## Redémarrer
	@sleep 3
	@$(MAKE) start

build: ## Builder l'image NestJS
	@docker compose build --no-cache api
	@echo "✅ Build terminé."

rebuild: build start ## Rebuild complet + redémarrage

## ══════════════════════════════════════════════════════════════════════════════
## LOGS
## ══════════════════════════════════════════════════════════════════════════════

logs: ## Tous les logs
	@docker compose logs --tail=100 -f

logs-api: ## Logs NestJS
	@docker compose logs -f api

logs-mongo: ## Logs MongoDB
	@docker compose logs -f mongo

logs-mongo-ui: ## Logs Mongo Express
	@docker compose logs -f mongo-express

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

health: ## Vérifier la santé des services
	@echo ""
	@echo "══════════════════════════════════════════════"
	@echo "  État des services Khidmeti"
	@echo "══════════════════════════════════════════════"
	@echo ""
	@echo -n "  NestJS API      (port 3000) : "; \
	  code=$$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/health 2>/dev/null); \
	  [ "$$code" = "200" ] && echo "✅ OK" || echo "❌ HORS LIGNE (HTTP $$code)"
	@echo -n "  nginx           (port 80)   : "; \
	  code=$$(curl -s -o /dev/null -w "%{http_code}" http://localhost/health 2>/dev/null); \
	  [ "$$code" = "200" ] && echo "✅ OK" || echo "❌ HORS LIGNE (HTTP $$code)"
	@echo -n "  MongoDB         (port 27017): "; \
	  docker exec khidmeti-mongo mongosh --quiet --eval "db.adminCommand('ping').ok" >/dev/null 2>&1 \
	  && echo "✅ OK" || echo "❌ HORS LIGNE"
	@echo -n "  Mongo Express   (port 8081) : "; \
	  code=$$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8081 2>/dev/null); \
	  [ "$$code" = "200" ] && echo "✅ OK  →  http://localhost:8081" || echo "❌ HORS LIGNE (HTTP $$code)"
	@echo -n "  Redis           (port 6379) : "; \
	  REDIS_PASS=$$(grep REDIS_PASSWORD .env | cut -d= -f2 | tr -d '[:space:]'); \
	  docker exec khidmeti-redis redis-cli -a "$$REDIS_PASS" ping >/dev/null 2>&1 \
	  && echo "✅ OK" || echo "❌ HORS LIGNE"
	@echo -n "  Qdrant          (port 6333) : "; \
	  code=$$(curl -s -o /dev/null -w "%{http_code}" http://localhost:6333/healthz 2>/dev/null); \
	  [ "$$code" = "200" ] && echo "✅ OK  →  http://localhost:6333/dashboard" || echo "❌ HORS LIGNE"
	@echo -n "  MinIO API       (port 9001) : "; \
	  code=$$(curl -s -o /dev/null -w "%{http_code}" http://localhost:9001/minio/health/live 2>/dev/null); \
	  [ "$$code" = "200" ] && echo "✅ OK  →  http://localhost:9002 (console)" || echo "❌ HORS LIGNE"
	@echo ""

status: ## Statut des conteneurs
	@docker ps -a --filter "name=khidmeti" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

ai-status: ## Fournisseur IA actif
	@echo -n "  AI_PROVIDER actif : "
	@docker exec khidmeti-api printenv AI_PROVIDER 2>/dev/null || echo "(conteneur non démarré)"

dns: ## Afficher les URLs + config Flutter
	@echo ""
	@echo "══════════════════════════════════════════════"
	@echo "  URLs des services  [hôte : $(HOST)]"
	@echo "══════════════════════════════════════════════"
	@echo ""
	@echo "  API REST       :  http://$(HOST):3000"
	@echo "  API via nginx  :  http://$(HOST):80"
	@echo "  Swagger docs   :  http://$(HOST):3000/api/docs"
	@echo "  Mongo Express  :  http://$(HOST):8081   ← Interface MongoDB"
	@echo "  Qdrant UI      :  http://$(HOST):6333/dashboard"
	@echo "  MinIO console  :  http://$(HOST):9002"
	@echo "  MinIO API (S3) :  http://$(HOST):9001"
	@echo ""
	@echo "══════════════════════════════════════════════"
	@echo "  Config Flutter (même WiFi)"
	@echo "══════════════════════════════════════════════"
	@echo ""
	@echo "  IP locale détectée : $(LOCAL_IP)"
	@echo ""
	@echo "  flutter run --dart-define=API_BASE_URL=http://$(LOCAL_IP):80"
	@echo ""
	@NGROK_DOMAIN=$$(grep '^NGROK_DOMAIN=' .env 2>/dev/null | cut -d= -f2- | tr -d '[:space:]' | tr -d '"'); \
	if [ -n "$$NGROK_DOMAIN" ]; then \
		echo "  Tunnel ngrok actif : https://$$NGROK_DOMAIN"; \
		echo "  flutter run --dart-define=API_BASE_URL=https://$$NGROK_DOMAIN"; \
		echo ""; \
	else \
		echo "  OU : collez l'URL Quick Tunnel dans Firebase Remote Config"; \
		echo "       clé : api_base_url"; \
		echo ""; \
	fi

## ══════════════════════════════════════════════════════════════════════════════
## TUNNEL CLOUDFLARE
## ══════════════════════════════════════════════════════════════════════════════

tunnel-install: ## Installer cloudflared
	@echo "Installation de cloudflared..."
	@if command -v cloudflared >/dev/null 2>&1; then \
		echo "✅ cloudflared déjà installé : $$(cloudflared --version)"; \
	elif [ -f /etc/debian_version ] || grep -qi ubuntu /etc/os-release 2>/dev/null; then \
		curl -L --output /tmp/cloudflared.deb \
		  https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb 2>/dev/null; \
		sudo dpkg -i /tmp/cloudflared.deb; \
		rm /tmp/cloudflared.deb; \
	else \
		curl -L -o /usr/local/bin/cloudflared \
		  https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64; \
		chmod +x /usr/local/bin/cloudflared; \
	fi
	@cloudflared --version || echo "⚠️  Relancez votre terminal."

tunnel-quick: ## Lancer un Quick Tunnel (URL aléatoire — change à chaque redémarrage)
	@echo ""
	@echo "  CTRL+C pour arrêter le tunnel."
	@echo "  💡 Pour un URL permanent : make ngrok"
	@echo ""
	@cloudflared tunnel --url http://localhost:80

tunnel-stop: ## Arrêter le tunnel Cloudflare
	@pkill -f 'cloudflared tunnel' 2>/dev/null && echo "✅ Tunnel(s) arrêté(s)." || echo "Aucun tunnel actif."

tunnel-status: ## État du tunnel Cloudflare
	@ps aux | grep 'cloudflared tunnel' | grep -v grep || echo "Aucun tunnel actif."

flutter-run: ## Lancer Flutter avec l'IP locale
	@flutter run --dart-define=API_BASE_URL=http://$(LOCAL_IP):80

## ══════════════════════════════════════════════════════════════════════════════
## TUNNEL NGROK — Domaine statique PERMANENT (recommandé)
##
##  Avantages vs Cloudflare Quick Tunnel :
##    ✅ URL identique à chaque redémarrage (ex: mon-app.ngrok-free.app)
##    ✅ Gratuit, sans carte bancaire (compte ngrok.com suffit)
##    ✅ Token + domaine sauvegardés dans .env → 1 seul mot à retaper
##
##  Première utilisation :
##    1. Créez un compte sur https://dashboard.ngrok.com/signup
##    2. Réservez un domaine sur https://dashboard.ngrok.com/domains
##    3. make ngrok  →  entrez token + domaine (1 seule fois)
##
##  Utilisations suivantes :
##    make ngrok  →  démarre directement
## ══════════════════════════════════════════════════════════════════════════════

ngrok-install: ## Installer ngrok (Linux / macOS / WSL)
	@echo "Installation de ngrok..."
	@if command -v ngrok >/dev/null 2>&1; then \
		echo "✅ ngrok déjà installé : $$(ngrok --version)"; \
	elif [ -f /etc/debian_version ] || grep -qi ubuntu /etc/os-release 2>/dev/null; then \
		curl -sSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc \
		  | sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null 2>&1; \
		echo "deb https://ngrok-agent.s3.amazonaws.com buster main" \
		  | sudo tee /etc/apt/sources.list.d/ngrok.list >/dev/null; \
		sudo apt-get update -qq && sudo apt-get install -y ngrok; \
	elif command -v brew >/dev/null 2>&1; then \
		brew install ngrok/ngrok/ngrok; \
	else \
		echo "  Téléchargement manuel de ngrok..."; \
		curl -sL https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz \
		  | sudo tar xz -C /usr/local/bin; \
	fi
	@echo ""
	@ngrok --version 2>/dev/null || echo "⚠️  Relancez votre terminal si ngrok est introuvable."
	@echo ""
	@echo "  Étapes suivantes :"
	@echo "  1. Compte gratuit (sans CB) : https://dashboard.ngrok.com/signup"
	@echo "  2. Token         : https://dashboard.ngrok.com/get-started/your-authtoken"
	@echo "  3. Domaine       : https://dashboard.ngrok.com/domains"
	@echo "  4. make ngrok"
	@echo ""

ngrok: ## Lancer le tunnel ngrok avec domaine statique permanent
	@echo ""
	@echo "══════════════════════════════════════════════"
	@echo "  Tunnel ngrok — Domaine statique permanent"
	@echo "══════════════════════════════════════════════"
	@echo ""
	@# ── Vérifier que ngrok est installé ────────────────────────────────────
	@if ! command -v ngrok >/dev/null 2>&1; then \
		echo "  ❌ ngrok introuvable."; \
		echo "  Lancez d'abord : make ngrok-install"; \
		echo ""; exit 1; \
	fi
	@# ── Lire / saisir NGROK_AUTH_TOKEN ─────────────────────────────────────
	@NGROK_TOKEN=$$(grep '^NGROK_AUTH_TOKEN=' .env 2>/dev/null | cut -d= -f2- | tr -d '[:space:]' | tr -d '"'); \
	if [ -z "$$NGROK_TOKEN" ]; then \
		echo "  ┌─────────────────────────────────────────────────────┐"; \
		echo "  │  Étape 1/2 — Auth Token ngrok                       │"; \
		echo "  │  https://dashboard.ngrok.com/get-started/your-authtoken │"; \
		echo "  └─────────────────────────────────────────────────────┘"; \
		echo ""; \
		read -p "  Collez votre Auth Token : " NGROK_TOKEN; \
		if grep -q '^NGROK_AUTH_TOKEN=' .env 2>/dev/null; then \
			$(SED_I) "s|^NGROK_AUTH_TOKEN=.*|NGROK_AUTH_TOKEN=$$NGROK_TOKEN|" .env; \
		else \
			printf '\n# ── ngrok ────────────────────────────────────────────────────────────────\n' >> .env; \
			echo "NGROK_AUTH_TOKEN=$$NGROK_TOKEN" >> .env; \
		fi; \
		echo "  ✅ Token sauvegardé dans .env"; \
		echo ""; \
	fi; \
	ngrok config add-authtoken "$$NGROK_TOKEN" 2>/dev/null; \
	NGROK_DOMAIN=$$(grep '^NGROK_DOMAIN=' .env 2>/dev/null | cut -d= -f2- | tr -d '[:space:]' | tr -d '"'); \
	if [ -z "$$NGROK_DOMAIN" ]; then \
		echo "  ┌─────────────────────────────────────────────────────┐"; \
		echo "  │  Étape 2/2 — Domaine statique ngrok                 │"; \
		echo "  │  Réservez-en un sur : https://dashboard.ngrok.com/domains │"; \
		echo "  │  Exemple : khidmeti-oran.ngrok-free.app             │"; \
		echo "  └─────────────────────────────────────────────────────┘"; \
		echo ""; \
		read -p "  Entrez votre domaine statique : " NGROK_DOMAIN; \
		if grep -q '^NGROK_DOMAIN=' .env 2>/dev/null; then \
			$(SED_I) "s|^NGROK_DOMAIN=.*|NGROK_DOMAIN=$$NGROK_DOMAIN|" .env; \
		else \
			echo "NGROK_DOMAIN=$$NGROK_DOMAIN" >> .env; \
		fi; \
		echo "  ✅ Domaine sauvegardé dans .env (ne sera plus demandé)"; \
		echo ""; \
	fi; \
	NGROK_DOMAIN=$$(grep '^NGROK_DOMAIN=' .env | cut -d= -f2- | tr -d '[:space:]' | tr -d '"'); \
	echo "  🚀 Démarrage du tunnel..."; \
	echo ""; \
	echo "  URL permanente : https://$$NGROK_DOMAIN"; \
	echo ""; \
	echo "  flutter run --dart-define=API_BASE_URL=https://$$NGROK_DOMAIN"; \
	echo ""; \
	echo "  → Collez cette URL dans Firebase Remote Config (clé : api_base_url)"; \
	echo "  → Ctrl+C pour arrêter"; \
	echo ""; \
	ngrok http --domain="$$NGROK_DOMAIN" 80

ngrok-reset: ## Réinitialiser la config ngrok (changer token ou domaine)
	@$(SED_I) '/^NGROK_AUTH_TOKEN=/d' .env 2>/dev/null; \
	$(SED_I) '/^NGROK_DOMAIN=/d' .env 2>/dev/null; \
	$(SED_I) '/^# ── ngrok/d' .env 2>/dev/null; \
	echo "✅ Config ngrok supprimée — relancez : make ngrok"

## ══════════════════════════════════════════════════════════════════════════════
## GESTION DE L'IA
## ══════════════════════════════════════════════════════════════════════════════

ai-switch-openrouter: ## Basculer sur OpenRouter (Gemma 4 gratuit)
	@$(SED_I) 's/^AI_PROVIDER=.*/AI_PROVIDER=openrouter/' .env
	@docker compose up -d --no-deps api
	@echo "✅ Fournisseur IA : OPENROUTER (Gemma 4 gratuit)"

ai-switch-gemini: ## Basculer sur Google Gemini
	@$(SED_I) 's/^AI_PROVIDER=.*/AI_PROVIDER=gemini/' .env
	@docker compose up -d --no-deps api
	@echo "✅ Fournisseur IA : GEMINI"

ai-switch-ollama: ## Basculer sur Ollama (local)
	@$(SED_I) 's/^AI_PROVIDER=.*/AI_PROVIDER=ollama/' .env
	@docker compose -f docker-compose.yml -f docker-compose.local.yml up -d
	@echo "✅ Fournisseur IA : OLLAMA"

ai-switch-vllm: ## Basculer sur vLLM (GPU)
	@$(SED_I) 's/^AI_PROVIDER=.*/AI_PROVIDER=vllm/' .env
	@docker compose -f docker-compose.yml -f docker-compose.gpu.yml up -d
	@echo "✅ Fournisseur IA : VLLM"

ollama-pull: ## Télécharger les modèles Ollama
	@docker exec khidmeti-ollama ollama pull gemma4:e2b
	@docker exec khidmeti-ollama ollama pull nomic-embed-text
	@echo "✅ Modèles téléchargés."

## ══════════════════════════════════════════════════════════════════════════════
## SCRIPTS — Migrations MongoDB + Seeds TypeScript
## ══════════════════════════════════════════════════════════════════════════════

scripts: ## Exécuter TOUTES les migrations puis TOUS les seeds
	@$(MAKE) scripts-migrations
	@$(MAKE) scripts-seeds

scripts-migrations: ## Exécuter toutes les migrations (scripts/migrations/*.js)
	@echo ""
	@echo "══════════════════════════════════════════════"
	@echo "  Migrations MongoDB"
	@echo "══════════════════════════════════════════════"
	@MONGO_USER=$$(grep '^MONGO_ROOT_USER' .env | cut -d= -f2 | tr -d '[:space:]'); \
	MONGO_PASS=$$(grep '^MONGO_ROOT_PASSWORD' .env | cut -d= -f2 | tr -d '[:space:]'); \
	COUNT=0; FAILED=0; \
	shopt -s nullglob; \
	FILES=(scripts/migrations/*.js); \
	if [ $${#FILES[@]} -eq 0 ]; then \
	  echo "  ⚪ Aucune migration trouvée dans scripts/migrations/"; \
	else \
	  for f in "$${FILES[@]}"; do \
	    echo "  → $$(basename $$f)"; \
	    docker exec -i khidmeti-mongo mongosh \
	      --quiet \
	      -u "$$MONGO_USER" -p "$$MONGO_PASS" \
	      --authenticationDatabase admin khidmeti < "$$f" \
	    && { echo "  ✅ $$(basename $$f) OK"; COUNT=$$((COUNT+1)); } \
	    || { echo "  ❌ $$(basename $$f) FAILED"; FAILED=$$((FAILED+1)); }; \
	  done; \
	  echo ""; \
	  echo "  ✅ $$COUNT migration(s) OK  |  ❌ $$FAILED échec(s)"; \
	  [ $$FAILED -gt 0 ] && exit 1 || true; \
	fi
	@echo ""

scripts-seeds: ## Exécuter tous les seeds (apps/api/src/scripts/seeds/*.ts)
	@echo ""
	@echo "══════════════════════════════════════════════"
	@echo "  Seeds TypeScript"
	@echo "══════════════════════════════════════════════"
	@COUNT=0; FAILED=0; \
	shopt -s nullglob; \
	FILES=(apps/api/src/scripts/seeds/*.ts); \
	if [ $${#FILES[@]} -eq 0 ]; then \
	  echo "  ⚪ Aucun seed trouvé dans apps/api/src/scripts/seeds/"; \
	else \
	  for f in "$${FILES[@]}"; do \
	    NAME=$$(basename "$$f"); \
	    echo "  → $$NAME $(ARGS)"; \
	    docker exec khidmeti-api \
	      npx ts-node --project tsconfig.json "src/scripts/seeds/$$NAME" $(ARGS) \
	    && { echo "  ✅ $$NAME OK"; COUNT=$$((COUNT+1)); } \
	    || { echo "  ❌ $$NAME FAILED"; FAILED=$$((FAILED+1)); }; \
	  done; \
	  echo ""; \
	  echo "  ✅ $$COUNT seed(s) OK  |  ❌ $$FAILED échec(s)"; \
	  [ $$FAILED -gt 0 ] && exit 1 || true; \
	fi
	@echo ""

scripts-%:
	@NAME=$*; \
	if [ -f "scripts/migrations/$$NAME.js" ]; then \
	  MONGO_USER=$$(grep '^MONGO_ROOT_USER' .env | cut -d= -f2 | tr -d '[:space:]'); \
	  MONGO_PASS=$$(grep '^MONGO_ROOT_PASSWORD' .env | cut -d= -f2 | tr -d '[:space:]'); \
	  echo ""; \
	  echo "  → Migration : $$NAME.js"; \
	  docker exec -i khidmeti-mongo mongosh \
	    --quiet \
	    -u "$$MONGO_USER" -p "$$MONGO_PASS" \
	    --authenticationDatabase admin khidmeti < "scripts/migrations/$$NAME.js" \
	  && echo "  ✅ $$NAME.js OK" || { echo "  ❌ $$NAME.js FAILED"; exit 1; }; \
	  echo ""; \
	elif [ -f "apps/api/src/scripts/seeds/$$NAME.ts" ]; then \
	  echo ""; \
	  echo "  → Seed : $$NAME.ts $(ARGS)"; \
	  docker exec khidmeti-api \
	    npx ts-node --project tsconfig.json "src/scripts/seeds/$$NAME.ts" $(ARGS) \
	  && echo "  ✅ $$NAME.ts OK" || { echo "  ❌ $$NAME.ts FAILED"; exit 1; }; \
	  echo ""; \
	else \
	  echo ""; \
	  echo "  ❌ Script '$$NAME' introuvable."; \
	  echo "     Cherché dans :"; \
	  echo "       scripts/migrations/$$NAME.js"; \
	  echo "       apps/api/src/scripts/seeds/$$NAME.ts"; \
	  echo ""; \
	  echo "  Scripts disponibles :"; \
	  echo "    Migrations :"; \
	  ls scripts/migrations/*.js 2>/dev/null | xargs -I{} basename {} .js | sed 's/^/      /' || echo "      (aucune)"; \
	  echo "    Seeds :"; \
	  ls apps/api/src/scripts/seeds/*.ts 2>/dev/null | xargs -I{} basename {} .ts | sed 's/^/      /' || echo "      (aucun)"; \
	  echo ""; \
	  exit 1; \
	fi

## ══════════════════════════════════════════════════════════════════════════════
## MINIO
## ══════════════════════════════════════════════════════════════════════════════

minio-buckets: ## Recréer les buckets MinIO
	@MINIO_ACCESS_KEY=$$(grep MINIO_ACCESS_KEY .env | cut -d= -f2 | tr -d '[:space:]'); \
	MINIO_SECRET_KEY=$$(grep MINIO_SECRET_KEY .env | cut -d= -f2 | tr -d '[:space:]'); \
	docker exec khidmeti-minio-init /bin/sh -c "\
		mc alias set local http://minio:9001 $$MINIO_ACCESS_KEY $$MINIO_SECRET_KEY && \
		mc mb --ignore-existing local/profile-images && \
		mc mb --ignore-existing local/service-media && \
		mc mb --ignore-existing local/audio-recordings && \
		mc anonymous set download local/profile-images && \
		echo '✅ Buckets Khidmeti créés.'" 2>/dev/null || \
	docker run --rm --network khidmeti-network minio/mc:latest sh -c \
		"mc alias set local http://minio:9001 $$MINIO_ACCESS_KEY $$MINIO_SECRET_KEY && \
		 mc mb --ignore-existing local/profile-images && \
		 mc mb --ignore-existing local/service-media && \
		 mc mb --ignore-existing local/audio-recordings && \
		 mc anonymous set download local/profile-images && \
		 echo '✅ Buckets créés.'"

minio-console: ## Ouvrir la console MinIO
	@$(OPEN_CMD) http://localhost:9002 2>/dev/null || echo "  → http://localhost:9002"

minio-list: ## Lister les fichiers MinIO
	@MINIO_ACCESS_KEY=$$(grep MINIO_ACCESS_KEY .env | cut -d= -f2 | tr -d '[:space:]'); \
	MINIO_SECRET_KEY=$$(grep MINIO_SECRET_KEY .env | cut -d= -f2 | tr -d '[:space:]'); \
	docker run --rm --network khidmeti-network minio/mc:latest sh -c \
	  "mc alias set local http://minio:9001 $$MINIO_ACCESS_KEY $$MINIO_SECRET_KEY && \
	   mc ls local/profile-images; mc ls local/service-media"

## ══════════════════════════════════════════════════════════════════════════════
## TESTS API
## ══════════════════════════════════════════════════════════════════════════════

test-api: ## Tester les endpoints principaux
	@echo ""
	@echo "  [1] Health :"; curl -s http://localhost:3000/health
	@echo ""
	@echo "  [2] Swagger (code HTTP) :"; curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/api/docs
	@echo ""

test-ai: ## Tester l'extraction d'intention IA (make test-ai TOKEN=xxx)
	@if [ -z "$(TOKEN)" ]; then \
		echo "Usage : make test-ai TOKEN=<firebase_id_token>"; \
	else \
		curl -s -X POST http://localhost:3000/ai/extract-intent \
		  -H "Authorization: Bearer $(TOKEN)" \
		  -H "Content-Type: application/json" \
		  -d '{"text": "jai une fuite deau sous levier"}'; \
	fi

## ══════════════════════════════════════════════════════════════════════════════
## SAUVEGARDE
## ══════════════════════════════════════════════════════════════════════════════

backup: ## Sauvegarder MongoDB + MinIO
	@echo "Sauvegarde — $(DATETIME)"
	@mkdir -p backups/mongodb/$(DATETIME) backups/minio/$(DATETIME)
	@MONGO_USER=$$(grep MONGO_ROOT_USER .env | cut -d= -f2 | tr -d '[:space:]'); \
	MONGO_PASS=$$(grep MONGO_ROOT_PASSWORD .env | cut -d= -f2 | tr -d '[:space:]'); \
	docker exec khidmeti-mongo mongodump \
	  --username "$$MONGO_USER" --password "$$MONGO_PASS" \
	  --authenticationDatabase admin --db khidmeti \
	  --out /tmp/backup_$(DATETIME); \
	docker cp khidmeti-mongo:/tmp/backup_$(DATETIME) backups/mongodb/$(DATETIME); \
	echo "  ✅ MongoDB → backups/mongodb/$(DATETIME)"

restore: ## Restaurer (BACKUP_DATE=YYYYMMDD-HHMMSS)
	@if [ -z "$(BACKUP_DATE)" ]; then \
		echo "Usage : make restore BACKUP_DATE=20250101-120000"; exit 1; \
	fi
	@MONGO_USER=$$(grep MONGO_ROOT_USER .env | cut -d= -f2 | tr -d '[:space:]'); \
	MONGO_PASS=$$(grep MONGO_ROOT_PASSWORD .env | cut -d= -f2 | tr -d '[:space:]'); \
	docker cp backups/mongodb/$(BACKUP_DATE) khidmeti-mongo:/tmp/restore_$(BACKUP_DATE); \
	docker exec khidmeti-mongo mongorestore \
	  --username "$$MONGO_USER" --password "$$MONGO_PASS" \
	  --authenticationDatabase admin --db khidmeti --drop \
	  /tmp/restore_$(BACKUP_DATE)/khidmeti
	@echo "✅ Restauration terminée."

## ══════════════════════════════════════════════════════════════════════════════
## SHELL ET DEBUG
## ══════════════════════════════════════════════════════════════════════════════

shell-api: ## Shell dans le conteneur NestJS
	@docker exec -it khidmeti-api /bin/sh

shell-mongo: ## mongosh dans MongoDB
	@MONGO_USER=$$(grep MONGO_ROOT_USER .env | cut -d= -f2 | tr -d '[:space:]'); \
	MONGO_PASS=$$(grep MONGO_ROOT_PASSWORD .env | cut -d= -f2 | tr -d '[:space:]'); \
	docker exec -it khidmeti-mongo mongosh -u "$$MONGO_USER" -p "$$MONGO_PASS" \
	  --authenticationDatabase admin khidmeti

shell-redis: ## redis-cli dans Redis
	@REDIS_PASS=$$(grep REDIS_PASSWORD .env | cut -d= -f2 | tr -d '[:space:]'); \
	docker exec -it khidmeti-redis redis-cli -a "$$REDIS_PASS"

shell-minio: ## mc client MinIO
	@MINIO_KEY=$$(grep MINIO_ACCESS_KEY .env | cut -d= -f2 | tr -d '[:space:]'); \
	MINIO_SECRET=$$(grep MINIO_SECRET_KEY .env | cut -d= -f2 | tr -d '[:space:]'); \
	docker run -it --rm --network khidmeti-network minio/mc:latest \
	  sh -c "mc alias set local http://minio:9001 $$MINIO_KEY $$MINIO_SECRET && sh"

shell-qdrant: ## Ouvrir le dashboard Qdrant
	@$(OPEN_CMD) http://localhost:6333/dashboard 2>/dev/null || echo "  → http://localhost:6333/dashboard"

mongo-stats: ## Stats MongoDB
	@MONGO_USER=$$(grep MONGO_ROOT_USER .env | cut -d= -f2 | tr -d '[:space:]'); \
	MONGO_PASS=$$(grep MONGO_ROOT_PASSWORD .env | cut -d= -f2 | tr -d '[:space:]'); \
	docker exec khidmeti-mongo mongosh -u "$$MONGO_USER" -p "$$MONGO_PASS" \
	  --authenticationDatabase admin khidmeti --quiet --eval "db.stats()"

redis-info: ## Stats Redis
	@REDIS_PASS=$$(grep REDIS_PASSWORD .env | cut -d= -f2 | tr -d '[:space:]'); \
	docker exec khidmeti-redis redis-cli -a "$$REDIS_PASS" INFO server

redis-flush: ## Vider le cache Redis
	@REDIS_PASS=$$(grep REDIS_PASSWORD .env | cut -d= -f2 | tr -d '[:space:]'); \
	docker exec khidmeti-redis redis-cli -a "$$REDIS_PASS" FLUSHALL
	@echo "✅ Cache Redis vidé."

## ══════════════════════════════════════════════════════════════════════════════
## NETTOYAGE
## ══════════════════════════════════════════════════════════════════════════════

clean-logs: ## Vider les logs
	@find logs/ -name "*.log" -delete 2>/dev/null || true
	@echo "✅ Logs nettoyés."

clean: ## Supprimer volumes + données (DESTRUCTIF)
	@echo ""
	@echo "  ⚠️  ATTENTION : suppression de TOUTES les données Khidmeti."
	@read -p "  Confirmer ? [y/N] " CONFIRM; \
	if [ "$$CONFIRM" = "y" ] || [ "$$CONFIRM" = "Y" ]; then \
		docker compose down -v --remove-orphans; \
		docker system prune -f; \
		rm -rf data/mongodb data/redis data/qdrant data/minio; \
		echo "✅ Nettoyage terminé."; \
	else \
		echo "Annulé."; \
	fi

## ══════════════════════════════════════════════════════════════════════════════
## PRODUCTION
## ══════════════════════════════════════════════════════════════════════════════

prod-start: ## Démarrer en mode production
	@docker compose up -d
	@echo "✅ Mode production actif."

prod-update: ## Mettre à jour l'API sans downtime
	@docker compose build --no-cache api
	@docker compose up -d --no-deps --build api
	@echo "✅ API mise à jour."

firewall: ## Afficher les commandes pare-feu
	@echo "  OS détecté : $(OS)"
ifeq ($(OS),Linux)
	@echo "  sudo ufw allow 80/tcp 3000/tcp 6333/tcp 8081/tcp 9001/tcp 9002/tcp"
endif
