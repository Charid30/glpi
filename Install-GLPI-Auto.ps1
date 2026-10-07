#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installation silencieuse et automatique de GLPI Agent 1.20.
    Telecharge le MSI depuis GitHub et configure l'agent.

.AUTHOR
    BATIONO Ulrich Rachid Kevin
    Developpeur d'applications
    Expert en Securite Informatique
    Tel      : +226 51 57 82 89 // 66 72 02 32
    WhatsApp : +226 51 57 82 89

.USAGE
    Lancer directement depuis PowerShell (en administrateur) :
    irm https://raw.githubusercontent.com/Charid30/glpi/main/Install-GLPI-Auto.ps1 | iex

.VERSION
    1.0
#>

$ErrorActionPreference = 'Stop'

# --- Configuration -----------------------------------------------------------
$MSI_URL      = 'https://github.com/Charid30/glpi/releases/download/glpi/GLPI-Agent-1.20-x64.msi'
$GLPI_SERVER  = 'http://172.20.10.140/front/inventory.php'
$GLPI_LOCAL   = 'http://localhost:62354'
$MSI_TEMP     = Join-Path $env:TEMP 'GLPI-Agent-1.20-x64.msi'
$LOG_FILE     = Join-Path $env:TEMP ("GLPI-Auto-" + $env:COMPUTERNAME + ".log")

# --- Helpers -----------------------------------------------------------------
function Write-OK   { param([string]$M); Write-Host "  [OK]  $M" -ForegroundColor Green;  Add-Content $LOG_FILE "[$(Get-Date -f 'HH:mm:ss')] OK:   $M" }
function Write-Err  { param([string]$M); Write-Host "  [ERR] $M" -ForegroundColor Red;    Add-Content $LOG_FILE "[$(Get-Date -f 'HH:mm:ss')] ERR:  $M" }
function Write-Step { param([string]$M); Write-Host "  [>>]  $M" -ForegroundColor Cyan;   Add-Content $LOG_FILE "[$(Get-Date -f 'HH:mm:ss')] STEP: $M" }
function Write-Warn { param([string]$M); Write-Host "  [!]   $M" -ForegroundColor Yellow; Add-Content $LOG_FILE "[$(Get-Date -f 'HH:mm:ss')] WARN: $M" }

# --- Debut -------------------------------------------------------------------
Add-Content $LOG_FILE ("=" * 60)
Add-Content $LOG_FILE ("=== Installation demarree le " + (Get-Date) + " sur $env:COMPUTERNAME ===")
Add-Content $LOG_FILE ("=" * 60)

Write-Host ""
Write-Host "  +=====================================================+" -ForegroundColor Cyan
Write-Host "  |   INSTALLATION AUTOMATIQUE GLPI AGENT 1.20         |" -ForegroundColor Cyan
Write-Host "  |   Poste : $($env:COMPUTERNAME.PadRight(41))|" -ForegroundColor Cyan
Write-Host "  +=====================================================+" -ForegroundColor Cyan
Write-Host ""

# --- Etape 1 : Verifier si deja installe ------------------------------------
Write-Step 'Verification installation existante...'
$installed = $null
try {
    $installed = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
                               'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall' -ErrorAction SilentlyContinue |
                 Get-ItemProperty -ErrorAction SilentlyContinue |
                 Where-Object { $_.DisplayName -like '*GLPI*Agent*' }
} catch { }

if ($installed) {
    Write-Warn "GLPI Agent deja installe : $($installed.DisplayName) $($installed.DisplayVersion)"
    Write-Step 'Desinstallation de l ancienne version...'
    try {
        $proc = Start-Process 'msiexec.exe' -ArgumentList "/x `"$($installed.PSChildName)`" /quiet /norestart" -Wait -PassThru
        if ($proc.ExitCode -eq 0) {
            Write-OK 'Ancienne version desinstallee.'
        } else {
            Write-Warn "Desinstallation : code $($proc.ExitCode). On continue quand meme."
        }
    } catch {
        Write-Warn "Impossible de desinstaller l ancienne version : $_"
    }
}

# --- Etape 2 : Telecharger le MSI -------------------------------------------
Write-Step "Telechargement du MSI depuis GitHub..."
Write-Host "  [i]   URL : $MSI_URL" -ForegroundColor DarkCyan

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $wc = New-Object System.Net.WebClient
    $wc.DownloadFile($MSI_URL, $MSI_TEMP)
    $sizeMB = [math]::Round((Get-Item $MSI_TEMP).Length / 1MB, 1)
    Write-OK "MSI telecharge : $MSI_TEMP ($sizeMB MB)"
} catch {
    Write-Err "Echec du telechargement : $_"
    Write-Err "Verifiez la connexion internet et l URL GitHub."
    Add-Content $LOG_FILE "=== ECHEC ==="
    exit 1
}

# --- Etape 3 : Installation --------------------------------------------------
Write-Step 'Installation de GLPI Agent...'
Write-Host "  [i]   Serveur : $GLPI_SERVER" -ForegroundColor DarkCyan
Write-Host "  [i]   Mode    : Windows Service (EXECMODE=1)" -ForegroundColor DarkCyan
Write-Host "  [i]   Modules : Inventaire uniquement (ADDLOCAL=Inventory)" -ForegroundColor DarkCyan

$msiArgs = "/i `"$MSI_TEMP`" /quiet /norestart SERVER=`"$GLPI_SERVER`" EXECMODE=1 ADDLOCAL=Inventory"

try {
    $proc = Start-Process 'msiexec.exe' -ArgumentList $msiArgs -Wait -PassThru
    if ($proc.ExitCode -eq 0) {
        Write-OK 'Installation terminee avec succes.'
    } else {
        Write-Err "msiexec a retourne le code : $($proc.ExitCode)"
        Add-Content $LOG_FILE "=== ECHEC ==="
        exit 1
    }
} catch {
    Write-Err "Erreur lors de l installation : $_"
    Add-Content $LOG_FILE "=== ECHEC ==="
    exit 1
}

# --- Etape 4 : Verification service ------------------------------------------
Write-Step 'Verification du service GLPI Agent...'
Start-Sleep -Seconds 3

$svc = Get-Service -Name 'GLPI-Agent' -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -eq 'Running') {
    Write-OK "Service 'GLPI-Agent' : En cours d execution."
} elseif ($svc) {
    Write-Warn "Service trouve mais etat : $($svc.Status.ToString()). Tentative de demarrage..."
    try {
        Start-Service 'GLPI-Agent'
        Start-Sleep -Seconds 2
        Write-OK 'Service demarre.'
    } catch {
        Write-Err "Impossible de demarrer le service : $_"
    }
} else {
    Write-Warn "Service 'GLPI-Agent' introuvable. Verifiez dans services.msc."
}

# --- Etape 5 : Verification interface locale ---------------------------------
Write-Step "Verification de l interface locale ($GLPI_LOCAL)..."
Start-Sleep -Seconds 2
try {
    $r = Invoke-WebRequest -Uri $GLPI_LOCAL -UseBasicParsing -TimeoutSec 10
    if ($r.StatusCode -eq 200) {
        Write-OK "Interface locale accessible : $GLPI_LOCAL"
    }
} catch {
    Write-Warn "Interface locale non accessible pour l instant (le service demarre)."
}

# --- Etape 6 : Nettoyage MSI temp -------------------------------------------
Write-Step 'Nettoyage du fichier temporaire...'
try {
    Remove-Item $MSI_TEMP -Force
    Write-OK 'Fichier temporaire supprime.'
} catch {
    Write-Warn "Impossible de supprimer le fichier temporaire : $MSI_TEMP"
}

# --- Etape 7 : Verification connectivite serveur GLPI -----------------------
Write-Step "Test de connectivite vers le serveur GLPI (172.20.10.140)..."
$serverOk = $false
if (Test-Connection -ComputerName '172.20.10.140' -Count 2 -Quiet) {
    Write-OK 'Serveur GLPI joignable (ping OK).'
    $serverOk = $true
} else {
    Write-Err 'Serveur GLPI inaccessible. Le poste est peut-etre encore en quarantaine.'
    Add-Content $LOG_FILE "[$(Get-Date -f 'HH:mm:ss')] ERR:  Serveur GLPI inaccessible"
}

# --- Etape 8 : Verification URL inventaire -----------------------------------
if ($serverOk) {
    Write-Step "Test de l URL d inventaire ($GLPI_SERVER)..."
    try {
        $resp = Invoke-WebRequest -Uri $GLPI_SERVER -UseBasicParsing -TimeoutSec 10
        if ($resp.StatusCode -eq 200) {
            Write-OK "URL inventaire accessible : $GLPI_SERVER"
        } else {
            Write-Warn "URL inventaire repond avec le code : $($resp.StatusCode)"
        }
    } catch {
        Write-Err "URL inventaire inaccessible : $_"
        Write-Warn "Verifiez que l URL contient bien 'front' et non 'font'."
    }
}

# --- Etape 9 : Forcer l inventaire ------------------------------------------
Write-Step "Forçage de l inventaire GLPI..."
Start-Sleep -Seconds 2
$inventoryOk = $false

$bat = 'C:\Program Files\GLPI-Agent\glpi-agent.bat'
if (Test-Path $bat) {
    try {
        $out = & cmd.exe /c "`"$bat`" --force" 2>&1
        $out | ForEach-Object { Add-Content $LOG_FILE "[$(Get-Date -f 'HH:mm:ss')] AGENT: $_" }
        Write-OK 'Inventaire force via glpi-agent.bat.'
        $inventoryOk = $true
    } catch {
        Write-Warn "Erreur glpi-agent.bat : $_"
    }
} else {
    try {
        Invoke-WebRequest -Uri "$GLPI_LOCAL/?action=forceInventory" -UseBasicParsing -TimeoutSec 15 | Out-Null
        Write-OK 'Inventaire force via interface locale.'
        $inventoryOk = $true
    } catch {
        Write-Warn "Impossible de forcer l inventaire automatiquement."
        Write-Warn "Ouvrez $GLPI_LOCAL et cliquez sur 'Force an Inventory'."
    }
}

# --- Etape 10 : Verification remontee dans GLPI ------------------------------
if ($inventoryOk -and $serverOk) {
    Write-Step "Verification de la remontee dans GLPI (attente 30 secondes)..."
    Start-Sleep -Seconds 30
    try {
        $glpiPage = Invoke-WebRequest -Uri "http://172.20.10.140" -UseBasicParsing -TimeoutSec 10
        if ($glpiPage.StatusCode -eq 200) {
            Write-OK "Interface GLPI accessible : http://172.20.10.140"
            Write-Host "  [i]   Verifiez dans GLPI : Parc -> Ordinateurs -> $env:COMPUTERNAME" -ForegroundColor DarkCyan
        }
    } catch {
        Write-Warn "Interface GLPI non accessible depuis ce poste."
    }
}

# --- Verification URL registre -----------------------------------------------
Write-Step 'Verification de l URL dans le registre Windows...'
$regKey = 'HKLM:\SOFTWARE\GLPI-Agent'
if (Test-Path $regKey) {
    $regUrl = (Get-ItemProperty -Path $regKey -ErrorAction SilentlyContinue).server
    if ($regUrl -like '*font/inventory*') {
        Write-Err "URL incorrecte dans le registre : $regUrl"
        Write-Step "Correction automatique de l URL..."
        $fixedUrl = $regUrl -replace 'font/', 'front/'
        Set-ItemProperty -Path $regKey -Name 'server' -Value $fixedUrl
        Write-OK "URL corrigee : $fixedUrl"
        Restart-Service 'GLPI-Agent' -ErrorAction SilentlyContinue
        Write-OK 'Service redémarre avec la bonne URL.'
    } elseif ($regUrl -like '*front/inventory*') {
        Write-OK "URL du registre correcte : $regUrl"
    }
}

# --- Resume ------------------------------------------------------------------
Write-Host ""
Write-Host "  +=====================================================+" -ForegroundColor Green
Write-Host "  |   INSTALLATION TERMINEE                             |" -ForegroundColor Green
Write-Host "  |   Poste  : $($env:COMPUTERNAME.PadRight(41))|" -ForegroundColor Green
Write-Host "  |   Serveur: $('172.20.10.140'.PadRight(41))|" -ForegroundColor Green
Write-Host "  |   Log    : $($LOG_FILE.Substring(0, [Math]::Min($LOG_FILE.Length,41)).PadRight(41))|" -ForegroundColor Green
Write-Host "  +=====================================================+" -ForegroundColor Green
Write-Host ""
if (-not $serverOk) {
    Write-Host "  [!]   ATTENTION : serveur GLPI inaccessible." -ForegroundColor Yellow
    Write-Host "        Verifiez la connexion reseau ou la quarantaine." -ForegroundColor Yellow
    Write-Host ""
}
Write-Host "  Connectez-vous avec le compte AD de l utilisateur puis" -ForegroundColor DarkCyan
Write-Host "  verifiez dans GLPI : Parc -> Ordinateurs -> $env:COMPUTERNAME" -ForegroundColor White
Write-Host ""

Add-Content $LOG_FILE "=== Installation terminee le $(Get-Date) ==="
Add-Content $LOG_FILE ("=" * 60)
