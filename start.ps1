# ==============================================================================
# OpenMRS 3.x — Windows One-Command Orchestrator & Runner
# ==============================================================================
# 1. Checks if Docker is installed
# 2. Checks if Docker Engine is running (starts Docker Desktop if needed)
# 3. Pulls required container images
# 4. Launches OpenMRS 3.x stack via Docker Compose
# ==============================================================================

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

# Define console helpers
function Write-Step {
    param([string]$Message)
    Write-Host "`n[STEP] $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Write-Failure {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

$ProjectRoot = $PSScriptRoot
if (-not $ProjectRoot) {
    $ProjectRoot = Get-Location
}

Write-Host "====================================================================" -ForegroundColor Magenta
Write-Host "       OpenMRS 3.x Pilot — Windows Single-Command Runner            " -ForegroundColor Magenta
Write-Host "====================================================================" -ForegroundColor Magenta

# ------------------------------------------------------------------------------
# 1. Check if Docker is installed
# ------------------------------------------------------------------------------
Write-Step "Checking Docker installation..."

$dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
$dockerDesktopPaths = @(
    "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe",
    "${env:ProgramFiles(x86)}\Docker\Docker\Docker Desktop.exe",
    "$env:LOCALAPPDATA\Programs\Docker\Docker Desktop.exe"
)

$dockerDesktopExe = $null
foreach ($path in $dockerDesktopPaths) {
    if (Test-Path $path) {
        $dockerDesktopExe = $path
        break
    }
}

# If docker CLI isn't in PATH, check Docker bin directory
if (-not $dockerCmd) {
    $dockerBin = "$env:ProgramFiles\Docker\Docker\resources\bin"
    if (Test-Path (Join-Path $dockerBin "docker.exe")) {
        $env:PATH = "$dockerBin;" + $env:PATH
        $dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
    }
}

if (-not $dockerCmd -and -not $dockerDesktopExe) {
    Write-Failure "Docker is not installed on this system."
    Write-Host "Please download and install Docker Desktop for Windows from:" -ForegroundColor Yellow
    Write-Host "👉 https://www.docker.com/products/docker-desktop`n" -ForegroundColor Cyan
    exit 1
}

Write-Success "Docker is installed."

# ------------------------------------------------------------------------------
# 2. Check if Docker Engine is running
# ------------------------------------------------------------------------------
Write-Step "Checking if Docker Engine is running..."

function Test-DockerEngine {
    try {
        & docker info > $null 2>&1
        return ($LASTEXITCODE -eq 0)
    }
    catch {
        return $false
    }
}

$isRunning = Test-DockerEngine

if (-not $isRunning) {
    Write-Warn "Docker Engine is not running. Starting Docker Desktop..."

    if (-not $dockerDesktopExe) {
        Write-Failure "Could not locate 'Docker Desktop.exe'. Please launch Docker Desktop manually."
        exit 1
    }

    try {
        Start-Process -FilePath $dockerDesktopExe
    }
    catch {
        Write-Failure "Failed to launch Docker Desktop: $_"
        exit 1
    }

    Write-Host "Waiting for Docker daemon to initialize..." -ForegroundColor Cyan
    $timeoutSeconds = 120
    $elapsed = 0
    $interval = 3

    while ($elapsed -lt $timeoutSeconds) {
        Start-Sleep -Seconds $interval
        $elapsed += $interval

        Write-Host -NoNewline "." -ForegroundColor DarkGray
        if (Test-DockerEngine) {
            $isRunning = $true
            Write-Host ""
            break
        }
    }

    if (-not $isRunning) {
        Write-Host ""
        Write-Failure "Timed out waiting for Docker Engine to start ($timeoutSeconds seconds)."
        Write-Host "Please check if Docker Desktop needs user interaction or a system restart." -ForegroundColor Yellow
        exit 1
    }
}

Write-Success "Docker Engine is responsive and ready."

# ------------------------------------------------------------------------------
# 3. Prepare Environment Configuration (.env)
# ------------------------------------------------------------------------------
Write-Step "Verifying environment configuration (.env)..."

$rootEnv = Join-Path $ProjectRoot ".env"
$exampleEnv = Join-Path $ProjectRoot ".env.example"
$dockerDir = Join-Path $ProjectRoot "docker"
$dockerEnv = Join-Path $dockerDir ".env"

if (-not (Test-Path $rootEnv)) {
    if (Test-Path $exampleEnv) {
        Write-Warn ".env file missing. Copying from .env.example..."
        Copy-Item $exampleEnv $rootEnv
        Write-Success "Created .env with default development settings."
    }
    else {
        Write-Failure ".env and .env.example are missing. Cannot continue."
        exit 1
    }
}

# Ensure docker/.env is in sync
Copy-Item $rootEnv $dockerEnv -Force

# ------------------------------------------------------------------------------
# 4. Pull Docker Images
# ------------------------------------------------------------------------------
Write-Step "Pulling OpenMRS 3.x and infrastructure images..."

Push-Location $dockerDir
try {
    & docker compose pull
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "Image pull encountered warnings; proceeding with available local caches..."
    }
    else {
        Write-Success "Images are up to date."
    }

    # --------------------------------------------------------------------------
    # 5. Start OpenMRS Containers
    # --------------------------------------------------------------------------
    Write-Step "Preparing and starting OpenMRS containers..."

    # Resolve any name conflicts with legacy or orphaned containers/networks
    $containerNames = @("openmrs-db", "openmrs-backend", "openmrs-frontend", "openmrs-nginx", "openmrs-certbot")
    foreach ($c in $containerNames) {
        $cExists = (& docker ps -a --filter "name=^/${c}$" --format "{{.ID}}")
        if ($cExists) {
            $cProject = (& docker inspect $c --format '{{index .Config.Labels "com.docker.compose.project"}}' 2>$null)
            if ($cProject -and $cProject -ne "oncopenmrs") {
                Write-Warn "Cleaning up legacy container: $c (project: '$cProject')"
                & docker rm -f $c > $null 2>&1
            }
        }
    }

    $netExists = (& docker network ls --filter "name=^openmrs-internal-net$" --format "{{.Name}}")
    if ($netExists) {
        $netProject = (& docker network inspect openmrs-internal-net --format '{{index .Labels "com.docker.compose.project"}}' 2>$null)
        if ($netProject -and $netProject -ne "oncopenmrs") {
            Write-Warn "Recreating legacy network 'openmrs-internal-net' (project: '$netProject')..."
            & docker network rm openmrs-internal-net > $null 2>&1
        }
    }

    & docker compose up -d

    if ($LASTEXITCODE -ne 0) {
        Write-Failure "docker compose up failed with exit code $LASTEXITCODE."
        Pop-Location
        exit 1
    }

    Write-Success "Containers are running!"
    Write-Host "`nContainer Status:" -ForegroundColor Cyan
    & docker compose ps
}
finally {
    Pop-Location
}

# ------------------------------------------------------------------------------
# 6. Guidance & Next Steps
# ------------------------------------------------------------------------------
Write-Host "`n====================================================================" -ForegroundColor Green
Write-Host "  OpenMRS 3.x Stack Successfully Launched!                          " -ForegroundColor Green
Write-Host "====================================================================" -ForegroundColor Green
Write-Host "`nAccess URLs:" -ForegroundColor White
Write-Host "  👉 Frontend SPA:  http://localhost/openmrs/spa/home" -ForegroundColor Cyan
Write-Host "  👉 REST / FHIR:   http://localhost/openmrs" -ForegroundColor Cyan

Write-Host "`nNotice for First-Time Run:" -ForegroundColor Yellow
Write-Host "  On first run, the backend initializes the database migrations (~240 tables)." -ForegroundColor Gray
Write-Host "  This takes approximately 2-3 minutes. If the page shows a setup wizard or loads slowly," -ForegroundColor Gray
Write-Host "  simply wait a couple of minutes." -ForegroundColor Gray

Write-Host "`nUseful Commands:" -ForegroundColor White
Write-Host "  • View Backend Logs:  docker compose -f docker/docker-compose.yml logs -f openmrs-backend" -ForegroundColor DarkCyan
Write-Host "  • View All Logs:      docker compose -f docker/docker-compose.yml logs -f" -ForegroundColor DarkCyan
Write-Host "  • Stop the Stack:     docker compose -f docker/docker-compose.yml down" -ForegroundColor DarkCyan
Write-Host ""
