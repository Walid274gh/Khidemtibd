

# ==========================================
# MAKEFILE - KHIDMETI BACKEND
# Stack: NestJS + MongoDB + Redis + Qdrant + MinIO + nginx
# ==========================================

.PHONY: help start stop restart build rebuild logs health status \
        firewall test-api backup restore clean \
        shell-api shell-mongo shell-redis shell-minio \
        ai-status ai-switch-gemini ai-switch-ollama ai-switch-vllm \
        ollama-pull minio-buckets dns

# ==========================================
# AIDE
# ==========================================

help: ## Afficher l'aide
	@echo.
	@echo ==========================================
	@echo   KHIDMETI - Commandes disponibles
	@echo ==========================================
	@echo.
	@echo   [SERVICES]
	@echo   start              Demarrer tous les services (AI=gemini par defaut)
	@echo   start-local        Demarrer avec Ollama (16GB RAM requis)
	@echo   start-gpu          Demarrer avec vLLM  (GPU NVIDIA requis)
	@echo   stop               Arreter tous les services
	@echo   restart            Redemarrer tous les services
	@echo   build              Builder l'image NestJS
	@echo   rebuild            Rebuild + redemarrer
	@echo.
	@echo   [LOGS]
	@echo   logs               Tous les logs en temps reel
	@echo   logs-api           Logs NestJS uniquement
	@echo   logs-mongo         Logs MongoDB uniquement
	@echo   logs-redis         Logs Redis uniquement
	@echo   logs-qdrant        Logs Qdrant uniquement
	@echo   logs-minio         Logs MinIO uniquement
	@echo   logs-nginx         Logs nginx uniquement
	@echo.
	@echo   [DIAGNOSTIC]
	@echo   health             Verifier la sante de tous les services
	@echo   status             Statut des conteneurs Docker
	@echo   ai-status          Afficher le provider AI actif
	@echo   dns                Afficher les URLs et la config reseau
	@echo.
	@echo   [IA]
	@echo   ai-switch-gemini   Basculer sur Gemini API (defaut, internet)
	@echo   ai-switch-ollama   Basculer sur Ollama   (local, 16GB RAM)
	@echo   ai-switch-vllm     Basculer sur vLLM     (GPU, 16GB VRAM)
	@echo   ollama-pull        Telecharger les modeles Ollama
	@echo.
	@echo   [MINIO]
	@echo   minio-buckets      Creer les buckets MinIO manuellement
	@echo   minio-console      Ouvrir la console MinIO dans le navigateur
	@echo.
	@echo   [TESTS]
	@echo   test-api           Tester les endpoints principaux
	@echo   test-ai            Tester l'extraction d'intention IA
	@echo   test-upload        Tester l'upload d'image
	@echo.
	@echo   [SAUVEGARDE]
	@echo   backup             Sauvegarder MongoDB + MinIO
	@echo   restore            Restaurer (BACKUP_DATE=YYYYMMDD-HHMMSS)
	@echo.
	@echo   [DEBUG]
	@echo   shell-api          Shell dans le conteneur NestJS
	@echo   shell-mongo        mongosh dans MongoDB
	@echo   shell-redis        redis-cli dans Redis
	@echo   shell-minio        mc (MinIO client) dans le conteneur minio-init
	@echo.
	@echo   [NETTOYAGE]
	@echo   clean              Supprimer volumes + donnees (destructif!)
	@echo   clean-logs         Vider les logs uniquement
	@echo.

# ==========================================
# GESTION DES SERVICES
# ==========================================

start: ## Demarrer (AI_PROVIDER=gemini par defaut)
	@echo.
	@echo ==========================================
	@echo   Demarrage de Khidmeti Backend...
	@echo ==========================================
	@if not exist logs mkdir logs
	@if not exist backups mkdir backups
	@if not exist backups\mongodb mkdir backups\mongodb
	@if not exist backups\minio mkdir backups\minio
	@if not exist data mkdir data
	@if not exist data\mongodb mkdir data\mongodb
	@if not exist data\redis mkdir data\redis
	@if not exist data\qdrant mkdir data\qdrant
	@if not exist data\minio mkdir data\minio
	@if not exist .env (copy .env.example .env && echo ATTENTION: Fichier .env cree depuis .env.example. Veuillez le configurer!)
	@docker compose up -d
	@echo.
	@echo   Attente du demarrage des services (15s)...
	@timeout /t 15 /nobreak >nul
	@make health
	@echo.
	@make dns

start-local: ## Demarrer avec Ollama (16GB RAM requis)
	@echo.
	@echo ==========================================
	@echo   Demarrage avec Ollama (AI local)...
	@echo   Requis: 16GB RAM minimum
	@echo ==========================================
	@docker compose -f docker-compose.yml -f docker-compose.local.yml up -d
	@echo   Telechargement des modeles Ollama...
	@timeout /t 20 /nobreak >nul
	@make ollama-pull
	@make health

start-gpu: ## Demarrer avec vLLM (GPU NVIDIA requis)
	@echo.
	@echo ==========================================
	@echo   Demarrage avec vLLM (GPU)...
	@echo   Requis: GPU NVIDIA 16GB VRAM + HF_TOKEN dans .env
	@echo ==========================================
	@docker compose -f docker-compose.yml -f docker-compose.gpu.yml up -d
	@make health

stop: ## Arreter tous les services
	@echo Arret de Khidmeti...
	@docker compose down
	@echo Services arretes.

stop-local: ## Arreter le stack Ollama
	@docker compose -f docker-compose.yml -f docker-compose.local.yml down

stop-gpu: ## Arreter le stack vLLM
	@docker compose -f docker-compose.yml -f docker-compose.gpu.yml down

restart: ## Redemarrer
	@make stop
	@timeout /t 3 /nobreak >nul
	@make start

build: ## Builder l'image NestJS
	@echo Build de l'image API...
	@docker compose build --no-cache api
	@echo Build termine.

rebuild: build start ## Rebuild complet + redemarrage

# ==========================================
# LOGS
# ==========================================

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

# ==========================================
# DIAGNOSTIC ET SANTE
# ==========================================

health: ## Verifier la sante de tous les services
	@echo.
	@echo ==========================================
	@echo   Etat des services Khidmeti
	@echo ==========================================
	@echo.
	@echo   NestJS API (port 3000):
	@curl -s -o nul -w "    HTTP %%{http_code}" http://localhost:3000/health 2>nul && echo  [OK] || echo    [HORS LIGNE]
	@echo.
	@echo   nginx (port 80):
	@curl -s -o nul -w "    HTTP %%{http_code}" http://localhost/health 2>nul && echo  [OK] || echo    [HORS LIGNE]
	@echo.
	@echo   MongoDB (port 27017):
	@docker exec khidmeti-mongo mongosh --quiet --eval "db.adminCommand('ping').ok" >nul 2>&1 && echo    [OK] || echo    [HORS LIGNE]
	@echo.
	@echo   Redis (port 6379):
	@docker exec khidmeti-redis redis-cli -a %REDIS_PASSWORD% ping >nul 2>&1 && echo    [OK] || echo    [HORS LIGNE]
	@echo.
	@echo   Qdrant (port 6333):
	@curl -s -o nul -w "    HTTP %%{http_code}" http://localhost:6333/healthz 2>nul && echo  [OK] || echo    [HORS LIGNE]
	@echo.
	@echo   MinIO API (port 9001):
	@curl -s -o nul -w "    HTTP %%{http_code}" http://localhost:9001/minio/health/live 2>nul && echo  [OK] || echo    [HORS LIGNE]
	@echo.
	@echo   MinIO Console (port 9002):
	@curl -s -o nul -w "    HTTP %%{http_code}" http://localhost:9002 2>nul && echo  [OK] || echo    [HORS LIGNE]
	@echo.

status: ## Statut des conteneurs
	@echo.
	@docker ps -a --filter "name=khidmeti" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
	@echo.

ai-status: ## Afficher le provider AI actif
	@echo.
	@echo ==========================================
	@echo   Provider IA actif
	@echo ==========================================
	@docker exec khidmeti-api printenv AI_PROVIDER 2>nul || echo   (conteneur non demarre)
	@echo.

dns: ## Afficher les URLs et la config reseau
	@echo.
	@echo ==========================================
	@echo   URLs des services Khidmeti
	@echo ==========================================
	@echo.
	@for /f "delims=" %%a in ('hostname') do @(
		echo   API REST:          http://%%a:3000
		echo   API via nginx:     http://%%a:80
		echo   Swagger docs:      http://%%a:3000/api/docs
		echo   Qdrant dashboard:  http://%%a:6333/dashboard
		echo   MinIO console:     http://%%a:9002
		echo   MinIO API (S3):    http://%%a:9001
	)
	@echo.
	@echo ==========================================
	@echo   Config Flutter (VITE_API_URL equivalent)
	@echo ==========================================
	@echo.
	@for /f "delims=" %%a in ('hostname') do @echo   API_BASE_URL=http://%%a:80
	@echo.
	@echo   Fichier a modifier: apps\api\.env
	@echo   Variable:           API_BASE_URL
	@echo.

# ==========================================
# GESTION DE L'IA
# ==========================================

ai-switch-gemini: ## Basculer sur Gemini (internet requis)
	@echo Bascule vers Gemini API...
	@powershell -Command "(Get-Content .env) -replace 'AI_PROVIDER=.*', 'AI_PROVIDER=gemini' | Set-Content .env"
	@docker compose up -d --no-deps api
	@echo Provider IA: GEMINI [OK]

ai-switch-ollama: ## Basculer sur Ollama (local)
	@echo Bascule vers Ollama...
	@powershell -Command "(Get-Content .env) -replace 'AI_PROVIDER=.*', 'AI_PROVIDER=ollama' | Set-Content .env"
	@docker compose -f docker-compose.yml -f docker-compose.local.yml up -d
	@echo Provider IA: OLLAMA [OK]

ai-switch-vllm: ## Basculer sur vLLM (GPU)
	@echo Bascule vers vLLM...
	@powershell -Command "(Get-Content .env) -replace 'AI_PROVIDER=.*', 'AI_PROVIDER=vllm' | Set-Content .env"
	@docker compose -f docker-compose.yml -f docker-compose.gpu.yml up -d
	@echo Provider IA: VLLM [OK]

ollama-pull: ## Telecharger les modeles Ollama
	@echo Telechargement des modeles Ollama...
	@docker exec khidmeti-ollama ollama pull gemma4:e2b
	@docker exec khidmeti-ollama ollama pull nomic-embed-text
	@echo Modeles telecharges.

# ==========================================
# MINIO
# ==========================================

minio-buckets: ## Creer les buckets MinIO manuellement
	@echo Creation des buckets MinIO...
	@docker exec khidmeti-minio-init /bin/sh -c "\
		mc alias set local http://minio:9001 %MINIO_ACCESS_KEY% %MINIO_SECRET_KEY%; \
		mc mb --ignore-existing local/profile-images; \
		mc mb --ignore-existing local/service-media; \
		mc mb --ignore-existing local/audio-recordings; \
		mc anonymous set download local/profile-images; \
		echo Buckets OK"
	@echo Buckets MinIO crees.

minio-console: ## Ouvrir la console MinIO
	@start http://localhost:9002

minio-list: ## Lister tous les fichiers dans les buckets
	@echo.
	@echo Bucket: profile-images
	@docker run --rm --network khidmeti-network minio/mc:latest \
		sh -c "mc alias set local http://minio:9001 %MINIO_ACCESS_KEY% %MINIO_SECRET_KEY% && mc ls local/profile-images"
	@echo.
	@echo Bucket: service-media
	@docker run --rm --network khidmeti-network minio/mc:latest \
		sh -c "mc alias set local http://minio:9001 %MINIO_ACCESS_KEY% %MINIO_SECRET_KEY% && mc ls local/service-media"

# ==========================================
# TESTS API
# ==========================================

test-api: ## Tester les endpoints principaux
	@echo.
	@echo ==========================================
	@echo   Tests API Khidmeti
	@echo ==========================================
	@echo.
	@echo   [1] Health check:
	@curl -s http://localhost:3000/health
	@echo.
	@echo.
	@echo   [2] Version Swagger disponible:
	@curl -s -o nul -w "    Swagger: HTTP %%{http_code}" http://localhost:3000/api/docs 2>nul
	@echo.
	@echo.
	@echo   [3] Endpoint workers (non-auth):
	@curl -s -o nul -w "    /workers: HTTP %%{http_code}" http://localhost:3000/workers 2>nul
	@echo.
	@echo   NOTE: La plupart des endpoints requierent un token Firebase Bearer.
	@echo   Utilisez Swagger UI pour tester avec auth: http://localhost:3000/api/docs
	@echo.

test-ai: ## Tester l'extraction d'intention IA (necessite TOKEN)
	@echo.
	@echo Test de l'extraction IA...
	@echo NOTE: Definir TOKEN=votre_firebase_token avant d'executer
	@echo.
	@if "%TOKEN%"=="" (echo ERREUR: TOKEN non defini. Usage: make test-ai TOKEN=xxx) else (curl -s -X POST http://localhost:3000/ai/extract-intent -H "Authorization: Bearer %TOKEN%" -H "Content-Type: application/json" -d "{\"text\": \"j ai une fuite d eau sous l evier\"}")
	@echo.

test-upload: ## Tester l'upload d'image (necessite TOKEN et FILE)
	@echo.
	@echo Test upload image vers MinIO...
	@echo Usage: make test-upload TOKEN=xxx FILE=C:\chemin\image.jpg
	@echo.
	@if "%TOKEN%"=="" (echo ERREUR: TOKEN non defini) else if "%FILE%"=="" (echo ERREUR: FILE non defini) else (curl -s -X POST http://localhost:3000/media/upload/image -H "Authorization: Bearer %TOKEN%" -F "file=@%FILE%")
	@echo.

# ==========================================
# PARE-FEU
# ==========================================

firewall: ## Afficher les commandes pare-feu
	@echo.
	@echo ==========================================
	@echo   Configuration Pare-feu Windows
	@echo   (Executer en tant qu Administrateur)
	@echo ==========================================
	@echo.
	@echo netsh advfirewall firewall add rule name="Khidmeti API"          dir=in action=allow protocol=TCP localport=3000
	@echo netsh advfirewall firewall add rule name="Khidmeti nginx"        dir=in action=allow protocol=TCP localport=80
	@echo netsh advfirewall firewall add rule name="Khidmeti Qdrant"       dir=in action=allow protocol=TCP localport=6333
	@echo netsh advfirewall firewall add rule name="Khidmeti MinIO API"    dir=in action=allow protocol=TCP localport=9001
	@echo netsh advfirewall firewall add rule name="Khidmeti MinIO UI"     dir=in action=allow protocol=TCP localport=9002
	@echo netsh advfirewall firewall add rule name="Khidmeti MongoDB"      dir=in action=allow protocol=TCP localport=27017
	@echo.
	@echo Pour verifier les regles:
	@echo netsh advfirewall firewall show rule name=all ^| findstr Khidmeti
	@echo.

firewall-apply: ## Appliquer les regles pare-feu (Admin requis)
	@netsh advfirewall firewall add rule name="Khidmeti API"          dir=in action=allow protocol=TCP localport=3000
	@netsh advfirewall firewall add rule name="Khidmeti nginx"        dir=in action=allow protocol=TCP localport=80
	@netsh advfirewall firewall add rule name="Khidmeti Qdrant"       dir=in action=allow protocol=TCP localport=6333
	@netsh advfirewall firewall add rule name="Khidmeti MinIO API"    dir=in action=allow protocol=TCP localport=9001
	@netsh advfirewall firewall add rule name="Khidmeti MinIO UI"     dir=in action=allow protocol=TCP localport=9002
	@echo Regles pare-feu appliquees.

# ==========================================
# SAUVEGARDE ET RESTAURATION
# ==========================================

backup: ## Sauvegarder MongoDB + MinIO
	@echo.
	@echo ==========================================
	@echo   Sauvegarde Khidmeti
	@echo ==========================================
	@for /f "tokens=2 delims==" %%a in ('wmic os get localdatetime /value') do @set DATETIME=%%a
	@set BACKUP_ID=%DATETIME:~0,8%-%DATETIME:~8,6%
	@echo   ID de sauvegarde: %BACKUP_ID%
	@echo.
	@echo   [1/2] Sauvegarde MongoDB...
	@docker exec khidmeti-mongo mongodump --username %MONGO_ROOT_USER% --password %MONGO_ROOT_PASSWORD% --authenticationDatabase admin --db khidmeti --out /tmp/backup_%BACKUP_ID%
	@docker cp khidmeti-mongo:/tmp/backup_%BACKUP_ID% backups\mongodb\%BACKUP_ID%
	@echo   MongoDB sauvegarde dans backups\mongodb\%BACKUP_ID%
	@echo.
	@echo   [2/2] Sauvegarde MinIO (mirror local)...
	@docker run --rm --network khidmeti-network -v "%CD%\backups\minio\%BACKUP_ID%:/backup" minio/mc:latest sh -c "mc alias set local http://minio:9001 %MINIO_ACCESS_KEY% %MINIO_SECRET_KEY% && mc mirror local/profile-images /backup/profile-images && mc mirror local/service-media /backup/service-media"
	@echo   MinIO sauvegarde dans backups\minio\%BACKUP_ID%
	@echo.
	@echo   Sauvegarde complete: %BACKUP_ID%

backup-mongo: ## Sauvegarder MongoDB uniquement
	@for /f "tokens=2 delims==" %%a in ('wmic os get localdatetime /value') do @set DATETIME=%%a
	@set BACKUP_ID=%DATETIME:~0,8%-%DATETIME:~8,6%
	@docker exec khidmeti-mongo mongodump --username %MONGO_ROOT_USER% --password %MONGO_ROOT_PASSWORD% --authenticationDatabase admin --db khidmeti --out /tmp/backup_%BACKUP_ID%
	@docker cp khidmeti-mongo:/tmp/backup_%BACKUP_ID% backups\mongodb\%BACKUP_ID%
	@echo MongoDB sauvegarde: backups\mongodb\%BACKUP_ID%

restore: ## Restaurer MongoDB (BACKUP_DATE=YYYYMMDD-HHMMSS)
	@if "%BACKUP_DATE%"=="" (
		@echo ERREUR: BACKUP_DATE non defini.
		@echo Usage: make restore BACKUP_DATE=20250101-120000
		@echo.
		@echo Sauvegardes disponibles:
		@dir /b backups\mongodb\
		@exit /b 1
	)
	@echo Restauration depuis backups\mongodb\%BACKUP_DATE%...
	@docker cp backups\mongodb\%BACKUP_DATE% khidmeti-mongo:/tmp/restore_%BACKUP_DATE%
	@docker exec khidmeti-mongo mongorestore --username %MONGO_ROOT_USER% --password %MONGO_ROOT_PASSWORD% --authenticationDatabase admin --db khidmeti --drop /tmp/restore_%BACKUP_DATE%\khidmeti
	@echo Restauration terminee.

list-backups: ## Lister les sauvegardes disponibles
	@echo.
	@echo Sauvegardes MongoDB:
	@dir /b /ad backups\mongodb\ 2>nul || echo   (aucune sauvegarde)
	@echo.
	@echo Sauvegardes MinIO:
	@dir /b /ad backups\minio\ 2>nul || echo   (aucune sauvegarde)
	@echo.

# ==========================================
# SHELL ET DEBUG
# ==========================================

shell-api: ## Shell dans le conteneur NestJS
	@docker exec -it khidmeti-api /bin/sh

shell-mongo: ## mongosh dans MongoDB
	@docker exec -it khidmeti-mongo mongosh -u %MONGO_ROOT_USER% -p %MONGO_ROOT_PASSWORD% --authenticationDatabase admin khidmeti

shell-redis: ## redis-cli dans Redis
	@docker exec -it khidmeti-redis redis-cli -a %REDIS_PASSWORD%

shell-minio: ## mc client MinIO
	@docker run -it --rm --network khidmeti-network minio/mc:latest sh -c "mc alias set local http://minio:9001 %MINIO_ACCESS_KEY% %MINIO_SECRET_KEY% && sh"

shell-qdrant: ## Ouvrir le dashboard Qdrant
	@start http://localhost:6333/dashboard

mongo-stats: ## Statistiques MongoDB
	@echo.
	@docker exec khidmeti-mongo mongosh -u %MONGO_ROOT_USER% -p %MONGO_ROOT_PASSWORD% --authenticationDatabase admin khidmeti --quiet --eval "db.stats()"

redis-info: ## Informations Redis
	@echo.
	@docker exec khidmeti-redis redis-cli -a %REDIS_PASSWORD% INFO server
	@echo.
	@echo   Cles en cache:
	@docker exec khidmeti-redis redis-cli -a %REDIS_PASSWORD% DBSIZE

redis-flush: ## Vider le cache Redis
	@echo Vidage du cache Redis...
	@docker exec khidmeti-redis redis-cli -a %REDIS_PASSWORD% FLUSHALL
	@echo Cache Redis vide.

# ==========================================
# NETTOYAGE
# ==========================================

clean-logs: ## Vider les fichiers de logs
	@echo Nettoyage des logs...
	@if exist logs\*.log del /q logs\*.log
	@echo Logs nettoyes.

clean: ## Supprimer volumes et donnees (DESTRUCTIF)
	@echo.
	@echo ==========================================
	@echo   ATTENTION - OPERATION DESTRUCTIVE
	@echo   Ceci va supprimer TOUTES les donnees:
	@echo   MongoDB, Redis, Qdrant, MinIO
	@echo ==========================================
	@echo.
	@set /p CONFIRM="Confirmer la suppression? [y/N]: "
	@if /i "$(CONFIRM)"=="y" (
		docker compose down -v --remove-orphans
		docker system prune -f
		if exist data\mongodb rmdir /s /q data\mongodb
		if exist data\redis rmdir /s /q data\redis
		if exist data\qdrant rmdir /s /q data\qdrant
		if exist data\minio rmdir /s /q data\minio
		echo Nettoyage termine.
	) else (
		echo Annule.
	)

# ==========================================
# PRODUCTION
# ==========================================

prod-start: ## Demarrer en mode production
	@echo Demarrage production...
	@docker compose -f docker-compose.yml up -d
	@echo Mode production actif.

prod-update: ## Mettre a jour l'API sans downtime
	@echo Mise a jour de l API...
	@docker compose build --no-cache api
	@docker compose up -d --no-deps --build api
	@echo API mise a jour.
