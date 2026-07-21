# ============================================================================
# LawnHive Workspace - System Setup Script (Hybrid: Offline + Online)
# ============================================================================
# Called by the installer. Handles:
#   - Finding local image file (offline mode, fast)
#   - Falling back to Docker Hub (online mode)
#   - Docker Desktop install, WSL2, .env, service startup
#
# Client never sees "offline" or "online" — just a branded progress bar.
# ============================================================================

param(
    [Parameter(Mandatory=$true)]
    [string]$ClientId,
    
    [Parameter(Mandatory=$true)]
    [string]$InstallDir,
    
    [Parameter(Mandatory=$false)]
    [string]$SourceDir = ""
)

$ErrorActionPreference = "Stop"
$LogFile = Join-Path $InstallDir "install.log"
$ImageName = "faisalabdullahabir/workspace:latest"

function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts - $Message" | Out-File -FilePath $LogFile -Append -Encoding utf8
}

function Generate-Password {
    param([int]$Length = 24)
    $chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'.ToCharArray()
    $pass = -join ((1..$Length) | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
    return $pass
}

function Test-Internet {
    try {
        $r = Invoke-WebRequest -Uri "https://registry-1.docker.io/v2/" -UseBasicParsing -TimeoutSec 10
        return $true
    } catch {
        return $false
    }
}

function Test-DockerInstalled {
    $paths = @(
        "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe",
        "$env:LOCALAPPDATA\Docker\app\version\bin\Docker Desktop.exe"
    )
    foreach ($p in $paths) {
        if (Test-Path $p) { return $true }
    }
    return $false
}

function Wait-DockerReady {
    param([int]$MaxWaitSeconds = 180)
    $elapsed = 0
    while ($elapsed -lt $MaxWaitSeconds) {
        try {
            docker info 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) { return $true }
        } catch {}
        Start-Sleep -Seconds 5
        $elapsed += 5
    }
    return $false
}

# =====================================================================
# FIND LOCAL IMAGE FILE (offline mode)
# =====================================================================
# Searches these locations for lawnHive-image.tar:
#   1. Installer's own folder (same dir as LawnHiveWorkspaceSetup.exe)
#   2. lawnhive-image/ subfolder next to installer
#   3. InstallDir itself
# =====================================================================
function Find-LocalImage {
    $searchPaths = @()
    
    # SourceDir = where the installer .exe lives (on pendrive)
    if ($SourceDir -and $SourceDir -ne "") {
        $searchPaths += Join-Path $SourceDir "lawnhive-image.tar"
        $searchPaths += Join-Path $SourceDir "lawnhive-image\lawnhive-image.tar"
    }
    
    # Same directory as install.ps1
    $scriptDir = Split-Path -Parent $MyInvocation.ScriptName
    if ($scriptDir) {
        $searchPaths += Join-Path $scriptDir "lawnhive-image.tar"
        $searchPaths += Join-Path (Split-Path -Parent $scriptDir) "lawnhive-image.tar"
        $searchPaths += Join-Path (Split-Path -Parent $scriptDir) "lawnhive-image\lawnhive-image.tar"
    }
    
    # Install directory
    $searchPaths += Join-Path $InstallDir "lawnhive-image.tar"
    
    # Pendrive root (common drive letters)
    foreach ($letter in @('D','E','F','G','H')) {
        $searchPaths += "${letter}:\lawnhive-image.tar"
        $searchPaths += "${letter}:\LawnHive Installer\lawnhive-image.tar"
        $searchPaths += "${letter}:\lawnhive-image\lawnhive-image.tar"
    }
    
    foreach ($p in $searchPaths) {
        if ($p -and (Test-Path $p)) {
            $sizeGB = [math]::Round((Get-Item $p).Length / 1GB, 2)
            Write-Log "Found local image: $p ($sizeGB GB)"
            return $p
        }
    }
    
    Write-Log "No local image file found."
    return $null
}

# =====================================================================
# LOAD IMAGE FROM LOCAL FILE
# =====================================================================
function Load-LocalImage {
    param([string]$ImagePath)
    
    Write-Log "Loading image from local file: $ImagePath"
    docker load -i $ImagePath 2>&1 | ForEach-Object { Write-Log $_ }
    
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to load image from local file. The file may be corrupted."
    }
    
    Write-Log "Image loaded successfully from local file."
}

# =====================================================================
# PULL IMAGE FROM DOCKER HUB (online fallback)
# =====================================================================
function Pull-OnlineImage {
    Write-Log "Pulling image from Docker Hub (this may take 10-20 minutes)..."
    docker pull $ImageName 2>&1 | ForEach-Object { Write-Log $_ }
    
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to download workspace components. Please check your internet connection."
    }
    
    Write-Log "Image pulled successfully from Docker Hub."
}

# =====================================================================
# CREATE .ENV FILE
# =====================================================================
function Set-EnvFile {
    $envPath = Join-Path $InstallDir ".env"
    $dbPass = Generate-Password -Length 24
    $redisPass = Generate-Password -Length 24
    
    $content = @"
CLIENT_ID=$ClientId
DB_ROOT_PASSWORD=$dbPass
DB_PASSWORD=$dbPass
REDIS_PASSWORD=$redisPass
ADMIN_PASSWORD=admin
FRAPPE_PORT=8000
"@
    [System.IO.File]::WriteAllText($envPath, $content, [System.Text.Encoding]::UTF8)
    Write-Log "Created .env file with Client ID: $ClientId"
}

# =====================================================================
# INSTALL DOCKER DESKTOP (silent)
# =====================================================================
function Install-DockerDesktop {
    Write-Log "Docker Desktop not found. Starting installation..."
    
    $installerUrl = "https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe"
    $installerPath = Join-Path $env:TEMP "DockerDesktopInstaller.exe"
    
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing -TimeoutSec 300
    } catch {
        Write-Log "Failed to download Docker Desktop: $_"
        throw "Could not install required system components. Please check your internet connection."
    }
    
    Write-Log "Installing Docker Desktop (this may take 5-10 minutes)..."
    
    $process = Start-Process -FilePath $installerPath -ArgumentList "install","--quiet","--accept-license","--backend=wsl-2" -Wait -PassThru -NoNewWindow
    Write-Log "Docker Desktop installer exit code: $($process.ExitCode)"
    
    Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
    
    if ($process.ExitCode -ne 0 -and $process.ExitCode -ne 3010) {
        throw "System component installation failed."
    }
    
    if ($process.ExitCode -eq 3010) {
        Write-Log "Docker Desktop installed. System restart is required."
        return $true
    }
    
    return $false
}

# =====================================================================
# ENABLE WSL2
# =====================================================================
function Enable-WSL2 {
    Write-Log "Checking WSL2 status..."
    try {
        $null = wsl --status 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "WSL2 is already enabled."
            return
        }
    } catch {}
    
    Write-Log "Enabling WSL2 features..."
    try {
        dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart 2>&1 | Out-Null
        dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart 2>&1 | Out-Null
        Write-Log "WSL2 features enabled."
    } catch {
        Write-Log "Warning: Could not enable WSL2: $_"
    }
}

# =====================================================================
# START SERVICES (docker compose up)
# =====================================================================
function Start-Services {
    Push-Location $InstallDir
    
    Write-Log "Starting services..."
    docker compose up -d 2>&1 | ForEach-Object { Write-Log $_ }
    
    if ($LASTEXITCODE -ne 0) {
        Pop-Location
        throw "Failed to start workspace services."
    }
    
    Pop-Location
    Write-Log "Services started successfully."
}

# =====================================================================
# WAIT FOR WEB SERVER
# =====================================================================
function Wait-WebReady {
    param([int]$MaxWaitSeconds = 300)
    $elapsed = 0
    while ($elapsed -lt $MaxWaitSeconds) {
        try {
            $r = Invoke-WebRequest -Uri "http://localhost:8000" -UseBasicParsing -TimeoutSec 5
            if ($r.StatusCode -eq 200) {
                Write-Log "Web server ready after $elapsed seconds."
                return $true
            }
        } catch {}
        Start-Sleep -Seconds 5
        $elapsed += 5
    }
    Write-Log "Warning: Web server did not respond within ${MaxWaitSeconds}s."
    return $false
}

# ============================================================================
# MAIN
# ============================================================================
Write-Log "========================================="
Write-Log "LawnHive Workspace Installer - Starting"
Write-Log "Client ID: $ClientId"
Write-Log "Install Dir: $InstallDir"
Write-Log "========================================="

try {
    if (-not (Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }

    # ── Step 1: Create .env ─────────────────────────────────────────
    Set-EnvFile

    # ── Step 2: Enable WSL2 ─────────────────────────────────────────
    Enable-WSL2

    # ── Step 3: Install Docker Desktop if needed ────────────────────
    $needsRestart = $false
    if (-not (Test-DockerInstalled)) {
        # Docker Desktop install needs internet
        if (-not (Test-Internet)) {
            throw "NO_INTERNET_NO_DOCKER"
        }
        $needsRestart = Install-DockerDesktop
    } else {
        Write-Log "Docker Desktop is already installed."
    }

    if ($needsRestart) {
        Write-Log "Restart needed. Scheduling resume..."
        $regPath = "HKCU:\SOFTWARE\LawnHive Workspace\Installer"
        New-Item -Path $regPath -Force | Out-Null
        Set-ItemProperty -Path $regPath -Name "ResumeInstall" -Value "1"
        Set-ItemProperty -Path $regPath -Name "InstallDir" -Value $InstallDir
        Set-ItemProperty -Path $regPath -Name "ClientId" -Value $ClientId
        
        $runOncePath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
        Set-ItemProperty -Path $runOncePath -Name "LawnHiveResume" -Value "`"$($MyInvocation.MyCommand.Path)`" -ClientId `"$ClientId`" -InstallDir `"$InstallDir`" -SourceDir `"$SourceDir`""
        
        Write-Log "Scheduled resume after restart."
        exit 3010
    }

    # ── Step 4: Wait for Docker to be ready ─────────────────────────
    Write-Log "Waiting for Docker to be ready..."
    if (-not (Wait-DockerReady -MaxWaitSeconds 180)) {
        throw "Docker did not start properly. Please restart your computer and try again."
    }
    Write-Log "Docker is ready."

    # ── Step 5: Load/Pull the image ─────────────────────────────────
    # HYBRID LOGIC: Try local file first, fall back to Docker Hub
    $localImage = Find-LocalImage
    
    if ($localImage) {
        # OFFLINE MODE — fast, no internet needed
        Write-Log "MODE: Offline (using local file)"
        Load-LocalImage -ImagePath $localImage
    } else {
        # ONLINE MODE — download from Docker Hub
        Write-Log "MODE: Online (downloading from Docker Hub)"
        
        if (-not (Test-Internet)) {
            throw "NO_IMAGE_NO_INTERNET"
        }
        
        Pull-OnlineImage
    }

    # ── Step 6: Start services ──────────────────────────────────────
    Start-Services

    # ── Step 7: Wait for web server ─────────────────────────────────
    Wait-WebReady -MaxWaitSeconds 300

    Write-Log "========================================="
    Write-Log "Installation completed successfully!"
    Write-Log "========================================="
    exit 0

} catch {
    Write-Log "ERROR: $_"
    
    $errMsg = $_.Exception.Message
    if ($errMsg -eq "NO_INTERNET_NO_DOCKER") {
        Write-Log "Error: No internet and Docker not installed."
    } elseif ($errMsg -eq "NO_IMAGE_NO_INTERNET") {
        Write-Log "Error: No local image file found and no internet connection."
    }
    
    exit 1
}
