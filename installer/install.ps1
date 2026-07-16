# ══════════════════════════════════════════════════════════════════════
# install.ps1 — LawnHive HRM Installer Helper
# Called by Inno Setup during installation
# ══════════════════════════════════════════════════════════════════════

param(
    [string]$AppDir,
    [string]$ClientId = "NGO001"
)

$ErrorActionPreference = "Stop"

function Write-Step($msg) {
    Write-Host "`n>>> $msg" -ForegroundColor Cyan
}

# ── Generate random password (12 chars: letters + numbers + symbols) ──
function New-StrongPassword {
    $upper   = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
    $lower   = 'abcdefghjkmnpqrstuvwxyz'
    $digits  = '23456789'
    $symbols = '!@#$%'
    $all     = $upper + $lower + $digits + $symbols

    $pw = @()
    $pw += $upper[(Get-Random -Maximum $upper.Length)]
    $pw += $upper[(Get-Random -Maximum $upper.Length)]
    $pw += $lower[(Get-Random -Maximum $lower.Length)]
    $pw += $lower[(Get-Random -Maximum $lower.Length)]
    $pw += $lower[(Get-Random -Maximum $lower.Length)]
    $pw += $digits[(Get-Random -Maximum $digits.Length)]
    $pw += $digits[(Get-Random -Maximum $digits.Length)]
    $pw += $digits[(Get-Random -Maximum $digits.Length)]
    $pw += $symbols[(Get-Random -Maximum $symbols.Length)]
    for ($i = 0; $i -lt 3; $i++) {
        $pw += $all[(Get-Random -Maximum $all.Length)]
    }
    return ($pw | Sort-Object { Get-Random }) -join ''
}

# ══════════════════════════════════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════════════════════════════════

Write-Host "`n============================================" -ForegroundColor Yellow
Write-Host "  LawnHive HRM Software — Installer" -ForegroundColor Yellow
Write-Host "============================================`n" -ForegroundColor Yellow

# Step 1: Check Docker
Write-Step "Step 1/7: Checking Docker..."
try {
    docker info 2>&1 | Out-Null
    Write-Host "  Docker is running." -ForegroundColor Green
} catch {
    Write-Host "  ERROR: Docker Desktop is not running!" -ForegroundColor Red
    Write-Host "  Please install and start Docker Desktop first." -ForegroundColor Red
    Write-Host "  Download: https://docs.docker.com/desktop/install/windows-install/" -ForegroundColor Yellow
    exit 1
}

# Step 2: Start containers
Write-Step "Step 2/7: Starting containers..."
Set-Location "$AppDir\docker"
docker compose up -d
Start-Sleep -Seconds 10
Write-Host "  Containers started." -ForegroundColor Green

# Step 3: Wait for Frappe
Write-Step "Step 3/7: Waiting for Frappe to start (may take 2-5 minutes)..."
$timeout = 300
$elapsed = 0
while ($elapsed -lt $timeout) {
    try {
        $r = Invoke-WebRequest -Uri 'http://localhost:8080' -TimeoutSec 5 -UseBasicParsing
        if ($r.StatusCode -eq 200) {
            Write-Host "  Frappe is ready!" -ForegroundColor Green
            break
        }
    } catch {}
    Start-Sleep 5
    $elapsed += 5
    Write-Host "  Waiting... ($elapsed/$timeout seconds)" -ForegroundColor Gray
}
if ($elapsed -ge $timeout) {
    Write-Host "  WARNING: Frappe may not be fully ready. Check Docker logs." -ForegroundColor Yellow
}

# Step 4: Create site
Write-Step "Step 4/7: Creating site..."
$siteExists = docker exec docker-frappe-1 bash -c "ls /home/frappe/frappe-bench/sites/site1.local 2>/dev/null"
if ($siteExists) {
    Write-Host "  Site already exists, skipping." -ForegroundColor Gray
} else {
    docker exec docker-frappe-1 bash -c "cd /home/frappe/frappe-bench && bench new-site site1.local --mariadb-root-password 123 --admin-password admin --set-default-language en 2>&1 | tail -5"
    Write-Host "  Site created." -ForegroundColor Green
}

# Step 5: Install apps
Write-Step "Step 5/7: Installing ERPNext + HRMS..."
docker exec docker-frappe-1 bash -c "cd /home/frappe/frappe-bench && bench --site site1.local install-app erpnext 2>&1 | tail -1"
docker exec docker-frappe-1 bash -c "cd /home/frappe/frappe-bench && bench --site site1.local install-app hrms 2>&1 | tail -1"
Write-Host "  Apps installed." -ForegroundColor Green

# Step 6: Apply branding
Write-Step "Step 6/7: Applying LawnHive branding..."
docker cp "$AppDir\lawnhive_branding" docker-frappe-1:/home/frappe/frappe-bench/apps/lawnhive_branding
docker cp "$AppDir\license_control" docker-frappe-1:/home/frappe/frappe-bench/apps/license_control
docker exec docker-frappe-1 bash -c "cd /home/frappe/frappe-bench && pip install -e apps/lawnhive_branding -e apps/license_control 2>&1 | tail -2"
docker exec docker-frappe-1 bash -c "cd /home/frappe/frappe-bench && bench --site site1.local install-app license_control 2>&1 | tail -1"
Write-Host "  Branding applied." -ForegroundColor Green

# Step 7: Generate password and set admin
Write-Step "Step 7/7: Generating admin password..."
$generatedPassword = New-StrongPassword
docker exec docker-frappe-1 bash -c "cd /home/frappe/frappe-bench && bench --site site1.local set-admin-password $generatedPassword 2>&1 | tail -1"

# Set client_id in site_config
docker exec docker-frappe-1 bash -c "cd /home/frappe/frappe-bench/sites/site1.local && python3 -c `"import json; c=json.load(open('site_config.json')); c['client_id']='${ClientId}'; json.dump(c,open('site_config.json','w'))`""

# Save credentials to file
$credentialsContent = @"
============================================
  LawnHive HRM — Login Credentials
  KEEP THIS FILE SAFE!
============================================

Client ID:     $ClientId
Admin Password: $generatedPassword
Login URL:     http://localhost:8080

Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

============================================
"@

$credentialsPath = "$AppDir\credentials_output.txt"
Set-Content -Path $credentialsPath -Value $credentialsContent -Encoding UTF8
Write-Host "  Credentials saved to: $credentialsPath" -ForegroundColor Green

# Create desktop shortcut
$ws = New-Object -ComObject WScript.Shell
$sc = $ws.CreateShortcut([Environment]::GetFolderPath('Desktop') + '\LawnHive HRM.lnk')
$sc.TargetPath = 'http://localhost:8080'
$sc.Description = 'LawnHive HRM Software'
$sc.Save()

# ══════════════════════════════════════════════════════════════════════
# FINAL DISPLAY
# ══════════════════════════════════════════════════════════════════════

Write-Host "`n" -NoNewline
Write-Host "============================================" -ForegroundColor Yellow
Write-Host "  INSTALLATION COMPLETE!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Client ID:      $ClientId" -ForegroundColor White
Write-Host "  Admin Password:  $generatedPassword" -ForegroundColor White
Write-Host "  Login URL:       http://localhost:8080" -ForegroundColor White
Write-Host ""
Write-Host "  Credentials saved to:" -ForegroundColor Gray
Write-Host "  $credentialsPath" -ForegroundColor Gray
Write-Host ""
Write-Host "  Desktop shortcut: LawnHive HRM" -ForegroundColor Gray
Write-Host ""
Write-Host "============================================" -ForegroundColor Yellow
Write-Host "  SAVE THIS PASSWORD NOW!" -ForegroundColor Red
Write-Host "============================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "Press Enter to close..." -NoNewline
Read-Host
