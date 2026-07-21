# PowerShell script to install Frappe Drive app
# For Windows environments

Write-Host "Installing Frappe Drive App..." -ForegroundColor Green

# Function to check if we're in a Frappe bench directory
function Test-BenchDirectory {
    if (Test-Path "apps" -PathType Container) {
        return $true
    } elseif (Test-Path "bench*") {
        return $true
    }
    return $false
}

# Check current directory
if (-not (Test-BenchDirectory)) {
    Write-Host "Error: Not in a Frappe bench directory" -ForegroundColor Red
    Write-Host "Please navigate to your bench directory first" -ForegroundColor Yellow
    Write-Host "Example: cd C:\frappe-bench" -ForegroundColor Yellow
    exit 1
}

try {
    # Install Drive app
    Write-Host "Getting Drive app from GitHub..." -ForegroundColor Blue
    bench get-app https://github.com/frappe/drive --branch main
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Drive app downloaded successfully" -ForegroundColor Green
        
        # Check available sites
        Write-Host "Available sites:" -ForegroundColor Blue
        bench list-sites
        
        # Install on specified site
        $siteName = "hrms.localhost"
        Write-Host "Installing Drive app on site: $siteName" -ForegroundColor Blue
        
        bench --site $siteName install-app drive
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Drive app installed successfully on $siteName" -ForegroundColor Green
            Write-Host "Running migrations..." -ForegroundColor Blue
            bench --site $siteName migrate
            bench restart
            Write-Host "Installation completed successfully!" -ForegroundColor Green
        } else {
            Write-Host "Failed to install Drive app on $siteName" -ForegroundColor Red
            Write-Host "Make sure the site exists and is accessible" -ForegroundColor Yellow
        }
    } else {
        Write-Host "Failed to download Drive app" -ForegroundColor Red
        Write-Host "Check your internet connection and GitHub access" -ForegroundColor Yellow
    }
} catch {
    Write-Host "An error occurred: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "Installation script completed." -ForegroundColor Green