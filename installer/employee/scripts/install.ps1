# ============================================================================
# LawnHive Workspace - Employee PC Setup (Auto-detect + Manual Fallback)
# ============================================================================
# Lightweight: No Docker, no containers.
# Discovers server on network, validates, creates shortcuts.
# ============================================================================

param(
    [Parameter(Mandatory=$true)]
    [string]$InstallDir
)

$ErrorActionPreference = "Stop"
$LogFile = Join-Path $InstallDir "install.log"
$IconPath = Join-Path $InstallDir "lawnhive.ico"

function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts - $Message" | Out-File -FilePath $LogFile -Append -Encoding utf8
}

# =====================================================================
# HEALTH-CHECK: Verify IP serves LawnHive Workspace
# =====================================================================
function Test-ServerHealth {
    param([string]$IP, [int]$Port = 8000)
    try {
        $url = "http://${IP}:${Port}"
        $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 3 -MaximumRedirection 0 -ErrorAction Stop
        return ($resp.StatusCode -eq 200 -or $resp.StatusCode -eq 301 -or $resp.StatusCode -eq 302)
    } catch {
        if ($_.Exception.Response) {
            $code = [int]$_.Exception.Response.StatusCode
            if ($code -ge 200 -and $code -lt 400) { return $true }
        }
    }
    return $false
}

# =====================================================================
# CREATE SHORTCUT (.url format for HTTP URLs)
# =====================================================================
function New-UrlShortcut {
    param(
        [string]$Path,
        [string]$Url,
        [string]$Icon
    )
    $content = "[InternetShortcut]`nURL=$Url"
    if ($Icon -and (Test-Path $Icon)) {
        $content += "`nIconFile=$Icon`nIconIndex=0"
    }
    [System.IO.File]::WriteAllText($Path, $content, [System.Text.Encoding]::ASCII)
    Write-Log "Shortcut created: $Path -> $Url"
}

# =====================================================================
# AUTO-DETECT: Scan local subnet for server (max 10 seconds)
# =====================================================================
function Find-ServerAuto {
    Write-Log "Starting auto-detect scan..."

    # Get local subnet
    $subnet = $null
    try {
        $adapters = Get-CimInstance Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled -eq $true }
        foreach ($a in $adapters) {
            if ($a.IPAddress) {
                foreach ($ip in $a.IPAddress) {
                    if ($ip -match '^(10\.|172\.(1[6-9]|2\d|3[01])\.|192\.168\.)' -and $ip -notlike '127.*') {
                        $parts = $ip.Split('.')
                        $subnet = "$($parts[0]).$($parts[1]).$($parts[2])"
                        Write-Log "Subnet: $subnet"
                        break
                    }
                }
            }
            if ($subnet) { break }
        }
    } catch {
        Write-Log "Subnet detection failed: $_"
    }

    if (-not $subnet) {
        Write-Log "No private IP found."
        return $null
    }

    # Scan with parallel jobs (10s limit)
    Write-Log "Scanning $subnet.1-254..."
    $deadline = [DateTime]::UtcNow.AddSeconds(10)

    for ($i = 1; $i -le 254; $i++) {
        if ([DateTime]::UtcNow -gt $deadline) { break }
        $target = "$subnet.$i"
        Start-Job -ScriptBlock {
            param($ip)
            try {
                $sock = New-Object System.Net.Sockets.TcpClient
                $result = $sock.BeginConnect($ip, 8000, $null, $null)
                $wait = $result.AsyncWaitHandle.WaitOne(800, $false)
                if ($wait -and $sock.Connected) {
                    $sock.EndConnect($result)
                    $sock.Close()
                    return $ip
                }
                $sock.Close()
            } catch {}
            return $null
        } -ArgumentList $target | Out-Null
    }

    # Wait for jobs with deadline
    while ([DateTime]::UtcNow -lt $deadline) {
        $running = @(Get-Job | Where-Object { $_.State -eq 'Running' })
        if ($running.Count -eq 0) { break }
        Start-Sleep -Milliseconds 200
    }

    # Collect results
    $liveIPs = @()
    Get-Job | Where-Object { $_.State -eq 'Completed' } | ForEach-Object {
        $result = Receive-Job $_ -ErrorAction SilentlyContinue
        if ($result) { $liveIPs += $result }
    }
    Get-Job | Remove-Job -Force -ErrorAction SilentlyContinue

    Write-Log "Port 8000 open on: $($liveIPs.Count) host(s)"

    # Health-check each
    $servers = @()
    foreach ($ip in $liveIPs) {
        if (Test-ServerHealth -IP $ip) {
            $servers += $ip
            Write-Log "Valid server: $ip"
        }
    }

    if ($servers.Count -eq 1) { return $servers[0] }
    if ($servers.Count -gt 1) { return ($servers -join ';') }
    return $null
}

# =====================================================================
# MANUAL INPUT DIALOG (WinForms)
# =====================================================================
function Show-ManualInputDialog {
    param([string]$PreFillIP = "")

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "LawnHive Workspace - Server Address"
    $form.Size = New-Object System.Drawing.Size(420,260)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.BackColor = [System.Drawing.Color]::FromArgb(254,249,243)

    $header = New-Object System.Windows.Forms.Label
    $header.Text = "Enter Your Office Server Address"
    $header.Font = New-Object System.Drawing.Font("Segoe UI",12,[System.Drawing.FontStyle]::Bold)
    $header.ForeColor = [System.Drawing.Color]::FromArgb(26,114,131)
    $header.AutoSize = $true
    $header.Location = New-Object System.Drawing.Point(30,20)
    $form.Controls.Add($header)

    $desc = New-Object System.Windows.Forms.Label
    $desc.Text = "Ask your office manager for the server address.`nThis is usually shown on the Server PC's screen."
    $desc.Font = New-Object System.Drawing.Font("Segoe UI",9)
    $desc.ForeColor = [System.Drawing.Color]::FromArgb(100,100,100)
    $desc.Size = New-Object System.Drawing.Size(350,35)
    $desc.Location = New-Object System.Drawing.Point(30,55)
    $form.Controls.Add($desc)

    $ipLabel = New-Object System.Windows.Forms.Label
    $ipLabel.Text = "Server address:"
    $ipLabel.Font = New-Object System.Drawing.Font("Segoe UI",9)
    $ipLabel.AutoSize = $true
    $ipLabel.Location = New-Object System.Drawing.Point(30,100)
    $form.Controls.Add($ipLabel)

    $ipBox = New-Object System.Windows.Forms.TextBox
    $ipBox.Font = New-Object System.Drawing.Font("Segoe UI",12)
    $ipBox.Size = New-Object System.Drawing.Size(330,30)
    $ipBox.Location = New-Object System.Drawing.Point(30,125)
    $ipBox.Text = $PreFillIP
    $ipBox.BackColor = [System.Drawing.Color]::White
    $form.Controls.Add($ipBox)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = "Example: 192.168.1.5"
    $hint.Font = New-Object System.Drawing.Font("Segoe UI",8)
    $hint.ForeColor = [System.Drawing.Color]::Gray
    $hint.AutoSize = $true
    $hint.Location = New-Object System.Drawing.Point(30,160)
    $form.Controls.Add($hint)

    $okBtn = New-Object System.Windows.Forms.Button
    $okBtn.Text = "Connect"
    $okBtn.Font = New-Object System.Drawing.Font("Segoe UI",10,[System.Drawing.FontStyle]::Bold)
    $okBtn.Size = New-Object System.Drawing.Size(120,35)
    $okBtn.Location = New-Object System.Drawing.Point(100,185)
    $okBtn.BackColor = [System.Drawing.Color]::FromArgb(245,159,54)
    $okBtn.FlatStyle = "Flat"
    $okBtn.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.Controls.Add($okBtn)

    $form.AcceptButton = $okBtn
    $form.Add_Shown({ $ipBox.Focus() })

    $result = $form.ShowDialog()

    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        return $ipBox.Text.Trim()
    }
    return $null
}

# =====================================================================
# VALIDATION ERROR DIALOG
# =====================================================================
function Show-ValidationError {
    param([string]$IP, [string]$Error)

    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        "Could not connect to: $IP`n`nReason: $Error`n`nPlease check:`n- Is the Server PC turned on?`n- Is the address correct?`n- Are you on the same network?",
        "LawnHive Workspace - Connection Failed",
        [System.Windows.Forms.Buttons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
}

# ============================================================================
# MAIN
# ============================================================================
Write-Log "========================================="
Write-Log "LawnHive Workspace Employee Setup"
Write-Log "Install Dir: $InstallDir"
Write-Log "========================================="

try {
    if (-not (Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }

    # Copy icon
    $iconSrc = Join-Path $PSScriptRoot "..\lawnhive.ico"
    if (Test-Path $iconSrc) {
        Copy-Item $iconSrc $IconPath -Force
    }

    # ── Step 1: Auto-detect server ──────────────────────────────────
    Write-Log "Attempting auto-detect..."
    $serverIP = $null
    $needsManual = $true

    $autoResult = Find-ServerAuto

    if ($autoResult -and $autoResult -notmatch ';') {
        # Single server found — confirm with user
        Write-Log "Auto-detected server: $autoResult"
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "Server found on your network:`n`n$autoResult`n`nIs this the correct server?",
            "LawnHive Workspace - Server Found",
            [System.Windows.Forms.Buttons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
        if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
            $serverIP = $autoResult
            $needsManual = $false
        }
    } elseif ($autoResult -and $autoResult -match ';') {
        # Multiple found
        Write-Log "Multiple servers found: $autoResult"
    }

    # ── Step 2: Manual fallback ─────────────────────────────────────
    while ($needsManual) {
        Write-Log "Showing manual input dialog..."
        $inputIP = Show-ManualInputDialog -PreFillIP $(if ($autoResult -and $autoResult -match ';') { ($autoResult -split ';')[0] } else { "" })

        if ($null -eq $inputIP -or $inputIP -eq "") {
            [System.Windows.Forms.MessageBox]::Show(
                "No server address entered. The setup will try again.",
                "LawnHive Workspace",
                [System.Windows.Forms.Buttons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
            continue
        }

        # Validate
        Write-Log "Validating: $inputIP"
        $isValid = Test-ServerHealth -IP $inputIP

        if ($isValid) {
            $serverIP = $inputIP
            $needsManual = $false
        } else {
            Show-ValidationError -IP $inputIP -Error "No response from this address."
        }
    }

    # ── Step 3: Save config + Create shortcuts ──────────────────────
    Write-Log "Server confirmed: $serverIP"

    # Save server address
    $confPath = Join-Path $InstallDir "server.conf"
    [System.IO.File]::WriteAllText($confPath, $serverIP, [System.Text.Encoding]::UTF8)
    Write-Log "Saved: $confPath"

    $serverUrl = "http://${serverIP}:8000"

    # Desktop shortcut
    $desktopPath = [Environment]::GetFolderPath("Desktop")
    $desktopShortcut = Join-Path $desktopPath "LawnHive Workspace.url"
    New-UrlShortcut -Path $desktopShortcut -Url $serverUrl -Icon $IconPath

    # Start Menu shortcut
    $startMenuPath = [Environment]::GetFolderPath("Programs")
    $startMenuDir = Join-Path $startMenuPath "LawnHive Workspace"
    if (-not (Test-Path $startMenuDir)) { New-Item -ItemType Directory -Path $startMenuDir -Force | Out-Null }
    $startShortcut = Join-Path $startMenuDir "LawnHive Workspace.url"
    New-UrlShortcut -Path $startShortcut -Url $serverUrl -Icon $IconPath

    # Copy launcher to install dir
    $launcherSrc = Join-Path $PSScriptRoot "launcher.vbs"
    $launcherDst = Join-Path $InstallDir "Launcher.vbs"
    if (Test-Path $launcherSrc) {
        Copy-Item $launcherSrc $launcherDst -Force
    }

    # Success message
    [System.Windows.Forms.MessageBox]::Show(
        "Setup complete!`n`nA shortcut has been created on your desktop.`nDouble-click it to open LawnHive Workspace.`n`nServer: $serverIP",
        "LawnHive Workspace - Setup Complete",
        [System.Windows.Forms.Buttons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    )

    # Open browser now
    Start-Process $serverUrl

    Write-Log "========================================="
    Write-Log "Employee setup completed successfully!"
    Write-Log "Server: $serverIP"
    Write-Log "========================================="
    exit 0

} catch {
    Write-Log "ERROR: $_"
    [System.Windows.Forms.MessageBox]::Show(
        "Setup encountered an error: $($_.Exception.Message)",
        "LawnHive Workspace - Error",
        [System.Windows.Forms.Buttons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
    exit 1
}
