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

function Find-DockerDesktopPath {
    # Try all known methods to find Docker Desktop.exe
    $candidates = @(
        "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe",
        "$env:LOCALAPPDATA\Docker\app\version\bin\Docker Desktop.exe",
        "C:\Program Files\Docker\Docker\Docker Desktop.exe",
        "D:\Program Files\Docker\Docker\Docker Desktop.exe"
    )

    # Method 1: Registry (most reliable for non-standard installs)
    try {
        $regKeys = @(
            "HKLM:\SOFTWARE\Docker Inc.\Docker Desktop",
            "HKLM:\SOFTWARE\WOW6432Node\Docker Inc.\Docker Desktop",
            "HKCU:\SOFTWARE\Docker Inc.\Docker Desktop"
        )
        foreach ($rk in $regKeys) {
            try {
                $installPath = Get-ItemProperty -Path $rk -Name "InstallPath" -ErrorAction SilentlyContinue
                if ($installPath -and $installPath.InstallPath) {
                    $exePath = Join-Path $installPath.InstallPath "Docker Desktop.exe"
                    if (Test-Path $exePath) {
                        Write-Log "Docker Desktop found via registry ($rk): $exePath"
                        return $exePath
                    }
                }
                $exePath2 = Get-ItemProperty -Path $rk -Name "ExecutablePath" -ErrorAction SilentlyContinue
                if ($exePath2 -and $exePath2.ExecutablePath -and (Test-Path $exePath2.ExecutablePath)) {
                    Write-Log "Docker Desktop found via registry ExecutablePath ($rk): $($exePath2.ExecutablePath)"
                    return $exePath2.ExecutablePath
                }
            } catch {}
        }
    } catch {}

    # Method 2: Known paths
    foreach ($p in $candidates) {
        if (Test-Path $p) {
            Write-Log "Docker Desktop found at known path: $p"
            return $p
        }
    }

    # Method 3: where.exe (searches PATH)
    try {
        $w = where.exe "Docker Desktop.exe" 2>&1 | Out-String
        $first = ($w -split "`n" | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1).Trim()
        if ($first -and (Test-Path $first)) {
            Write-Log "Docker Desktop found via where.exe: $first"
            return $first
        }
    } catch {}

    # Method 4: Get-Command (PowerShell PATH search)
    try {
        $cmd = Get-Command "Docker Desktop.exe" -ErrorAction SilentlyContinue
        if ($cmd -and $cmd.Source -and (Test-Path $cmd.Source)) {
            Write-Log "Docker Desktop found via Get-Command: $($cmd.Source)"
            return $cmd.Source
        }
    } catch {}

    Write-Log "Docker Desktop.exe NOT FOUND by any method"
    return $null
}

function Test-DockerInstalled {
    Write-Log "Test-DockerInstalled: Starting Docker detection..."
    # Check 1: Known paths
    Write-Log "Test-DockerInstalled: Check 1 - Known file paths..."
    $paths = @(
        "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe",
        "$env:LOCALAPPDATA\Docker\app\version\bin\Docker Desktop.exe"
    )
    foreach ($p in $paths) {
        if (Test-Path $p) {
            Write-Log "Test-DockerInstalled: FOUND at known path: $p"
            return $true
        }
    }
    Write-Log "Test-DockerInstalled: Check 1 - Not found at known paths"
    
    # Check 2: docker CLI (installed but exe at non-standard location)
    Write-Log "Test-DockerInstalled: Check 2 - Docker CLI..."
    try {
        $ver = docker --version 2>&1 | Out-String
        if ($ver -match "Docker version") {
            Write-Log "Test-DockerInstalled: FOUND via CLI: $($ver.Trim())"
            return $true
        }
    } catch {}
    Write-Log "Test-DockerInstalled: Check 2 - Docker CLI not available"
    
    # Check 3: Registry + where.exe + Get-Command
    Write-Log "Test-DockerInstalled: Check 3 - Registry/PATH detection..."
    $regPath = Find-DockerDesktopPath
    if ($regPath) {
        Write-Log "Test-DockerInstalled: FOUND via Find-DockerDesktopPath: $regPath"
        return $true
    }
    
    Write-Log "Test-DockerInstalled: NOT FOUND by any method"
    return $false
}

function Wait-DockerReady {
    param([int]$MaxWaitSeconds = 180)
    $elapsed = 0
    $prompted = $false

    # Refresh PATH so docker CLI is accessible even after fresh install
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

    while ($elapsed -lt $MaxWaitSeconds) {
        try {
            $ver = docker info 2>&1 | Out-String
            if ($LASTEXITCODE -eq 0) {
                Write-Log "Docker daemon ready after ${elapsed}s"
                return $true
            }
        } catch {}
        
        # After 30 seconds, show visible prompt (only once)
        if ($elapsed -ge 30 -and -not $prompted) {
            $prompted = $true
            Write-Log "Docker daemon not responding after ${elapsed}s - showing manual start prompt"
            Set-Progress -Percent 18 -Step "Docker Desktop needs to be started manually..."
            
            # Show a message box via WPF (non-blocking to installer flow)
            Add-Type -AssemblyName PresentationFramework
            $null = [System.Threading.Thread]::new({
                [System.Windows.MessageBox]::Show(
                    "Docker Desktop needs to be started manually." + [Environment]::NewLine + [Environment]::NewLine +
                    "Please do the following:" + [Environment]::NewLine +
                    "1. Press the Windows key" + [Environment]::NewLine +
                    "2. Type 'Docker Desktop'" + [Environment]::NewLine +
                    "3. Click on Docker Desktop to open it" + [Environment]::NewLine +
                    "4. Wait for the whale icon to appear in the taskbar" + [Environment]::NewLine + [Environment]::NewLine +
                    "The installer will continue automatically once Docker is ready." + [Environment]::NewLine +
                    "This window will close on its own.",
                    "LawnHive Workspace - Action Required",
                    "OK",
                    "Information")
            }).Start()
        }
        
        Start-Sleep -Seconds 5
        $elapsed += 5
        if ($elapsed % 15 -eq 0) {
            Write-Log "Waiting for Docker daemon... (${elapsed}/${MaxWaitSeconds}s)"
        }
    }
    Write-Log "Docker daemon NOT ready after ${MaxWaitSeconds}s timeout"
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
# START DOCKER DAEMON (service first, then GUI app as fallback)
# =====================================================================
function Start-DockerDesktop {
    Write-Log "Start-DockerDesktop: Beginning Docker startup sequence..."

    # === Strategy 1: Start the Windows Service directly (no path needed) ===
    Write-Log "Start-DockerDesktop: Strategy 1 - Checking Windows services..."
    $svcNames = @("com.docker.service", "Docker Desktop Service", "docker")
    $svcFound = $false
    foreach ($svc in $svcNames) {
        try {
            $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
            if ($service) {
                $svcFound = $true
                Write-Log "Start-DockerDesktop: Found service '$svc' (Status: $($service.Status))"
                if ($service.Status -ne "Running") {
                    Write-Log "Start-DockerDesktop: Starting service '$svc'..."
                    Start-Service -Name $svc -ErrorAction Stop
                    Write-Log "Start-DockerDesktop: Service '$svc' started successfully"
                    return $true
                } else {
                    Write-Log "Start-DockerDesktop: Service '$svc' already running"
                    return $true
                }
            }
        } catch {
            Write-Log "Start-DockerDesktop: Service '$svc' error: $($_.Exception.Message)"
        }
    }
    if (-not $svcFound) {
        Write-Log "Start-DockerDesktop: Strategy 1 FAILED - No Docker services registered (tried: $($svcNames -join ', '))"
    }

    # === Strategy 2: Find Docker Desktop.exe via robust detection and launch GUI ===
    Write-Log "Start-DockerDesktop: Strategy 2 - Searching for Docker Desktop.exe..."
    $exePath = Find-DockerDesktopPath
    if ($exePath) {
        Write-Log "Start-DockerDesktop: Found exe at: $exePath"
        try {
            Start-Process -FilePath $exePath -WindowStyle Minimized
            Write-Log "Start-DockerDesktop: GUI launch command sent successfully"
            return $true
        } catch {
            Write-Log "Start-DockerDesktop: Strategy 2 FAILED - GUI launch error: $($_.Exception.Message)"
        }
    } else {
        Write-Log "Start-DockerDesktop: Strategy 2 FAILED - Docker Desktop.exe not found by any detection method"
    }

    # === Strategy 3: Start-Process "Docker Desktop" (relies on Windows PATH/app registration) ===
    Write-Log "Start-DockerDesktop: Strategy 3 - Trying app registration launch..."
    try {
        Start-Process -FilePath "Docker Desktop" -WindowStyle Minimized -ErrorAction Stop
        Write-Log "Start-DockerDesktop: Strategy 3 succeeded - launched via app registration"
        return $true
    } catch {
        Write-Log "Start-DockerDesktop: Strategy 3 FAILED - $($_.Exception.Message)"
    }

    Write-Log "Start-DockerDesktop: ALL strategies FAILED"
    return $false
}

# =====================================================================
# TEST DOCKER CLI - Verify docker command is accessible from PowerShell
# Refreshes PATH from registry (for fresh installs), tries full path as fallback
# =====================================================================
function Test-DockerCLI {
    Write-Log "Test-DockerCLI: Checking if docker CLI is callable..."

    # Strategy 1: Refresh PATH from registry (catches fresh Docker installs)
    Write-Log "Test-DockerCLI: Refreshing PATH from registry..."
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = $machinePath + ";" + $userPath

    # Strategy 2: Try 'docker --version' with refreshed PATH
    try {
        $ver = docker --version 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0 -and $ver -match "Docker version") {
            Write-Log "Test-DockerCLI: FOUND via PATH: $($ver.Trim())"
            return "docker"
        }
    } catch {
        Write-Log "Test-DockerCLI: docker --version failed: $($_.Exception.Message)"
    }

    # Strategy 3: Try full path to docker.exe (PATH-independent fallback)
    $dockerPaths = @(
        "$env:ProgramFiles\Docker\Docker\resources\bin\docker.exe",
        "${env:ProgramFiles(x86)}\Docker\Docker\resources\bin\docker.exe",
        "$env:LOCALAPPDATA\Docker\app\version\resources\bin\docker.exe",
        "C:\Program Files\Docker\Docker\resources\bin\docker.exe"
    )
    foreach ($dp in $dockerPaths) {
        if (Test-Path $dp) {
            try {
                $ver = & $dp --version 2>&1 | Out-String
                if ($LASTEXITCODE -eq 0 -and $ver -match "Docker version") {
                    Write-Log "Test-DockerCLI: FOUND at full path ($dp): $($ver.Trim())"
                    $dockerDir = Split-Path $dp -Parent
                    $env:Path = $dockerDir + ";" + $env:Path
                    Write-Log "Test-DockerCLI: Added $dockerDir to PATH"
                    return "docker"
                }
            } catch {
                Write-Log "Test-DockerCLI: Full path $dp failed: $($_.Exception.Message)"
            }
        }
    }

    Write-Log "Test-DockerCLI: NOT FOUND by any method"
    return $null
}

# =====================================================================
# SAVE RESUME STATE (for post-restart auto-resume)
# =====================================================================
function Save-ResumeState {
    # 1. HKCU registry (resume flag)
    try {
        $regPath = "HKCU:\SOFTWARE\LawnHive Workspace\Installer"
        New-Item -Path $regPath -Force | Out-Null
        Set-ItemProperty -Path $regPath -Name "ResumeInstall" -Value "1"
        Set-ItemProperty -Path $regPath -Name "InstallDir" -Value $InstallDir
        Set-ItemProperty -Path $regPath -Name "ClientId" -Value $ClientId
        Set-ItemProperty -Path $regPath -Name "SourceDir" -Value $SourceDir
        Write-Log "RESUME: HKCU registry state saved"
    } catch {
        Write-Log "RESUME: WARNING - HKCU registry save FAILED: $($_.Exception.Message)"
    }

    $scriptPath = $PSCommandPath
    if (-not $scriptPath) { $scriptPath = Join-Path $InstallDir "install.ps1" }
    Write-Log "RESUME: Script path resolved as: $scriptPath"
    $resumeCmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -ClientId `"$ClientId`" -InstallDir `"$InstallDir`" -SourceDir `"$SourceDir`""

    # 2. HKCU RunOnce (runs after current user logs in)
    try {
        $hkcuRunOnce = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
        New-Item -Path $hkcuRunOnce -Force | Out-Null
        Set-ItemProperty -Path $hkcuRunOnce -Name "LawnHiveResume" -Value $resumeCmd
        Write-Log "RESUME: HKCU RunOnce WRITTEN to: $hkcuRunOnce"
    } catch {
        Write-Log "RESUME: WARNING - HKCU RunOnce FAILED: $($_.Exception.Message)"
    }

    # 3. HKLM RunOnce (backup, may fail silently without admin)
    try {
        $hklmRunOnce = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
        Set-ItemProperty -Path $hklmRunOnce -Name "LawnHiveResume" -Value $resumeCmd -ErrorAction Stop
        Write-Log "RESUME: HKLM RunOnce WRITTEN to: $hklmRunOnce"
    } catch {
        Write-Log "RESUME: WARNING - HKLM RunOnce FAILED: $($_.Exception.Message)"
    }

    # 4. Desktop shortcut (most reliable fallback)
    try {
        $desktopPath = [Environment]::GetFolderPath("Desktop")
        $lnk = Join-Path $desktopPath "Resume LawnHive Installation.lnk"
        $shell = New-Object -ComObject WScript.Shell
        $sc = $shell.CreateShortcut($lnk)
        $sc.TargetPath = "powershell.exe"
        $sc.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -ClientId `"$ClientId`" -InstallDir `"$InstallDir`" -SourceDir `"$SourceDir`""
        $sc.WorkingDirectory = $InstallDir
        $sc.Description = "Resume LawnHive Workspace installation after restart"
        $sc.IconLocation = "$InstallDir\lawnhive.ico,0"
        $sc.Save()
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null
        $verifySc = New-Object -ComObject WScript.Shell
        $verifyTarget = $verifySc.CreateShortcut($lnk)
        if ($verifyTarget.Arguments -match '-File\s+""') {
            Write-Log "RESUME: WARNING - Resume shortcut created with empty script path! Target: $($verifyTarget.Arguments)"
        } else {
            Write-Log "RESUME: Desktop shortcut CREATED: $lnk"
        }
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($verifySc) | Out-Null
    } catch {
        Write-Log "RESUME: WARNING - Desktop shortcut FAILED: $($_.Exception.Message)"
    }

    # 5. Start Menu shortcut
    try {
        $startMenuPath = [Environment]::GetFolderPath("StartMenu")
        $programsPath = Join-Path $startMenuPath "Programs\LawnHive Workspace"
        if (-not (Test-Path $programsPath)) {
            New-Item -ItemType Directory -Path $programsPath -Force | Out-Null
        }
        $lnk2 = Join-Path $programsPath "Resume Installation.lnk"
        $shell2 = New-Object -ComObject WScript.Shell
        $sc2 = $shell2.CreateShortcut($lnk2)
        $sc2.TargetPath = "powershell.exe"
        $sc2.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -ClientId `"$ClientId`" -InstallDir `"$InstallDir`" -SourceDir `"$SourceDir`""
        $sc2.WorkingDirectory = $InstallDir
        $sc2.Description = "Resume LawnHive Workspace installation after restart"
        $sc2.IconLocation = "$InstallDir\lawnhive.ico,0"
        $sc2.Save()
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell2) | Out-Null
        $verifySc2 = New-Object -ComObject WScript.Shell
        $verifyTarget2 = $verifySc2.CreateShortcut($lnk2)
        if ($verifyTarget2.Arguments -match '-File\s+""') {
            Write-Log "RESUME: WARNING - Start Menu resume shortcut created with empty script path! Target: $($verifyTarget2.Arguments)"
        } else {
            Write-Log "RESUME: Start Menu shortcut CREATED: $lnk2"
        }
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($verifySc2) | Out-Null
    } catch {
        Write-Log "RESUME: WARNING - Start Menu shortcut FAILED: $($_.Exception.Message)"
    }
}

# =====================================================================
# CLEANUP RESUME ARTIFACTS (called on resume or successful completion)
# =====================================================================
function Remove-ResumeArtifacts {
    try { Remove-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" -Name "LawnHiveResume" -ErrorAction SilentlyContinue } catch {}
    try { Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" -Name "LawnHiveResume" -ErrorAction SilentlyContinue } catch {}
    try {
        $lnk = Join-Path ([Environment]::GetFolderPath("Desktop")) "Resume LawnHive Installation.lnk"
        Remove-Item $lnk -Force -ErrorAction SilentlyContinue
    } catch {}
    try {
        $lnk2 = Join-Path ([Environment]::GetFolderPath("StartMenu")) "Programs\LawnHive Workspace\Resume Installation.lnk"
        Remove-Item $lnk2 -Force -ErrorAction SilentlyContinue
    } catch {}
    Write-Log "RESUME: All resume artifacts cleaned up"
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
    # If .env already exists (resume scenario), do NOT overwrite - preserves original passwords
    if (Test-Path $envPath) {
        Write-Log ".env file already exists - keeping existing configuration (resume mode)"
        return
    }
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
    
    Write-Log "Starting services with docker compose up -d..."
    Write-Log "Note: First run may take a few minutes if images need to be pulled."
    
    # Run docker compose up -d and capture all output
    $composeOutput = @()
    docker compose up -d 2>&1 | ForEach-Object {
        $line = $_.ToString()
        $composeOutput += $line
        Write-Log "compose: $line"
    }
    $composeExit = $LASTEXITCODE
    
    Write-Log "docker compose up -d exit code: $composeExit"
    
    # Log container status for debugging
    $containerStatus = docker ps -a --format "table {{.Names}}\t{{.Status}}" 2>&1 | Out-String
    Write-Log "Container status after compose up: $containerStatus"
    
    if ($composeExit -ne 0) {
        # Check if containers are actually running despite exit code
        $runningCount = (docker ps --format "{{.Names}}" 2>&1 | Measure-Object).Count
        Write-Log "Running containers after compose up: $runningCount"
        
        if ($runningCount -ge 2) {
            # At least some containers are running — continue despite exit code
            Write-Log "WARNING: docker compose exited with code $composeExit but $runningCount containers are running. Continuing."
        } else {
            Pop-Location
            throw "Failed to start workspace services. Docker compose exit code: $composeExit`r`n`r`n" +
                "This can happen if:`r`n" +
                "- Required images could not be downloaded`r`n" +
                "- Port 8000 is already in use by another program`r`n" +
                "- Docker needs more time to initialize`r`n`r`n" +
                "Please restart your computer and try again. If the problem persists, check install.log."
        }
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
    $lastContainerLog = 0
    while ($elapsed -lt $MaxWaitSeconds) {
        try {
            $r = Invoke-WebRequest -Uri "http://localhost:8000" -UseBasicParsing -TimeoutSec 5
            if ($r.StatusCode -eq 200 -or $r.StatusCode -eq 302) {
                Write-Log "Web server ready after $elapsed seconds. Status: $($r.StatusCode)"
                return $true
            }
        } catch {}
        
        # Every 60 seconds, log container status for debugging
        if ($elapsed - $lastContainerLog -ge 60) {
            $running = docker ps --format '{{.Names}}' 2>&1 | Out-String
            $runningClean = ($running -split "`n" | Where-Object { $_.Trim() -ne "" }) -join ", "
            Write-Log "Web wait ${elapsed}s: Running containers: $runningClean"
            $lastContainerLog = $elapsed
        }
        
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

    # === Check if this is a RESUME after restart ===
    $isResume = $false
    try {
        $resumeState = Get-ItemProperty -Path "HKCU:\SOFTWARE\LawnHive Workspace\Installer" -Name "ResumeInstall" -ErrorAction SilentlyContinue
        if ($resumeState -and $resumeState.ResumeInstall -eq "1") {
            $isResume = $true
            Write-Log "RESUME MODE DETECTED - skipping completed steps"
            Set-ItemProperty -Path "HKCU:\SOFTWARE\LawnHive Workspace\Installer" -Name "ResumeInstall" -Value "0"
            Remove-ResumeArtifacts
        }
    } catch {}

    # =====================================================================
    # STEP 3: DOCKER DESKTOP - Smart detect, install if needed, start daemon
    # =====================================================================
    Write-Log "STEP 3: Smart Docker Desktop detection"
    Set-Progress -Percent 12 -Step "Checking Docker Desktop..."
    $needsRestart = $false

    if (Test-DockerInstalled) {
        # Docker Desktop is already installed - just make sure daemon is running
        Write-Log "STEP 3: Docker Desktop is installed" + $(if ($isResume) { " (RESUME)" } else { "" })

        if (Wait-DockerReady -MaxWaitSeconds 10) {
            Write-Log "STEP 3: Docker daemon already running"
        } else {
            Write-Log "STEP 3: Docker daemon not responding - attempting to start Docker Desktop..."
            Set-Progress -Percent 18 -Step "Starting Docker Desktop..."
            $startResult = Start-DockerDesktop
            Write-Log "STEP 3: Start-DockerDesktop returned: $startResult"
            
            if (-not $startResult) {
                Write-Log "STEP 3: Start-DockerDesktop FAILED - all start methods exhausted"
                Write-Log "STEP 3: Showing visible error to user"
                throw "Docker was found on your computer but could not be started automatically." + [Environment]::NewLine + [Environment]::NewLine +
                    "Please start Docker Desktop manually:" + [Environment]::NewLine +
                    "1. Press the Windows key" + [Environment]::NewLine +
                    "2. Type 'Docker Desktop'" + [Environment]::NewLine +
                    "3. Click on Docker Desktop to open it" + [Environment]::NewLine +
                    "4. Wait for the whale icon in the taskbar (1-2 minutes)" + [Environment]::NewLine +
                    "5. Then run this installer again"
            }
            
            Start-Sleep -Seconds 10

            if (Wait-DockerReady -MaxWaitSeconds 180) {
                Write-Log "STEP 3: Docker daemon started successfully"
            } else {
                Write-Log "STEP 3: Docker daemon still not responding after 3 minutes"
                $virtCheck = Test-Virtualization
                if (-not $virtCheck.Enabled) {
                    throw "VIRTUALIZATION_DISABLED"
                }
                throw "Docker did not start properly. Virtualization is enabled but Docker daemon is not responding." + [Environment]::NewLine + [Environment]::NewLine +
                    "Please try:" + [Environment]::NewLine +
                    "1. Restart your computer" + [Environment]::NewLine +
                    "2. Wait 2 minutes after login" + [Environment]::NewLine +
                    "3. Run this installer again" + [Environment]::NewLine + [Environment]::NewLine +
                    "If this keeps happening, open Docker Desktop manually first, then run the installer."
            }
        }
    } else {
        # Docker Desktop NOT installed - need to download and install
        Write-Log "STEP 3: Docker Desktop NOT found - will install"
        if (-not (Test-Internet)) {
            throw "NO_INTERNET_NO_DOCKER"
        }
        Write-Log "STEP 3: Internet OK - downloading Docker Desktop"
        Set-Progress -Percent 15 -Step "Downloading Docker Desktop..."
        $needsRestart = Install-DockerDesktop

        # Fresh install without restart: refresh PATH + verify docker CLI is callable
        if (-not $needsRestart) {
            Write-Log "STEP 3: Docker Desktop installed (exit 0). Verifying Docker CLI..."
            $dockerCLI = $null
            for ($i = 0; $i -lt 6; $i++) {
                $dockerCLI = Test-DockerCLI
                if ($dockerCLI) { break }
                Write-Log "STEP 3: Docker CLI not available (attempt $($i+1)/6). Waiting 10s..."
                Start-Sleep -Seconds 10
            }
            if (-not $dockerCLI) {
                throw "Docker was installed but the docker command could not be found in this PowerShell session." + [Environment]::NewLine + [Environment]::NewLine +
                    "This usually means the computer needs a restart to complete the Docker setup." + [Environment]::NewLine + [Environment]::NewLine +
                    "Please restart your computer and run the installer again."
            }
            Write-Log "STEP 3: Docker CLI verified: $dockerCLI"
        }
    }

    # Check if a restart is needed (Docker exit 3010 OR WSL2 pending)
    $rebootCheck = Test-PendingReboot
    if ($needsRestart -or $rebootCheck.Pending) {
        $reason = if ($needsRestart) { "Docker Desktop installer requires restart" } else { "System restart pending: $($rebootCheck.Reasons -join ', ')" }
        Write-Log "STEP 3: Restart needed - $reason"
        Save-ResumeState
        Set-Progress -Percent 100 -Step "Restart required"
        "3010" | Out-File -FilePath (Join-Path $InstallDir "install-progress-done.txt") -Encoding ascii -Force
        Write-Log "STEP 3: Exit code 3010 written. Ready for restart."
        exit 3010
    }
    Write-Log "STEP 3: Done - Docker Desktop ready and daemon running"

    # ── Pre-STEP 4 safety: refresh PATH for all remaining docker commands ──
    Write-Log "STEP 3→4: Refreshing PATH to ensure Docker CLI is available..."
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    if (-not (Test-DockerCLI)) {
        throw "Docker command not available after PATH refresh. A system restart may be required." + [Environment]::NewLine + [Environment]::NewLine +
            "Please restart your computer and run the installer again."
    }
    Write-Log "STEP 3→4: Docker CLI confirmed accessible."

    Write-Log "STEP 4: Loading/Pulling image"
    Set-Progress -Percent 28 -Step "Loading workspace components..."
    $localImage = Find-LocalImage
    
    if ($localImage) {
        Write-Log "STEP 4: MODE = Offline (file: $localImage)"
        Load-LocalImage -ImagePath $localImage
    } else {
        Write-Log "STEP 4: MODE = Online (Docker Hub)"
        if (-not (Test-Internet)) {
            Write-Log "STEP 4: No internet for image download"
            throw "NO_IMAGE_NO_INTERNET"
        }
        Pull-OnlineImage
    }
    Write-Log "STEP 4: Done - workspace image ready"

    Write-Log "STEP 4b: Pre-pulling dependency images (mariadb, redis)..."
    Set-Progress -Percent 72 -Step "Preparing database and cache components..."
    $depImages = @(
        @{ Image = "mariadb:10.6";            Name = "Database" },
        @{ Image = "redis:6.2-alpine";         Name = "Cache" }
    )
    foreach ($dep in $depImages) {
        Write-Log "STEP 4b: Pulling $($dep.Image)..."
        $pullOutput = ""
        $pullExit = 0
        try {
            docker pull $dep.Image 2>&1 | ForEach-Object {
                $line = $_.ToString()
                Write-Log "  $($dep.Name): $line"
                if ($line -match "Pull complete" -or $line -match "Download complete" -or $line -match "Already exists") {
                    Set-Progress -Percent 73 -Step "$($dep.Name) component ready..."
                }
            }
            $pullExit = $LASTEXITCODE
        } catch {
            Write-Log "STEP 4b: Exception pulling $($dep.Image): $($_.Exception.Message)"
            $pullExit = 1
        }
        if ($pullExit -ne 0) {
            Write-Log "STEP 4b: WARNING - Failed to pull $($dep.Image) (exit code: $pullExit). Will retry during container start."
        } else {
            Write-Log "STEP 4b: $($dep.Image) ready."
        }
    }
    Write-Log "STEP 4b: Dependency image pre-pull complete."

    Write-Log "STEP 5: Starting Docker containers"
    Set-Progress -Percent 75 -Step "Starting workspace containers..."
    Start-Services
    Write-Log "STEP 5: Done - containers started"

    Write-Log "STEP 6: Waiting for web server (max 300s)"
    Set-Progress -Percent 85 -Step "Configuring workspace..."
    if (-not (Wait-WebReady -MaxWaitSeconds 300)) {
        Write-Log "STEP 6: Web server did NOT respond. Running container diagnostics..."
        
        # Diagnostic 1: Check which containers are running vs exited
        $psOutput = docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>&1 | Out-String
        Write-Log "STEP 6: Container status: $psOutput"
        
        # Diagnostic 2: Check logs of the main erpnext container for errors
        $containers = @("site1-erpnext-python-1", "site1-erpnext-worker-default-1", "site1-erpnext-scheduler-1", "site1-mariadb-1", "site1-redis-1")
        foreach ($c in $containers) {
            $logOutput = docker logs $c --tail 10 2>&1 | Out-String
            if ($logOutput.Trim() -ne "") {
                Write-Log "STEP 6: Logs for ${c}: $logOutput"
            }
        }
        
        # Diagnostic 3: Check if port 8000 is occupied by something else
        $portCheck = netstat -ano 2>&1 | Select-String ":8000" | Out-String
        Write-Log "STEP 6: Port 8000 status: $portCheck"
        
        throw "Web server did not respond after 5 minutes. Containers may have failed to start. Check install.log for details."
    }
    Write-Log "STEP 6: Done - web server responding"

    Write-Log "STEP 7: Adding firewall rule"
    Set-Progress -Percent 93 -Step "Setting up network access..."
    Add-FirewallRule
    Write-Log "STEP 7: Done"

    Write-Log "STEP 8: Detecting local IP"
    Set-Progress -Percent 97 -Step "Detecting network address..."
    $localIP = Get-LocalIPAddress
    if ($localIP) {
        $ipFile = Join-Path $InstallDir "server-ip.txt"
        [System.IO.File]::WriteAllText($ipFile, $localIP, [System.Text.Encoding]::UTF8)
        Write-Log "STEP 8: Server IP = $localIP"
        } else {
            Write-Log "STEP 8: Could not detect local IP"
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
    } elseif ($errMsg -match "Web server did not respond") {
        $userMsg = "The workspace containers started but the web server did not respond.`r`n`r`n" +
            "This usually means a container crashed during startup.`r`n" +
            "Please restart your computer and run the installer again.`r`n`r`n" +
            "If the problem persists, contact support with the install.log file."
    } elseif ($errMsg -match "Docker did not start") {
        $userMsg = "Docker Desktop is installed but the service is not responding.`r`n`r`n" +
            "This can happen if the computer needs a restart.`r`n`r`n" +
            "What to do:`r`n" +
            "1. Restart your computer`r`n" +
            "2. If Docker Desktop opens automatically, wait 30 seconds`r`n" +
            "3. Run this installer again`r`n`r`n" +
            "If it still fails after restart, contact support."
    } elseif ($errMsg -match "could not be started automatically") {
        $userMsg = "Docker was found on your computer but could not be started.`r`n`r`n" +
            "Please start Docker Desktop manually:`r`n" +
            "1. Press the Windows key`r`n" +
            "2. Type 'Docker Desktop'`r`n" +
            "3. Click on Docker Desktop to open it`r`n" +
            "4. Wait for the whale icon in the taskbar (1-2 minutes)`r`n" +
            "5. Then run this installer again."
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
    elseif ($errMsg -match "could not be started automatically") { $errorCode = "DOCKER_START_FAILED" }
    elseif ($errMsg -match "Docker did not start") { $errorCode = "DOCKER_START_FAILED" }
    elseif ($errMsg -match "Web server did not respond") { $errorCode = "WEB_SERVER_FAILED" }
    elseif ($errMsg -match "Failed to start workspace") { $errorCode = "CONTAINER_START_FAILED" }
    elseif ($errMsg -match "Could not install required system components") { $errorCode = "DOCKER_DOWNLOAD_FAILED" }
    elseif ($errMsg -match "Failed to download") { $errorCode = "DOWNLOAD_FAILED" }
    elseif ($errMsg -match "timed out|timeout|Timeout") { $errorCode = "TIMEOUT" }
    [System.IO.File]::WriteAllText($codeFile, $errorCode, [System.Text.Encoding]::UTF8)
    
    Set-Progress -Percent 0 -Step "Installation failed"
    "1" | Out-File -FilePath (Join-Path $InstallDir "install-progress-done.txt") -Encoding ascii -Force
    exit 1
}
