@echo off
:: ══════════════════════════════════════════════════════════════════════════════
:: KHIDMETI BACKEND — Windows CMD Script
:: Usage: khidmeti.bat [command] [args]
::
:: Requirements: Docker Desktop
:: ══════════════════════════════════════════════════════════════════════════════
setlocal enabledelayedexpansion

:: ── Get local IP ──────────────────────────────────────────────────────────────
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /r "IPv4.*192\."') do (
  set LOCAL_IP=%%a
  set LOCAL_IP=!LOCAL_IP: =!
  goto :ip_found
)
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /r "IPv4.*10\."') do (
  set LOCAL_IP=%%a
  set LOCAL_IP=!LOCAL_IP: =!
  goto :ip_found
)
set LOCAL_IP=127.0.0.1
:ip_found

:: ── Route command ─────────────────────────────────────────────────────────────
set CMD=%1
set ARGS=%2
if "%CMD%"==""                  goto :help
if /i "%CMD%"=="help"           goto :help
if /i "%CMD%"=="start"          goto :start
if /i "%CMD%"=="stop"           goto :stop
if /i "%CMD%"=="restart"        goto :restart
if /i "%CMD%"=="build"          goto :build
if /i "%CMD%"=="rebuild"        goto :rebuild
if /i "%CMD%"=="health"         goto :health
if /i "%CMD%"=="status"         goto :status
if /i "%CMD%"=="logs"           goto :logs
if /i "%CMD%"=="logs-api"       goto :logs_api
if /i "%CMD%"=="tunnel"         goto :tunnel
if /i "%CMD%"=="ngrok"          goto :ngrok
if /i "%CMD%"=="ngrok-install"  goto :ngrok_install
if /i "%CMD%"=="ngrok-reset"    goto :ngrok_reset
if /i "%CMD%"=="flutter-run"    goto :flutter_run
if /i "%CMD%"=="clean"          goto :clean
if /i "%CMD%"=="dns"            goto :dns
if /i "%CMD%"=="shell-api"      goto :shell_api
if /i "%CMD%"=="shell-mongo"    goto :shell_mongo
if /i "%CMD%"=="test-api"       goto :test_api
if /i "%CMD%"=="scripts"        goto :scripts
if /i "%CMD%"=="scripts-migrations" goto :scripts_migrations
if /i "%CMD%"=="scripts-seeds"  goto :scripts_seeds

:: Vérifier si la commande commence par "scripts-"
set PREFIX=%CMD:~0,8%
if /i "%PREFIX%"=="scripts-" (
  set SCRIPT_NAME=%CMD:~8%
  goto :scripts_one
)

echo Commande inconnue : %CMD%
echo Utilisation : khidmeti.bat help
exit /b 1

:: ── HELP ──────────────────────────────────────────────────────────────────────
:help
echo.
echo ══════════════════════════════════════════════════════
echo   KHIDMETI — Commandes Windows CMD
echo   IP locale : %LOCAL_IP%
echo ══════════════════════════════════════════════════════
echo.
echo   [SERVICES]
echo   khidmeti.bat start              Demarrer tous les services
echo   khidmeti.bat stop               Arreter tous les services
echo   khidmeti.bat restart            Redemarrer
echo   khidmeti.bat build              Builder l'image NestJS
echo   khidmeti.bat rebuild            Rebuild + redemarrage
echo   khidmeti.bat health             Verifier la sante des services
echo   khidmeti.bat status             Statut des conteneurs
echo   khidmeti.bat logs               Tous les logs (Ctrl+C pour quitter)
echo   khidmeti.bat logs-api           Logs NestJS uniquement
echo   khidmeti.bat dns                URLs + config Flutter
echo   khidmeti.bat flutter-run        Lancer Flutter avec l'IP locale
echo   khidmeti.bat shell-api          Shell dans le conteneur NestJS
echo   khidmeti.bat shell-mongo        mongosh dans MongoDB
echo   khidmeti.bat test-api           Tester les endpoints
echo   khidmeti.bat clean              Supprimer toutes les donnees (DESTRUCTIF)
echo.
echo   [TUNNEL — Acces distant]
echo   khidmeti.bat tunnel             Cloudflare Quick Tunnel (URL aleatoire)
echo   khidmeti.bat ngrok              Tunnel ngrok PERMANENT (recommande)
echo   khidmeti.bat ngrok-install      Installer ngrok
echo   khidmeti.bat ngrok-reset        Changer token ou domaine ngrok
echo.
echo   [SCRIPTS — Migrations + Seeds]
echo   khidmeti.bat scripts                        Tout executer
echo   khidmeti.bat scripts-migrations             Migrations seulement
echo   khidmeti.bat scripts-seeds                  Seeds seulement
echo   khidmeti.bat scripts-001_phone_auth_indexes Une migration precise
echo   khidmeti.bat scripts-seed-workers           Un seed precis
echo   khidmeti.bat scripts-seed-workers --clear   Seed avec flag
echo.
echo   Structure attendue :
echo     scripts\migrations\*.js         ^(mongosh dans khidmeti-mongo^)
echo     apps\api\src\scripts\seeds\*.ts ^(ts-node dans khidmeti-api^)
echo.
goto :eof

:: ── START ─────────────────────────────────────────────────────────────────────
:start
echo.
echo ══════════════════════════════════════════════
echo   Demarrage de Khidmeti Backend...
echo ══════════════════════════════════════════════
if not exist ".env" (
  if exist ".env.example" (
    copy ".env.example" ".env" >nul
    echo ATTENTION : .env cree depuis .env.example — configurez FIREBASE_* et les cles IA
  )
)
if not exist "logs"              mkdir logs
if not exist "backups\mongodb"   mkdir backups\mongodb
if not exist "backups\minio"     mkdir backups\minio
if not exist "data\mongodb"      mkdir data\mongodb
if not exist "data\redis"        mkdir data\redis
if not exist "data\qdrant"       mkdir data\qdrant
if not exist "data\minio"        mkdir data\minio
docker compose up -d
echo.
echo   Attente 15s...
timeout /t 15 /nobreak >nul
call :health
call :dns
goto :eof

:: ── STOP ──────────────────────────────────────────────────────────────────────
:stop
docker compose down
echo Services arretes.
goto :eof

:: ── RESTART ───────────────────────────────────────────────────────────────────
:restart
call :stop
timeout /t 3 /nobreak >nul
call :start
goto :eof

:: ── BUILD ─────────────────────────────────────────────────────────────────────
:build
docker compose build --no-cache api
echo Build termine.
goto :eof

:rebuild
call :build
call :start
goto :eof

:: ── HEALTH ────────────────────────────────────────────────────────────────────
:health
echo.
echo ══════════════════════════════════════════════
echo   Etat des services
echo ══════════════════════════════════════════════
echo.
curl -s -o nul -w "  NestJS API  (3000) : HTTP %%{http_code}\n" http://localhost:3000/health     2>nul || echo   NestJS API  (3000) : HORS LIGNE
curl -s -o nul -w "  nginx       (80)   : HTTP %%{http_code}\n" http://localhost/health           2>nul || echo   nginx       (80)   : HORS LIGNE
curl -s -o nul -w "  Qdrant      (6333) : HTTP %%{http_code}\n" http://localhost:6333/healthz    2>nul || echo   Qdrant      (6333) : HORS LIGNE
curl -s -o nul -w "  MinIO API   (9001) : HTTP %%{http_code}\n" http://localhost:9001/minio/health/live 2>nul || echo   MinIO       (9001) : HORS LIGNE
echo.
echo   Pour MongoDB et Redis : docker ps --filter name=khidmeti
echo.
goto :eof

:: ── STATUS ────────────────────────────────────────────────────────────────────
:status
docker ps --filter "name=khidmeti" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
goto :eof

:: ── LOGS ──────────────────────────────────────────────────────────────────────
:logs
docker compose logs --tail=100 -f
goto :eof

:logs_api
docker compose logs -f api
goto :eof

:: ── DNS / URLs ────────────────────────────────────────────────────────────────
:dns
echo.
echo ══════════════════════════════════════════════
echo   URLs des services
echo ══════════════════════════════════════════════
echo.
echo   API REST       :  http://localhost:3000
echo   API via nginx  :  http://localhost:80
echo   Swagger docs   :  http://localhost:3000/api/docs
echo   Mongo Express  :  http://localhost:8081
echo   Qdrant UI      :  http://localhost:6333/dashboard
echo   MinIO console  :  http://localhost:9002
echo   MinIO API (S3) :  http://localhost:9001
echo.
echo ══════════════════════════════════════════════
echo   Config Flutter (meme WiFi)
echo   IP locale : %LOCAL_IP%
echo ══════════════════════════════════════════════
echo.
echo   flutter run --dart-define=API_BASE_URL=http://%LOCAL_IP%:80
echo.
:: Afficher le domaine ngrok s'il est configuré
set NGROK_DOMAIN_DNS=
for /f "tokens=2 delims==" %%a in ('findstr "^NGROK_DOMAIN=" .env 2^>nul') do set NGROK_DOMAIN_DNS=%%a
if not "%NGROK_DOMAIN_DNS%"=="" (
  echo   Tunnel ngrok : https://%NGROK_DOMAIN_DNS%
  echo   flutter run --dart-define=API_BASE_URL=https://%NGROK_DOMAIN_DNS%
  echo.
) else (
  echo   OU : collez l'URL Quick Tunnel dans Firebase Remote Config
  echo        cle : api_base_url
  echo.
)
goto :eof

:: ── TUNNEL CLOUDFLARE ─────────────────────────────────────────────────────────
:tunnel
echo.
echo   Ctrl+C pour arreter.  URL aleatoire — change a chaque demarrage.
echo   Pour une URL permanente : khidmeti.bat ngrok
echo.
where cloudflared >nul 2>&1
if %errorlevel% neq 0 (
  echo ERREUR : cloudflared introuvable.
  echo Telecharger : https://github.com/cloudflare/cloudflared/releases/latest
  exit /b 1
)
cloudflared tunnel --url http://localhost:80
goto :eof

:: ══════════════════════════════════════════════════════════════════════════════
:: TUNNEL NGROK — Domaine statique PERMANENT
:: ══════════════════════════════════════════════════════════════════════════════

:ngrok_install
echo.
echo ══════════════════════════════════════════════
echo   Installation de ngrok (Windows)
echo ══════════════════════════════════════════════
echo.
where ngrok >nul 2>&1
if %errorlevel% equ 0 (
  echo   ngrok deja installe.
  ngrok --version
  goto :eof
)
echo   Telechargement de ngrok...
curl -sL -o "%TEMP%\ngrok.zip" "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-windows-amd64.zip"
if %errorlevel% neq 0 (
  echo   ERREUR : telechargement echoue.
  echo   Telechargez manuellement : https://ngrok.com/download
  goto :eof
)
powershell -Command "Expand-Archive -Path '%TEMP%\ngrok.zip' -DestinationPath 'C:\ngrok' -Force" >nul 2>&1
echo.
echo   ngrok extrait dans C:\ngrok\
echo.
echo   IMPORTANT : ajoutez C:\ngrok\ a votre variable PATH :
echo   Panneau de configuration -^> Systeme -^> Variables d'environnement
echo   OU ouvrez PowerShell en admin et tapez :
echo   [System.Environment]::SetEnvironmentVariable('PATH', $env:PATH+';C:\ngrok', 'Machine')
echo.
echo   Etapes suivantes :
echo   1. Compte gratuit (sans CB) : https://dashboard.ngrok.com/signup
echo   2. Token         : https://dashboard.ngrok.com/get-started/your-authtoken
echo   3. Domaine       : https://dashboard.ngrok.com/domains
echo   4. khidmeti.bat ngrok
echo.
goto :eof

:ngrok
echo.
echo ══════════════════════════════════════════════
echo   Tunnel ngrok — Domaine statique permanent
echo ══════════════════════════════════════════════
echo.
where ngrok >nul 2>&1
if %errorlevel% neq 0 (
  echo   ERREUR : ngrok introuvable.
  echo   Lancez d'abord : khidmeti.bat ngrok-install
  echo.
  exit /b 1
)

:: ── Lire NGROK_AUTH_TOKEN depuis .env ────────────────────────────────────────
set NGROK_TOKEN=
for /f "tokens=2 delims==" %%a in ('findstr "^NGROK_AUTH_TOKEN=" .env 2^>nul') do set NGROK_TOKEN=%%a
set NGROK_TOKEN=%NGROK_TOKEN: =%

if "%NGROK_TOKEN%"=="" (
  echo   Etape 1/2 — Auth Token ngrok
  echo   Obtenez-le sur : https://dashboard.ngrok.com/get-started/your-authtoken
  echo.
  set /p NGROK_TOKEN="  Collez votre Auth Token : "
  :: Sauvegarder dans .env
  findstr /v "^NGROK_AUTH_TOKEN=" .env > .env.tmp 2>nul
  echo NGROK_AUTH_TOKEN=!NGROK_TOKEN!>> .env.tmp
  move /y .env.tmp .env >nul
  echo   Token sauvegarde dans .env
  echo.
)

:: Configurer ngrok
ngrok config add-authtoken %NGROK_TOKEN% >nul 2>&1

:: ── Lire NGROK_DOMAIN depuis .env ────────────────────────────────────────────
set NGROK_DOMAIN=
for /f "tokens=2 delims==" %%a in ('findstr "^NGROK_DOMAIN=" .env 2^>nul') do set NGROK_DOMAIN=%%a
set NGROK_DOMAIN=%NGROK_DOMAIN: =%

if "%NGROK_DOMAIN%"=="" (
  echo   Etape 2/2 — Domaine statique ngrok
  echo   Reservez-en un sur : https://dashboard.ngrok.com/domains
  echo   Exemple : khidmeti-oran.ngrok-free.app
  echo.
  set /p NGROK_DOMAIN="  Entrez votre domaine statique : "
  :: Sauvegarder dans .env
  findstr /v "^NGROK_DOMAIN=" .env > .env.tmp 2>nul
  echo NGROK_DOMAIN=!NGROK_DOMAIN!>> .env.tmp
  move /y .env.tmp .env >nul
  echo   Domaine sauvegarde dans .env (ne sera plus demande^)
  echo.
)

echo   Demarrage du tunnel...
echo.
echo   URL permanente : https://%NGROK_DOMAIN%
echo.
echo   flutter run --dart-define=API_BASE_URL=https://%NGROK_DOMAIN%
echo.
echo   -^> Copiez cette URL dans Firebase Remote Config (cle : api_base_url^)
echo   -^> Ctrl+C pour arreter
echo.
ngrok http --domain=%NGROK_DOMAIN% 80
goto :eof

:ngrok_reset
:: Supprimer NGROK_AUTH_TOKEN et NGROK_DOMAIN du .env
findstr /v "^NGROK_AUTH_TOKEN=" .env > .env.tmp 2>nul
move /y .env.tmp .env >nul
findstr /v "^NGROK_DOMAIN=" .env > .env.tmp 2>nul
move /y .env.tmp .env >nul
echo Config ngrok supprimee — relancez : khidmeti.bat ngrok
goto :eof

:: ── FLUTTER RUN ───────────────────────────────────────────────────────────────
:flutter_run
echo.
echo   Lancement Flutter avec API_BASE_URL=http://%LOCAL_IP%:80
echo.
flutter run --dart-define=API_BASE_URL=http://%LOCAL_IP%:80
goto :eof

:: ── SHELL ─────────────────────────────────────────────────────────────────────
:shell_api
docker exec -it khidmeti-api /bin/sh
goto :eof

:shell_mongo
for /f "tokens=2 delims==" %%a in ('findstr "^MONGO_ROOT_USER" .env') do set MONGO_USER=%%a
for /f "tokens=2 delims==" %%a in ('findstr "^MONGO_ROOT_PASSWORD" .env') do set MONGO_PASS=%%a
docker exec -it khidmeti-mongo mongosh -u "%MONGO_USER%" -p "%MONGO_PASS%" --authenticationDatabase admin khidmeti
goto :eof

:: ── TEST API ──────────────────────────────────────────────────────────────────
:test_api
echo.
echo   [1] Health :
curl -s http://localhost:3000/health
echo.
echo   [2] Swagger (code HTTP) :
curl -s -o nul -w "%%{http_code}" http://localhost:3000/api/docs
echo.
echo   Endpoints proteges : jeton Firebase Bearer requis.
echo   Swagger UI : http://localhost:3000/api/docs
echo.
goto :eof

:: ══════════════════════════════════════════════════════════════════════════════
:: SCRIPTS — Migrations + Seeds
:: ══════════════════════════════════════════════════════════════════════════════

:scripts
echo.
echo ══════════════════════════════════════════════
echo   Scripts : migrations + seeds
echo ══════════════════════════════════════════════
call :scripts_migrations
call :scripts_seeds
goto :eof

:scripts_migrations
echo.
echo ══════════════════════════════════════════════
echo   Migrations MongoDB
echo ══════════════════════════════════════════════
echo.
for /f "tokens=2 delims==" %%a in ('findstr "^MONGO_ROOT_USER" .env 2^>nul') do set MIG_MONGO_USER=%%a
for /f "tokens=2 delims==" %%a in ('findstr "^MONGO_ROOT_PASSWORD" .env 2^>nul') do set MIG_MONGO_PASS=%%a
set MIG_COUNT=0
set MIG_FAILED=0
if not exist "scripts\migrations\*.js" (
  echo   Aucune migration trouvee dans scripts\migrations\
  echo.
  goto :migrations_done
)
for %%f in (scripts\migrations\*.js) do (
  echo   ^> %%~nxf
  docker exec -i khidmeti-mongo mongosh --quiet ^
    -u "%MIG_MONGO_USER%" -p "%MIG_MONGO_PASS%" ^
    --authenticationDatabase admin khidmeti < "%%f"
  if !errorlevel! equ 0 (
    echo     OK %%~nxf
    set /a MIG_COUNT+=1
  ) else (
    echo     ECHEC %%~nxf
    set /a MIG_FAILED+=1
  )
  echo.
)
:migrations_done
echo   Resultat : %MIG_COUNT% OK  ^|  %MIG_FAILED% echec(s)
echo.
if %MIG_FAILED% gtr 0 exit /b 1
goto :eof

:scripts_seeds
echo.
echo ══════════════════════════════════════════════
echo   Seeds TypeScript
echo ══════════════════════════════════════════════
echo.
set SEED_COUNT=0
set SEED_FAILED=0
if not exist "apps\api\src\scripts\seeds\*.ts" (
  echo   Aucun seed trouve dans apps\api\src\scripts\seeds\
  echo.
  goto :seeds_done
)
for %%f in (apps\api\src\scripts\seeds\*.ts) do (
  echo   ^> %%~nxf %ARGS%
  docker exec khidmeti-api ^
    npx ts-node --project tsconfig.json "src/scripts/seeds/%%~nxf" %ARGS%
  if !errorlevel! equ 0 (
    echo     OK %%~nxf
    set /a SEED_COUNT+=1
  ) else (
    echo     ECHEC %%~nxf
    set /a SEED_FAILED+=1
  )
  echo.
)
:seeds_done
echo   Resultat : %SEED_COUNT% OK  ^|  %SEED_FAILED% echec(s)
echo.
if %SEED_FAILED% gtr 0 exit /b 1
goto :eof

:scripts_one
echo.
if exist "scripts\migrations\%SCRIPT_NAME%.js" (
  echo   ^> Migration : %SCRIPT_NAME%.js
  echo.
  for /f "tokens=2 delims==" %%a in ('findstr "^MONGO_ROOT_USER" .env 2^>nul') do set ONE_USER=%%a
  for /f "tokens=2 delims==" %%a in ('findstr "^MONGO_ROOT_PASSWORD" .env 2^>nul') do set ONE_PASS=%%a
  docker exec -i khidmeti-mongo mongosh --quiet ^
    -u "%ONE_USER%" -p "%ONE_PASS%" ^
    --authenticationDatabase admin khidmeti < "scripts\migrations\%SCRIPT_NAME%.js"
  if !errorlevel! equ 0 (
    echo.
    echo   OK %SCRIPT_NAME%.js
  ) else (
    echo.
    echo   ECHEC %SCRIPT_NAME%.js
    exit /b 1
  )
  echo.
  goto :eof
)
if exist "apps\api\src\scripts\seeds\%SCRIPT_NAME%.ts" (
  echo   ^> Seed : %SCRIPT_NAME%.ts %ARGS%
  echo.
  docker exec khidmeti-api ^
    npx ts-node --project tsconfig.json "src/scripts/seeds/%SCRIPT_NAME%.ts" %ARGS%
  if !errorlevel! equ 0 (
    echo.
    echo   OK %SCRIPT_NAME%.ts
  ) else (
    echo.
    echo   ECHEC %SCRIPT_NAME%.ts
    exit /b 1
  )
  echo.
  goto :eof
)
echo   ERREUR : Script '%SCRIPT_NAME%' introuvable.
echo.
echo   Cherche dans :
echo     scripts\migrations\%SCRIPT_NAME%.js
echo     apps\api\src\scripts\seeds\%SCRIPT_NAME%.ts
echo.
exit /b 1

:: ── CLEAN ─────────────────────────────────────────────────────────────────────
:clean
echo.
echo   ATTENTION : suppression de TOUTES les donnees Khidmeti.
set /p CONFIRM="  Taper YES pour confirmer : "
if /i "%CONFIRM%"=="YES" (
  docker compose down -v --remove-orphans
  if exist "data\mongodb" rmdir /s /q data\mongodb
  if exist "data\redis"   rmdir /s /q data\redis
  if exist "data\qdrant"  rmdir /s /q data\qdrant
  if exist "data\minio"   rmdir /s /q data\minio
  echo Nettoyage termine.
) else (
  echo Annule.
)
goto :eof
