# ============================================================================
# LawnHive Workspace - System Setup Script (Hybrid: Offline + Online)
# ============================================================================
# Called by the installer. Handles:
#   - Finding local image file (offline mode, fast)
#   - Falling back to Docker Hub (online mode)
#   - Docker Desktop install, WSL2, .env, service startup
#
# Client never sees "offline" or "online" - just a branded progress bar.
# ============================================================================

param(
    [Parameter(Mandatory=$true)]
    [string]$ClientId,
    
    [Parameter(Mandatory=$true)]
    [string]$InstallDir,
    
    [Parameter(Mandatory=$false)]
    [string]$SourceDir = "",
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipInternetCheck
)

$ProgressFile = Join-Path $InstallDir "install-progress.txt"

function Set-Progress {
    param([int]$Percent, [string]$Step)
    "$Percent|$Step" | Out-File -FilePath $ProgressFile -Encoding utf8 -Force
}

# HARDCODED DEBUG - writes to temp dir (always writable) AND {app}.
# If NEITHER file exists on client PC, PowerShell script NEVER started.
$DebugFile1 = Join-Path $env:TEMP "lawnhive-debug.txt"
$DebugFile2 = Join-Path $InstallDir "lawnhive-debug.txt"
$DebugMsg = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - install.ps1 STARTED. ClientId=$ClientId InstallDir=$InstallDir SourceDir=$SourceDir PSVersion=$($PSVersionTable.PSVersion) OS=$([Environment]::OSVersion)"
try { $DebugMsg | Out-File -FilePath $DebugFile1 -Encoding utf8 } catch {}
try {
    if (-not (Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }
    $DebugMsg | Out-File -FilePath $DebugFile2 -Encoding utf8
} catch {}

try { $PID | Out-File -FilePath (Join-Path $InstallDir "install.pid") -Encoding ascii -Force } catch {}

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
    if ($SkipInternetCheck) {
        Write-Log "Internet check BYPASSED via -SkipInternetCheck flag"
        return $true
    }
    
    # Check for force-internet override file (created by .iss installer dialog)
    $forceFile = Join-Path $InstallDir "force-internet.txt"
    if (Test-Path $forceFile) {
        Remove-Item $forceFile -Force -ErrorAction SilentlyContinue
        Write-Log "Internet check BYPASSED via force-internet.txt override file"
        return $true
    }

    $urls = @(
        @{ Url = "https://www.google.com";           Timeout = 8;  Name = "Google" },
        @{ Url = "https://www.microsoft.com";        Timeout = 8;  Name = "Microsoft" },
        @{ Url = "https://www.cloudflare.com";       Timeout = 8;  Name = "Cloudflare" },
        @{ Url = "https://registry-1.docker.io/v2/"; Timeout = 10; Name = "Docker Hub" }
    )

    for ($attempt = 1; $attempt -le 2; $attempt++) {
        if ($attempt -eq 2) {
            Write-Log "Internet check: retrying in 5 seconds..."
            Start-Sleep -Seconds 5
        }
        foreach ($endpoint in $urls) {
            try {
                $r = Invoke-WebRequest -Uri $endpoint.Url -UseBasicParsing -TimeoutSec $endpoint.Timeout -Method Head
                Write-Log "Internet check PASSED via $($endpoint.Name) ($($endpoint.Url)) - Status: $($r.StatusCode) (attempt $attempt)"
                return $true
            } catch {
                $errMsg = $_.Exception.Message
                if ($errMsg.Length -gt 120) { $errMsg = $errMsg.Substring(0, 120) + "..." }
                Write-Log "Internet check FAILED attempt $attempt for $($endpoint.Name) ($($endpoint.Url)): $errMsg"
            }
        }
    }

    Write-Log "Internet check: ALL endpoints failed after 2 attempts. No internet connectivity detected."
    return $false
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
# CHECK IF WINDOWS RESTART IS PENDING
# =====================================================================
function Test-PendingReboot {
    $pending = $false
    $reasons = @()
    
    # Check WSL2 pending restart (just enabled features)
    try {
        $wslStatus = wsl --status 2>&1 | Out-String
        if ($wslStatus -match "restart required|pending") {
            $pending = $true
            $reasons += "WSL2 requires restart"
        }
    } catch {}
    
    # Check Windows Update restart pending
    try {
        $key = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"
        if (Test-Path $key) {
            $pending = $true
            $reasons += "Windows Update restart pending"
        }
    } catch {}
    
    # Check pending file rename operations
    try {
        $key = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
        $pendingRenames = Get-ItemProperty -Path $key -Name "PendingFileRenameOperations" -ErrorAction SilentlyContinue
        if ($pendingRenames -and $pendingRenames.PendingFileRenameOperations) {
            $pending = $true
            $reasons += "File rename operations pending"
        }
    } catch {}
    
    # Check pending DCOM restart
    try {
        $key = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
        if (Test-Path $key) {
            $pending = $true
            $reasons += "Windows Update reboot required"
        }
    } catch {}
    
    Write-Log "Pending reboot check: $pending (reasons: $($reasons -join ', '))"
    return @{ Pending = $pending; Reasons = $reasons }
}

# =====================================================================
# CHECK IF VIRTUALIZATION IS ENABLED IN BIOS
# =====================================================================
function Test-Virtualization {
    $result = @{ Enabled = $false; Details = "" }
    
    try {
        $info = systeminfo 2>&1 | Out-String
        if ($info -match "Hyper-V Requirements.*?Yes" -or $info -match "A hypervisor has been detected") {
            $result.Enabled = $true
            $result.Details = "Virtualization is enabled"
            Write-Log "Virtualization: ENABLED (systeminfo)"
            return $result
        }
        # Also check via WMI
        $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cpu -and $cpu.VirtualizationFirmwareEnabled) {
            $result.Enabled = $true
            $result.Details = "Virtualization is enabled (VT-x/AMD-V)"
            Write-Log "Virtualization: ENABLED (WMI)"
            return $result
        }
        
        $result.Details = "Virtualization is NOT enabled in BIOS"
        Write-Log "Virtualization: NOT ENABLED"
    } catch {
        $result.Details = "Could not determine virtualization status"
        Write-Log "Virtualization check failed: $_"
    }
    
    return $result
}

# =====================================================================
# START DOCKER DESKTOP MANUALLY (if not running)
# =====================================================================
function Start-DockerDesktop {
    $dockerPaths = @(
        "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe",
        "$env:LOCALAPPDATA\Docker\app\version\bin\Docker Desktop.exe"
    )
    
    foreach ($path in $dockerPaths) {
        if (Test-Path $path) {
            Write-Log "Starting Docker Desktop from: $path"
            try {
                Start-Process -FilePath $path -WindowStyle Minimized
                Write-Log "Docker Desktop start command sent."
                return $true
            } catch {
                Write-Log "Failed to start Docker Desktop: $_"
            }
        }
    }
    
    Write-Log "Docker Desktop executable not found."
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
    Set-Progress -Percent 35 -Step "Loading workspace components from file..."
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
    Set-Progress -Percent 30 -Step "Downloading workspace components..."
    
    $completedLayers = 0
    $totalLayers = 0
    
    docker pull $ImageName 2>&1 | ForEach-Object {
        Write-Log $_
        if ($_ -match 'Pulling fs layer') { $totalLayers++ }
        if ($_ -match 'Pull complete') {
            $completedLayers++
            if ($totalLayers -gt 0) {
                $pct = 30 + [math]::Floor(($completedLayers / $totalLayers) * 42)
                Set-Progress -Percent $pct -Step "Downloading... ($completedLayers/$totalLayers layers)"
            }
        }
    }
    
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to download workspace components. Please check your internet connection."
    }
    
    Set-Progress -Percent 72 -Step "Download complete"
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
        Set-Progress -Percent 14 -Step "Downloading Docker Desktop..."
        Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing -TimeoutSec 300
    } catch {
        Write-Log "Failed to download Docker Desktop: $_"
        throw "Could not install required system components. Please check your internet connection."
    }
    
    Write-Log "Installing Docker Desktop (this may take 5-10 minutes)..."
    Set-Progress -Percent 18 -Step "Installing Docker Desktop..."
    
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

# =====================================================================
# ADD WINDOWS FIREWALL RULE (port 8000 inbound)
# =====================================================================
function Add-FirewallRule {
    Write-Log "Adding Windows Firewall rule for port 8000..."
    try {
        # Use UAC elevation to ensure admin rights
        $ruleExists = netsh advfirewall firewall show rule name="LawnHive Workspace" dir=in 2>&1 | Select-String "LawnHive Workspace"
        if ($ruleExists) {
            Write-Log "Firewall rule already exists."
            return
        }

        # Create a temp script that adds the rule (elevated)
        $tempScript = Join-Path $env:TEMP "lh_firewall.ps1"
        @"
netsh advfirewall firewall add rule name="LawnHive Workspace" dir=in action=allow protocol=tcp localport=8000 profile=any description="Allows other PCs on the network to access LawnHive Workspace"
"@ | Out-File -FilePath $tempScript -Encoding ascii -Force

        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$tempScript`"" -Verb RunAs -Wait -WindowStyle Hidden 2>&1 | Out-Null
        
        Remove-Item $tempScript -Force -ErrorAction SilentlyContinue
        Write-Log "Firewall rule added (via UAC elevation)."
    } catch {
        Write-Log "Warning: Firewall rule could not be set: $_ (non-critical)"
    }
}

# =====================================================================
# GET LOCAL IP ADDRESS
# =====================================================================
function Get-LocalIPAddress {
    try {
        $adapters = Get-CimInstance Win32_NetworkAdapterConfiguration | Where-Object {
            $_.IPEnabled -eq $true -and $_.IPAddress -ne $null
        }
        foreach ($adapter in $adapters) {
            foreach ($ip in $adapter.IPAddress) {
                if ($ip -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$' -and $ip -notlike '127.*') {
                    return $ip
                }
            }
        }
    } catch {}
    return $null
}

# ============================================================================
# MAIN
# ============================================================================

# CRITICAL: Ensure install directory exists BEFORE any log writes.
# Inno Setup calls this script in PrepareToInstall, which runs BEFORE
# the {app} directory is created. Without this, Write-Log fails and
# the script crashes silently - no log file, no error file.
if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

# First log entry - before anything else. Proves the script started.
"$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) - INSTALLER BOOT: Script execution started" | Out-File -FilePath $LogFile -Append -Encoding utf8

Write-Log "========================================="
Write-Log "LawnHive Workspace Installer v1.0.0"
Write-Log "Started at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Log "PowerShell $($PSVersionTable.PSVersion)"
Write-Log "Client ID: $ClientId"
Write-Log "Install Dir: $InstallDir"
Write-Log "Source Dir: $SourceDir"
Write-Log "Script Path: $($MyInvocation.MyCommand.Path)"
Write-Log "OS: $([Environment]::OSVersion.VersionString)"
Write-Log "SkipInternetCheck: $SkipInternetCheck"
Write-Log "========================================="

try {
    Write-Log "STEP 1: Creating .env file"
    Set-Progress -Percent 5 -Step "Creating configuration..."
    # Clean up any previous error files
    Remove-Item (Join-Path $InstallDir "install-error.txt") -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $InstallDir "install-error-code.txt") -Force -ErrorAction SilentlyContinue
    Set-EnvFile
    Write-Log "STEP 1: Done - .env created"

    Write-Log "STEP 2: Enabling WSL2"
    Set-Progress -Percent 8 -Step "Checking system requirements..."
    Enable-WSL2
    Write-Log "STEP 2: Done - WSL2 checked"

    Write-Log "STEP 3: Checking Docker Desktop"
    Set-Progress -Percent 12 -Step "Checking Docker Desktop..."
    $needsRestart = $false
    if (-not (Test-DockerInstalled)) {
        Write-Log "STEP 3: Docker Desktop NOT found - will install"
        if (-not (Test-Internet)) {
            Write-Log "STEP 3: No internet connection available"
            throw "NO_INTERNET_NO_DOCKER"
        }
        Write-Log "STEP 3: Internet OK - downloading Docker Desktop"
        Set-Progress -Percent 15 -Step "Downloading Docker Desktop..."
        $needsRestart = Install-DockerDesktop
    } else {
        Write-Log "STEP 3: Docker Desktop already installed"
    }

    # Check if a restart is needed (Docker exit 3010 OR WSL2 was just enabled)
    $rebootCheck = Test-PendingReboot
    if ($needsRestart -or $rebootCheck.Pending) {
        $reason = if ($needsRestart) { "Docker Desktop installer requires restart" } else { "System restart pending: $($rebootCheck.Reasons -join ', ')" }
        Write-Log "STEP 3: Restart needed - $reason"
        
        # Save resume state for post-restart
        $regPath = "HKCU:\SOFTWARE\LawnHive Workspace\Installer"
        New-Item -Path $regPath -Force | Out-Null
        Set-ItemProperty -Path $regPath -Name "ResumeInstall" -Value "1"
        Set-ItemProperty -Path $regPath -Name "InstallDir" -Value $InstallDir
        Set-ItemProperty -Path $regPath -Name "ClientId" -Value $ClientId
        Set-ItemProperty -Path $regPath -Name "SourceDir" -Value $SourceDir
        
        # Write resume command to RunOnce (runs after restart)
        $resumeCmd = "`"$($MyInvocation.MyCommand.Path)`" -ClientId `"$ClientId`" -InstallDir `"$InstallDir`" -SourceDir `"$SourceDir`""
        $runOncePath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
        Set-ItemProperty -Path $runOncePath -Name "LawnHiveResume" -Value $resumeCmd
        Write-Log "STEP 3: RunOnce resume entry saved to: $runOncePath"
        
        Set-Progress -Percent 100 -Step "Restart required"
        "3010" | Out-File -FilePath (Join-Path $InstallDir "install-progress-done.txt") -Encoding ascii -Force
        exit 3010
    }
    Write-Log "STEP 3: Done - Docker Desktop ready"

    Write-Log "STEP 4: Waiting for Docker daemon to respond"
    Set-Progress -Percent 25 -Step "Starting Docker services..."
    
    # Phase 1: Wait up to 120 seconds for Docker to respond
    if (Wait-DockerReady -MaxWaitSeconds 120) {
        Write-Log "STEP 4: Docker daemon responded on first wait"
    } else {
        # Phase 2: Try starting Docker Desktop manually
        Write-Log "STEP 4: Docker not responding. Attempting to start Docker Desktop..."
        Set-Progress -Percent 26 -Step "Starting Docker Desktop..."
        Start-DockerDesktop | Out-Null
        Start-Sleep -Seconds 10
        
        # Phase 3: Wait another 120 seconds after manual start
        Write-Log "STEP 4: Waiting after manual Docker Desktop start..."
        if (Wait-DockerReady -MaxWaitSeconds 120) {
            Write-Log "STEP 4: Docker daemon responded after manual start"
        } else {
            # Phase 4: Docker still won't start - check virtualization
            Write-Log "STEP 4: Docker still not responding. Checking virtualization..."
            $virtCheck = Test-Virtualization
            
            if (-not $virtCheck.Enabled) {
                Write-Log "STEP 4: VIRTUALIZATION NOT ENABLED"
                throw "VIRTUALIZATION_DISABLED"
            } else {
                Write-Log "STEP 4: Virtualization is enabled but Docker still not starting"
                throw "Docker did not start properly. Virtualization is enabled but Docker daemon is not responding."
            }
        }
    }
    Write-Log "STEP 4: Done - Docker daemon ready"

    Write-Log "STEP 5: Loading/Pulling image"
    Set-Progress -Percent 28 -Step "Loading workspace components..."
    $localImage = Find-LocalImage
    
    if ($localImage) {
        Write-Log "STEP 5: MODE = Offline (file: $localImage)"
        Load-LocalImage -ImagePath $localImage
    } else {
        Write-Log "STEP 5: MODE = Online (Docker Hub)"
        if (-not (Test-Internet)) {
            Write-Log "STEP 5: No internet for image download"
            throw "NO_IMAGE_NO_INTERNET"
        }
        Pull-OnlineImage
    }
    Write-Log "STEP 5: Done - image ready"

    Write-Log "STEP 6: Starting Docker containers"
    Set-Progress -Percent 75 -Step "Starting workspace containers..."
    Start-Services
    Write-Log "STEP 6: Done - containers started"

    Write-Log "STEP 7: Waiting for web server (max 300s)"
    Set-Progress -Percent 85 -Step "Configuring workspace..."
    Wait-WebReady -MaxWaitSeconds 300
    Write-Log "STEP 7: Done - web server responding"

    Write-Log "STEP 8: Adding firewall rule"
    Set-Progress -Percent 93 -Step "Setting up network access..."
    Add-FirewallRule
    Write-Log "STEP 8: Done"

    Write-Log "STEP 9: Detecting local IP"
    Set-Progress -Percent 97 -Step "Detecting network address..."
    $localIP = Get-LocalIPAddress
    if ($localIP) {
        $ipFile = Join-Path $InstallDir "server-ip.txt"
        [System.IO.File]::WriteAllText($ipFile, $localIP, [System.Text.Encoding]::UTF8)
        Write-Log "STEP 9: Server IP = $localIP"
    } else {
        Write-Log "STEP 9: Could not detect local IP"
    }

    Write-Log "========================================="
    Write-Log "INSTALLATION COMPLETED SUCCESSFULLY"
    Write-Log "========================================="
    Set-Progress -Percent 100 -Step "Installation complete!"
    "0" | Out-File -FilePath (Join-Path $InstallDir "install-progress-done.txt") -Encoding ascii -Force
    exit 0

} catch {
    # -- Error handler - MUST be bulletproof --
    # NOTE: No try-catch here - it confuses the PowerShell parser.
    # Direct Out-File calls only. Directory is guaranteed to exist from main block.
    
    # Write to log file
    "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) - FATAL ERROR: $($_.Exception.Message)" | Out-File -FilePath $LogFile -Append -Encoding utf8
    "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) - Exception type: $($_.Exception.GetType().FullName)" | Out-File -FilePath $LogFile -Append -Encoding utf8
    if ($_.ScriptStackTrace) {
        "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) - Stack: $($_.ScriptStackTrace)" | Out-File -FilePath $LogFile -Append -Encoding utf8
    }
    
    $errMsg = $_.Exception.Message
    $userMsg = ""
    
    if ($errMsg -eq "NO_INTERNET_NO_DOCKER") {
        $userMsg = "Docker is not installed and no internet connection was found.`r`n`r`n" +
            "Please connect to the internet and try again.`r`n" +
            "Docker Desktop needs to be downloaded during installation."
    } elseif ($errMsg -eq "NO_IMAGE_NO_INTERNET") {
        $userMsg = "No offline image file found and no internet connection.`r`n`r`n" +
            "Please connect to the internet, or place lawnhive-image.tar`r`n" +
            "in the same folder as the installer."
    } elseif ($errMsg -eq "VIRTUALIZATION_DISABLED") {
        $userMsg = "Docker requires virtualization to be enabled in your computer's BIOS settings.`r`n`r`n" +
            "What to do:`r`n" +
            "1. Restart your computer`r`n" +
            "2. Press F2 or F12 or DEL when it starts (to open BIOS settings)`r`n" +
            "   (Different brands: Dell=F2, HP=F10, Lenovo=F2, Acer=F2, Asus=DEL/F2)`r`n" +
            "3. Find 'Virtualization Technology' or 'VT-x' or 'SVM Mode'`r`n" +
            "4. Set it to 'Enabled'`r`n" +
            "5. Save and exit BIOS`r`n" +
            "6. Run the installer again"
    } elseif ($errMsg -match "Docker did not start") {
        $userMsg = "Docker Desktop is installed but the service is not responding.`r`n`r`n" +
            "This can happen if the computer needs a restart.`r`n`r`n" +
            "What to do:`r`n" +
            "1. Restart your computer`r`n" +
            "2. If Docker Desktop opens automatically, wait 30 seconds`r`n" +
            "3. Run this installer again`r`n`r`n" +
            "If it still fails after restart, contact support."
    } elseif ($errMsg -match "Failed to start workspace") {
        $userMsg = "Docker containers failed to start.`r`n`r`n" +
            "This can happen if another program is using port 8000,`r`n" +
            "or if Docker needs more time to initialize.`r`n" +
            "Please restart your computer and try again."
    } elseif ($errMsg -match "Could not install required system components") {
        $userMsg = "Could not download Docker Desktop.`r`n`r`n" +
            "Please check your internet connection and try again.`r`n" +
            "If you have antivirus software, it may be blocking the download."
    } elseif ($errMsg -match "Failed to download") {
        $userMsg = "Could not download required files.`r`n`r`n" +
            "Please check your internet connection.`r`n" +
            "If you use a proxy or firewall, it may be blocking Docker Hub."
    } elseif ($errMsg -match "timed out|timeout|Timeout") {
        $userMsg = "The operation took too long and timed out.`r`n`r`n" +
            "This can happen with slow internet or if Docker Hub is busy.`r`n" +
            "Please try again in a few minutes."
    } else {
        $shortErr = $errMsg
        if ($shortErr.Length -gt 200) { $shortErr = $shortErr.Substring(0, 200) + "..." }
        $userMsg = "An unexpected error occurred:`r`n`r`n" +
            "$shortErr`r`n`r`n" +
            "Please check install.log for details:`r`n" +
            "$LogFile"
    }
    
    # Write error file for Inno Setup to read
    if (-not (Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }
    $errorFile = Join-Path $InstallDir "install-error.txt"
    [System.IO.File]::WriteAllText($errorFile, $userMsg, [System.Text.Encoding]::UTF8)
    
    $codeFile = Join-Path $InstallDir "install-error-code.txt"
    $errorCode = "UNKNOWN"
    if ($errMsg -eq "NO_INTERNET_NO_DOCKER") { $errorCode = "NO_INTERNET_NO_DOCKER" }
    elseif ($errMsg -eq "NO_IMAGE_NO_INTERNET") { $errorCode = "NO_IMAGE_NO_INTERNET" }
    elseif ($errMsg -eq "VIRTUALIZATION_DISABLED") { $errorCode = "VIRTUALIZATION_DISABLED" }
    elseif ($errMsg -match "Docker did not start") { $errorCode = "DOCKER_START_FAILED" }
    elseif ($errMsg -match "Failed to start workspace") { $errorCode = "CONTAINER_START_FAILED" }
    elseif ($errMsg -match "Could not install required system components") { $errorCode = "DOCKER_DOWNLOAD_FAILED" }
    elseif ($errMsg -match "Failed to download") { $errorCode = "DOWNLOAD_FAILED" }
    elseif ($errMsg -match "timed out|timeout|Timeout") { $errorCode = "TIMEOUT" }
    [System.IO.File]::WriteAllText($codeFile, $errorCode, [System.Text.Encoding]::UTF8)
    
    Set-Progress -Percent 0 -Step "Installation failed"
    "1" | Out-File -FilePath (Join-Path $InstallDir "install-progress-done.txt") -Encoding ascii -Force
    exit 1
}
