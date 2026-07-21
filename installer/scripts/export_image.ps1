# ============================================================================
# LawnHive Workspace - Image Export Script
# ============================================================================
# Run this on a computer with internet access (not the client PC).
# It exports the Docker image to a .tar file for pendrive distribution.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File export_image.ps1
# ============================================================================

$ErrorActionPreference = "Stop"
$ImageName = "faisalabdullahabir/workspace:latest"
$TarFile = "lawnhive-image.tar"

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "  LawnHive Workspace - Image Export" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

# ── Step 1: Check Docker ────────────────────────────────────────────
Write-Host "[1/3] Checking Docker..." -ForegroundColor Yellow
try {
    docker info 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Docker not running" }
    Write-Host "  Docker is running." -ForegroundColor Green
} catch {
    Write-Host "  ERROR: Docker Desktop is not running." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

# ── Step 2: Pull latest image ───────────────────────────────────────
Write-Host ""
Write-Host "[2/3] Pulling latest image from Docker Hub..." -ForegroundColor Yellow
Write-Host "  (This may take 10-20 minutes depending on your internet)" -ForegroundColor Gray

docker pull $ImageName
if ($LASTEXITCODE -ne 0) {
    Write-Host "  ERROR: Failed to pull image." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}
Write-Host "  Image pulled successfully." -ForegroundColor Green

# ── Step 3: Save image to .tar ──────────────────────────────────────
Write-Host ""
Write-Host "[3/3] Saving image to file (this may take 5-15 minutes)..." -ForegroundColor Yellow
Write-Host "  Output: $(Join-Path $PWD $TarFile)" -ForegroundColor Gray

if (Test-Path $TarFile) { Remove-Item $TarFile -Force }

docker save $ImageName -o $TarFile
if ($LASTEXITCODE -ne 0) {
    Write-Host "  ERROR: Failed to save image." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

$tarSize = (Get-Item $TarFile).Length
$tarSizeGB = [math]::Round($tarSize / 1GB, 2)
$tarSizeMB = [math]::Round($tarSize / 1MB, 1)

# ── Summary ─────────────────────────────────────────────────────────
Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "  Export Complete!" -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  File created:" -ForegroundColor Yellow
Write-Host "    $TarFile  ($tarSizeGB GB / $tarSizeMB MB)" -ForegroundColor White
Write-Host ""
Write-Host "  Next steps:" -ForegroundColor Yellow
Write-Host "    1. Copy this .tar file to your pendrive" -ForegroundColor White
Write-Host "    2. Place it in a folder called 'lawnhive-image'" -ForegroundColor White
Write-Host "    3. Put the installer .exe alongside it" -ForegroundColor White
Write-Host ""
Write-Host "  Pendrive structure:" -ForegroundColor Gray
Write-Host "    Pendrive:\" -ForegroundColor Gray
Write-Host "      LawnHiveWorkspaceSetup.exe" -ForegroundColor Gray
Write-Host "      lawnhive-image\" -ForegroundColor Gray
Write-Host "        lawnhive-image.tar" -ForegroundColor Gray
Write-Host ""

Read-Host "Press Enter to exit"
