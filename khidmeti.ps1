# ══════════════════════════════════════════════════════════════════════════════
# KHIDMETI BACKEND — PowerShell Script
# Usage:  .\khidmeti.ps1 [command] [args]
# Alias:  Set-Alias kh .\khidmeti.ps1   (ajouter dans $PROFILE)
#
# Requirements: Docker Desktop, PowerShell 5+
# ══════════════════════════════════════════════════════════════════════════════
param(
  [Parameter(Position=0)]
  [string]$Command = "help",

  # Arguments optionnels transmis aux seeds (ex: --clear)
  [Parameter(Position=1, ValueFromRemainingArguments)]
  [string[]]$ScriptArgs = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Couleurs ──────────────────────────────────────────────────────────────────
function Write-Header([string]$text) {
  Write-Host "`n══════════════════════════════════════════════" -ForegroundColor Cyan
  Write-Host "  $text" -ForegroundColor White
  Write-Host "══════════════════════════════════════════════" -ForegroundColor Cyan
}
function Write-Ok([string]$msg)    { Write-Host "  ✅ $msg" -ForegroundColor Green  }
function Write-Warn([string]$msg)  { Write-Host "  ⚠️  $msg" -ForegroundColor Yellow }
function Write-Err([string]$msg)   { Write-Host "  ❌ $msg" -ForegroundColor Red    }
function Write-Info([string]$msg)  { Write-Host "  $msg"    -ForegroundColor Gray   }
function Write-Step([string]$msg)  { Write-Host "  → $msg"  -ForegroundColor White  }

# ── IP locale ─────────────────────────────────────────────────────────────────
function Get-LocalIp {
  $candidates = Get-NetIPAddress -AddressFamily IPv4 -PrefixOrigin Dhcp 2>$null |
    Where-Object { $_.IPAddress -match '^(192\.168|10\.|172\.(1[6-9]|2\d|3[01]))' } |
    Select-Object -First 1
  if ($candidates) { return $candidates.IPAddress }
  return "127.0.0.1"
}
$LOCAL_IP = Get-LocalIp

# ── Lecture .env ──────────────────────────────────────────────────────────────
function Get-EnvValue([string]$key) {
  if (-not (Test-Path ".env")) { return "" }
  $line = Get-Content ".env" | Where-Object { $_ -match "^$key=" } | Select-Object -First 1
  if ($line) { return ($line -split "=", 2)[1].Trim() }
  return ""
}

# ── Écriture d'une valeur dans .env (crée ou remplace) ───────────────────────
function Set-EnvValue([string]$key, [string]$value) {
  if (-not (Test-Path ".env")) { return }
  $content = Get-Content ".env"
  if ($content | Where-Object { $_ -match "^$key=" }) {
    $content = $content -replace "^$key=.*", "$key=$value"
  } else {
    $content += "$key=$value"
  }
  $content | Set-Content ".env" -Encoding UTF8
}

# ── Suppression d'une clé dans .env ───────────────────────────────────────────
function Remove-EnvValue([string]$key) {
  if (-not (Test-Path ".env")) { return }
  $content = Get-Content ".env" | Where-Object { $_ -notmatch "^$key=" }
  $content | Set-Content ".env" -Encoding UTF8
}

# ── Health check ──────────────────────────────────────────────────────────────
function Test-Endpoint([string]$label, [string]$url) {
  try {
    $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 5 -ErrorAction SilentlyContinue
    if ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 300) {
      Write-Ok "$label → HTTP $($resp.StatusCode)"
    } else {
      Write-Err "$label → HTTP $($resp.StatusCode)"
    }
  } catch {
    Write-Err "$label → HORS LIGNE"
  }
}

# ── Exécution migration JS ────────────────────────────────────────────────────
function Invoke-Migration([string]$filePath) {
  $mongoUser = Get-EnvValue "MONGO_ROOT_USER"
  $mongoPass = Get-EnvValue "MONGO_ROOT_PASSWORD"
  $name      = Split-Path $filePath -Leaf

  Write-Step "Migration : $name"
  $content = Get-Content $filePath -Raw
  $content | docker exec -i khidmeti-mongo mongosh `
    --quiet `
    -u $mongoUser -p $mongoPass `
    --authenticationDatabase admin khidmeti
  return $LASTEXITCODE -eq 0
}

# ── Exécution seed TS ─────────────────────────────────────────────────────────
function Invoke-Seed([string]$filePath, [string[]]$extraArgs = @()) {
  $name     = Split-Path $filePath -Leaf
  $argsStr  = if ($extraArgs.Count -gt 0) { " " + ($extraArgs -join " ") } else { "" }

  Write-Step "Seed : $name$argsStr"
  docker exec khidmeti-api `
    npx ts-node --project tsconfig.json "src/scripts/seeds/$name" @extraArgs
  return $LASTEXITCODE -eq 0
}

# ══════════════════════════════════════════════════════════════════════════════
# COMMANDES
# ══════════════════════════════════════════════════════════════════════════════

# Détection de la commande scripts-<nom> (pattern dynamique)
if ($Command -like "scripts-*" -and
    $Command -ne "scripts-migrations" -and
    $Command -ne "scripts-seeds") {

  $scriptName = $Command.Substring(8)
  $migPath  = "scripts\migrations\$scriptName.js"
  $seedPath = "apps\api\src\scripts\seeds\$scriptName.ts"

  Write-Host ""

  if (Test-Path $migPath) {
    $ok = Invoke-Migration $migPath
    if ($ok) { Write-Ok "$scriptName.js OK" } else { Write-Err "$scriptName.js ECHEC"; exit 1 }
  } elseif (Test-Path $seedPath) {
    $ok = Invoke-Seed $seedPath $ScriptArgs
    if ($ok) { Write-Ok "$scriptName.ts OK" } else { Write-Err "$scriptName.ts ECHEC"; exit 1 }
  } else {
    Write-Err "Script '$scriptName' introuvable."
    Write-Host ""
    Write-Info "Cherche dans :"
    Write-Info "  $migPath"
    Write-Info "  $seedPath"
    Write-Host ""
    Write-Info "Scripts disponibles :"
    Write-Info "  Migrations :"
    $migs = Get-ChildItem "scripts\migrations\*.js" -ErrorAction SilentlyContinue
    if ($migs) { $migs | ForEach-Object { Write-Info "    $($_.BaseName)" } }
    else        { Write-Info "    (aucune)" }
    Write-Info "  Seeds :"
    $seeds = Get-ChildItem "apps\api\src\scripts\seeds\*.ts" -ErrorAction SilentlyContinue
    if ($seeds) { $seeds | ForEach-Object { Write-Info "    $($_.BaseName)" } }
    else         { Write-Info "    (aucun)" }
    Write-Host ""
    exit 1
  }

  Write-Host ""
  exit 0
}

switch ($Command.ToLower()) {

  # ── help ────────────────────────────────────────────────────────────────────
  "help" {
    Write-Header "KHIDMETI — Commandes PowerShell"
    Write-Host "  IP locale : $LOCAL_IP" -ForegroundColor Yellow
    Write-Host ""
    $cmds = @(
      @("[SERVICES]",              ""),
      @("start",                   "Demarrer tous les services"),
      @("stop",                    "Arreter tous les services"),
      @("restart",                 "Redemarrer"),
      @("build",                   "Builder l'image NestJS"),
      @("rebuild",                 "Rebuild + redemarrage"),
      @("health",                  "Verifier la sante des services"),
      @("status",                  "Statut des conteneurs"),
      @("logs",                    "Tous les logs (Ctrl+C pour quitter)"),
      @("logs-api",                "Logs NestJS uniquement"),
      @("dns",                     "URLs + config Flutter"),
      @("flutter-run",             "Lancer Flutter avec l'IP locale"),
      @("shell-api",               "Shell dans le conteneur NestJS"),
      @("shell-mongo",             "mongosh dans MongoDB"),
      @("test-api",                "Tester les endpoints"),
      @("clean",                   "Supprimer toutes les donnees (DESTRUCTIF)"),
      @("",                        ""),
      @("[TUNNEL — Acces distant]", ""),
      @("tunnel",                  "Cloudflare Quick Tunnel (URL aleatoire)"),
      @("ngrok",                   "Tunnel ngrok PERMANENT — recommande"),
      @("ngrok-install",           "Installer ngrok"),
      @("ngrok-reset",             "Changer token ou domaine ngrok"),
      @("",                        ""),
      @("[SCRIPTS]",               ""),
      @("scripts",                 "Tout executer (migrations + seeds)"),
      @("scripts-migrations",      "Migrations seulement"),
      @("scripts-seeds",           "Seeds seulement"),
      @("scripts-001_phone_...    ","Une migration precise"),
      @("scripts-seed-workers",    "Un seed precis"),
      @("scripts-seed-workers --clear", "Seed avec flag --clear")
    )
    foreach ($c in $cmds) {
      if ($c[1] -eq "" -and $c[0] -ne "") {
        Write-Host ""
        Write-Host "  $($c[0])" -ForegroundColor Cyan
      } elseif ($c[0] -ne "") {
        Write-Host ("  {0,-35} {1}" -f $c[0], $c[1]) -ForegroundColor Gray
      }
    }
    Write-Host ""
    Write-Info "Structure attendue :"
    Write-Info "  scripts\migrations\*.js         -> mongosh dans khidmeti-mongo"
    Write-Info "  apps\api\src\scripts\seeds\*.ts -> ts-node dans khidmeti-api"
    Write-Host ""
  }

  # ── start ───────────────────────────────────────────────────────────────────
  "start" {
    Write-Header "Demarrage de Khidmeti Backend..."
    @("logs","backups\mongodb","backups\minio","data\mongodb","data\redis","data\qdrant","data\minio") |
      ForEach-Object { if (-not (Test-Path $_)) { New-Item -ItemType Directory -Path $_ -Force | Out-Null } }
    if (-not (Test-Path ".env")) {
      if (Test-Path ".env.example") {
        Copy-Item ".env.example" ".env"
        Write-Warn ".env cree depuis .env.example — configurez FIREBASE_* et vos cles IA"
      }
    }
    docker compose up -d
    Write-Info "Attente 15s..."
    Start-Sleep -Seconds 15
    & $PSCommandPath health
    & $PSCommandPath dns
  }

  # ── stop ────────────────────────────────────────────────────────────────────
  "stop" {
    docker compose down
    Write-Ok "Services arretes."
  }

  # ── restart ─────────────────────────────────────────────────────────────────
  "restart" {
    & $PSCommandPath stop
    Start-Sleep -Seconds 3
    & $PSCommandPath start
  }

  # ── build ───────────────────────────────────────────────────────────────────
  "build" {
    docker compose build --no-cache api
    Write-Ok "Build termine."
  }

  "rebuild" {
    & $PSCommandPath build
    & $PSCommandPath start
  }

  # ── health ──────────────────────────────────────────────────────────────────
  "health" {
    Write-Header "Etat des services"
    Test-Endpoint "NestJS API  (3000)" "http://localhost:3000/health"
    Test-Endpoint "nginx       (80)  " "http://localhost/health"
    Test-Endpoint "Qdrant      (6333)" "http://localhost:6333/healthz"
    Test-Endpoint "MinIO API   (9001)" "http://localhost:9001/minio/health/live"
    Write-Host ""
    Write-Info "MongoDB / Redis : docker ps --filter name=khidmeti"
    Write-Host ""
  }

  # ── status ──────────────────────────────────────────────────────────────────
  "status" {
    docker ps --filter "name=khidmeti" --format "table {{.Names}}`t{{.Status}}`t{{.Ports}}"
  }

  # ── logs ────────────────────────────────────────────────────────────────────
  "logs" {
    docker compose logs --tail=100 -f
  }

  "logs-api" {
    docker compose logs -f api
  }

  # ── dns ─────────────────────────────────────────────────────────────────────
  "dns" {
    Write-Header "URLs des services"
    Write-Host "  API REST       :  http://localhost:3000"          -ForegroundColor White
    Write-Host "  API via nginx  :  http://localhost:80"            -ForegroundColor White
    Write-Host "  Swagger docs   :  http://localhost:3000/api/docs" -ForegroundColor White
    Write-Host "  Mongo Express  :  http://localhost:8081"          -ForegroundColor Gray
    Write-Host "  Qdrant UI      :  http://localhost:6333/dashboard"-ForegroundColor Gray
    Write-Host "  MinIO console  :  http://localhost:9002"          -ForegroundColor Gray
    Write-Host ""
    Write-Header "Config Flutter (meme WiFi)"
    Write-Host "  IP locale : $LOCAL_IP" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  flutter run --dart-define=API_BASE_URL=http://$($LOCAL_IP):80" -ForegroundColor Cyan

    $ngrokDomain = Get-EnvValue "NGROK_DOMAIN"
    if ($ngrokDomain -ne "") {
      Write-Host ""
      Write-Host "  Tunnel ngrok : https://$ngrokDomain" -ForegroundColor Green
      Write-Host "  flutter run --dart-define=API_BASE_URL=https://$ngrokDomain" -ForegroundColor Cyan
    } else {
      Write-Host ""
      Write-Info "OU : collez l'URL Quick Tunnel dans Firebase Remote Config (cle : api_base_url)"
    }
    Write-Host ""
  }

  # ── tunnel (Cloudflare) ─────────────────────────────────────────────────────
  "tunnel" {
    Write-Header "Cloudflare Quick Tunnel (URL aleatoire)"
    Write-Host ""
    Write-Host "  Ctrl+C pour arreter." -ForegroundColor Gray
    Write-Host "  Pour une URL permanente : .\khidmeti.ps1 ngrok" -ForegroundColor Yellow
    Write-Host ""
    $cf = Get-Command cloudflared -ErrorAction SilentlyContinue
    if (-not $cf) {
      Write-Err "cloudflared introuvable."
      Write-Info "https://github.com/cloudflare/cloudflared/releases/latest"
      exit 1
    }
    cloudflared tunnel --url http://localhost:80
  }

  # ══════════════════════════════════════════════════════════════════════════════
  # TUNNEL NGROK — Domaine statique PERMANENT
  #
  #  Avantages :
  #    ✅ URL identique a chaque redemarrage (ex: khidmeti-oran.ngrok-free.app)
  #    ✅ Gratuit, sans carte bancaire
  #    ✅ Token + domaine sauvegardes dans .env → saisis 1 seule fois
  #
  #  Premiere utilisation :
  #    1. Compte sur https://dashboard.ngrok.com/signup
  #    2. Domaine sur https://dashboard.ngrok.com/domains
  #    3. .\khidmeti.ps1 ngrok  →  entrez token + domaine (1 seule fois)
  #
  #  Utilisations suivantes :
  #    .\khidmeti.ps1 ngrok  →  demarre directement
  # ══════════════════════════════════════════════════════════════════════════════

  "ngrok-install" {
    Write-Header "Installation de ngrok (Windows)"
    Write-Host ""

    $ngrokCmd = Get-Command ngrok -ErrorAction SilentlyContinue
    if ($ngrokCmd) {
      Write-Ok "ngrok deja installe : $(ngrok --version)"
    } else {
      Write-Info "Telechargement de ngrok..."
      $zipPath = "$env:TEMP\ngrok.zip"
      $destPath = "C:\ngrok"
      try {
        Invoke-WebRequest -Uri "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-windows-amd64.zip" `
          -OutFile $zipPath -UseBasicParsing
        if (-not (Test-Path $destPath)) { New-Item -ItemType Directory -Path $destPath -Force | Out-Null }
        Expand-Archive -Path $zipPath -DestinationPath $destPath -Force
        Remove-Item $zipPath -ErrorAction SilentlyContinue
        Write-Ok "ngrok extrait dans $destPath"
        Write-Host ""
        Write-Host "  IMPORTANT : ajoutez $destPath a votre PATH :" -ForegroundColor Yellow
        Write-Host "  (ou lancez cette commande PowerShell en admin)" -ForegroundColor Gray
        Write-Host '  [System.Environment]::SetEnvironmentVariable("PATH", $env:PATH+";C:\ngrok", "Machine")' -ForegroundColor Cyan
      } catch {
        Write-Err "Echec telechargement : $_"
        Write-Info "Telechargez manuellement : https://ngrok.com/download"
      }
    }

    Write-Host ""
    Write-Info "Etapes suivantes :"
    Write-Info "  1. Compte gratuit (sans CB) : https://dashboard.ngrok.com/signup"
    Write-Info "  2. Token  : https://dashboard.ngrok.com/get-started/your-authtoken"
    Write-Info "  3. Domaine : https://dashboard.ngrok.com/domains"
    Write-Info "  4. .\khidmeti.ps1 ngrok"
    Write-Host ""
  }

  "ngrok" {
    Write-Header "Tunnel ngrok — Domaine statique permanent"
    Write-Host ""

    # ── Vérifier que ngrok est installé ──────────────────────────────────────
    $ngrokCmd = Get-Command ngrok -ErrorAction SilentlyContinue
    if (-not $ngrokCmd) {
      Write-Err "ngrok introuvable."
      Write-Info "Lancez d'abord : .\khidmeti.ps1 ngrok-install"
      Write-Host ""
      exit 1
    }

    # ── Lire / saisir NGROK_AUTH_TOKEN ────────────────────────────────────────
    $ngrokToken = Get-EnvValue "NGROK_AUTH_TOKEN"
    if ($ngrokToken -eq "") {
      Write-Host "  ┌─────────────────────────────────────────────────────┐" -ForegroundColor Cyan
      Write-Host "  │  Etape 1/2 — Auth Token ngrok                       │" -ForegroundColor Cyan
      Write-Host "  │  https://dashboard.ngrok.com/get-started/your-authtoken │" -ForegroundColor Cyan
      Write-Host "  └─────────────────────────────────────────────────────┘" -ForegroundColor Cyan
      Write-Host ""
      $ngrokToken = Read-Host "  Collez votre Auth Token"
      Set-EnvValue "NGROK_AUTH_TOKEN" $ngrokToken
      Write-Ok "Token sauvegarde dans .env"
      Write-Host ""
    }

    # Configurer le token
    ngrok config add-authtoken $ngrokToken 2>$null | Out-Null

    # ── Lire / saisir NGROK_DOMAIN ────────────────────────────────────────────
    $ngrokDomain = Get-EnvValue "NGROK_DOMAIN"
    if ($ngrokDomain -eq "") {
      Write-Host "  ┌─────────────────────────────────────────────────────┐" -ForegroundColor Cyan
      Write-Host "  │  Etape 2/2 — Domaine statique ngrok                 │" -ForegroundColor Cyan
      Write-Host "  │  Reservez-en un : https://dashboard.ngrok.com/domains │" -ForegroundColor Cyan
      Write-Host "  │  Exemple : khidmeti-oran.ngrok-free.app             │" -ForegroundColor Cyan
      Write-Host "  └─────────────────────────────────────────────────────┘" -ForegroundColor Cyan
      Write-Host ""
      $ngrokDomain = Read-Host "  Entrez votre domaine statique"
      Set-EnvValue "NGROK_DOMAIN" $ngrokDomain
      Write-Ok "Domaine sauvegarde dans .env (ne sera plus demande)"
      Write-Host ""
    }

    # ── Démarrer le tunnel ─────────────────────────────────────────────────────
    Write-Host "  Demarrage du tunnel..." -ForegroundColor White
    Write-Host ""
    Write-Host "  URL permanente : https://$ngrokDomain" -ForegroundColor Green
    Write-Host ""
    Write-Host "  flutter run --dart-define=API_BASE_URL=https://$ngrokDomain" -ForegroundColor Cyan
    Write-Host ""
    Write-Info "  → Copiez cette URL dans Firebase Remote Config (cle : api_base_url)"
    Write-Info "  → Ctrl+C pour arreter"
    Write-Host ""

    ngrok http "--domain=$ngrokDomain" 80
  }

  "ngrok-reset" {
    Remove-EnvValue "NGROK_AUTH_TOKEN"
    Remove-EnvValue "NGROK_DOMAIN"
    Write-Ok "Config ngrok supprimee de .env — relancez : .\khidmeti.ps1 ngrok"
  }

  # ── flutter-run ─────────────────────────────────────────────────────────────
  "flutter-run" {
    Write-Host ""
    Write-Host "  Lancement Flutter avec API_BASE_URL=http://$($LOCAL_IP):80" -ForegroundColor Cyan
    Write-Host ""
    flutter run "--dart-define=API_BASE_URL=http://$($LOCAL_IP):80"
  }

  # ── shells ──────────────────────────────────────────────────────────────────
  "shell-api" {
    docker exec -it khidmeti-api /bin/sh
  }

  "shell-mongo" {
    $user = Get-EnvValue "MONGO_ROOT_USER"
    $pass = Get-EnvValue "MONGO_ROOT_PASSWORD"
    docker exec -it khidmeti-mongo mongosh -u $user -p $pass --authenticationDatabase admin khidmeti
  }

  # ── test-api ────────────────────────────────────────────────────────────────
  "test-api" {
    Write-Header "Tests API"
    Write-Host "  [1] Health :"
    try { (Invoke-WebRequest -Uri "http://localhost:3000/health" -UseBasicParsing).Content } catch { Write-Err "HORS LIGNE" }
    Write-Host ""
    Write-Host "  [2] Swagger :"
    try { Write-Ok "HTTP $((Invoke-WebRequest -Uri 'http://localhost:3000/api/docs' -UseBasicParsing).StatusCode)" } catch { Write-Err "HORS LIGNE" }
    Write-Host ""
    Write-Info "Swagger UI : http://localhost:3000/api/docs"
    Write-Host ""
  }

  # ── scripts ─────────────────────────────────────────────────────────────────
  "scripts" {
    Write-Header "Scripts : migrations + seeds"
    & $PSCommandPath scripts-migrations
    & $PSCommandPath scripts-seeds
  }

  "scripts-migrations" {
    Write-Header "Migrations MongoDB"
    $files = Get-ChildItem "scripts\migrations\*.js" -ErrorAction SilentlyContinue
    if (-not $files) {
      Write-Info "Aucune migration trouvee dans scripts\migrations\"
      Write-Host ""
      return
    }
    $ok = 0; $failed = 0
    foreach ($f in $files) {
      $success = Invoke-Migration $f.FullName
      if ($success) { Write-Ok "$($f.Name) OK"; $ok++ }
      else           { Write-Err "$($f.Name) ECHEC"; $failed++ }
      Write-Host ""
    }
    Write-Info "Resultat : $ok OK  |  $failed echec(s)"
    Write-Host ""
    if ($failed -gt 0) { exit 1 }
  }

  "scripts-seeds" {
    Write-Header "Seeds TypeScript"
    $files = Get-ChildItem "apps\api\src\scripts\seeds\*.ts" -ErrorAction SilentlyContinue
    if (-not $files) {
      Write-Info "Aucun seed trouve dans apps\api\src\scripts\seeds\"
      Write-Host ""
      return
    }
    $ok = 0; $failed = 0
    foreach ($f in $files) {
      $success = Invoke-Seed $f.FullName $ScriptArgs
      if ($success) { Write-Ok "$($f.Name) OK"; $ok++ }
      else           { Write-Err "$($f.Name) ECHEC"; $failed++ }
      Write-Host ""
    }
    Write-Info "Resultat : $ok OK  |  $failed echec(s)"
    Write-Host ""
    if ($failed -gt 0) { exit 1 }
  }

  # ── clean ───────────────────────────────────────────────────────────────────
  "clean" {
    Write-Host ""
    Write-Err "ATTENTION : suppression de TOUTES les donnees (MongoDB, Redis, Qdrant, MinIO)"
    $confirm = Read-Host "  Taper YES pour confirmer"
    if ($confirm -eq "YES") {
      docker compose down -v --remove-orphans
      @("data\mongodb","data\redis","data\qdrant","data\minio") |
        Where-Object { Test-Path $_ } |
        ForEach-Object { Remove-Item -Recurse -Force $_ }
      Write-Ok "Nettoyage termine."
    } else {
      Write-Info "Annule."
    }
  }

  # ── defaut ──────────────────────────────────────────────────────────────────
  default {
    Write-Err "Commande inconnue : $Command"
    Write-Info "Utilisation : .\khidmeti.ps1 help"
    exit 1
  }
}
