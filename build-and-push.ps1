# Build and push Docker image to Docker Hub
# Usage: .\build-and-push.ps1 <docker-hub-username>

param(
    [Parameter(Mandatory=$false)]
    [string]$DockerUsername = "",
    
    [Parameter(Mandatory=$false)]
    [string]$ImageName = "django-site"
)

$ErrorColor = "Red"
$SuccessColor = "Green"
$InfoColor = "Cyan"
$WarningColor = "Yellow"

Write-Host "`n=== Build and Push Docker Image ===" -ForegroundColor $InfoColor

# Check we are in the repository root
if (-not (Test-Path "backend_main_django/Dockerfile")) {
    Write-Host "Error: Run script from k8s-test-django root directory" -ForegroundColor $ErrorColor
    Write-Host "Current directory: $(Get-Location)" -ForegroundColor $ErrorColor
    exit 1
}

# Request username if not provided
if ([string]::IsNullOrEmpty($DockerUsername)) {
    $DockerUsername = Read-Host "Enter your Docker Hub username"
    if ([string]::IsNullOrEmpty($DockerUsername)) {
        Write-Host "Error: Docker Hub username is required" -ForegroundColor $ErrorColor
        exit 1
    }
}

Write-Host "`nDocker Hub username: $DockerUsername" -ForegroundColor $InfoColor
Write-Host "Image name: $ImageName" -ForegroundColor $InfoColor

# Get current commit hash
Write-Host "`nGetting commit hash..." -ForegroundColor $InfoColor
$CommitHash = git rev-parse --short HEAD
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Failed to get commit hash" -ForegroundColor $ErrorColor
    exit 1
}
Write-Host "Commit hash: $CommitHash" -ForegroundColor $SuccessColor

# Check for uncommitted changes
$GitStatus = git status --porcelain
if ($GitStatus) {
    Write-Host "`nWarning: You have uncommitted changes!" -ForegroundColor $WarningColor
    Write-Host "It's recommended to commit changes before building the image." -ForegroundColor $WarningColor
    $Continue = Read-Host "Continue? (y/n)"
    if ($Continue -ne "y") {
        Write-Host "Cancelled by user" -ForegroundColor $WarningColor
        exit 0
    }
}

# Check Docker is running
Write-Host "`nChecking Docker..." -ForegroundColor $InfoColor
docker ps > $null 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Docker is not running or unavailable" -ForegroundColor $ErrorColor
    Write-Host "Start Docker Desktop and try again" -ForegroundColor $ErrorColor
    exit 1
}
Write-Host "Docker is running" -ForegroundColor $SuccessColor

# Build image
Write-Host "`n=== Step 1: Building Docker image ===" -ForegroundColor $InfoColor
Write-Host "Command: docker build -t ${ImageName}:${CommitHash} ./backend_main_django" -ForegroundColor $InfoColor

docker build -t "${ImageName}:${CommitHash}" ./backend_main_django

if ($LASTEXITCODE -ne 0) {
    Write-Host "`nError: Failed to build image" -ForegroundColor $ErrorColor
    exit 1
}
Write-Host "`nImage built successfully: ${ImageName}:${CommitHash}" -ForegroundColor $SuccessColor

# Create tags
Write-Host "`n=== Step 2: Creating tags ===" -ForegroundColor $InfoColor

# Tag with commit hash
$TagWithHash = "${DockerUsername}/${ImageName}:${CommitHash}"
Write-Host "Creating tag: $TagWithHash" -ForegroundColor $InfoColor
docker tag "${ImageName}:${CommitHash}" "$TagWithHash"

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Failed to create tag with hash" -ForegroundColor $ErrorColor
    exit 1
}

# Tag latest
$TagLatest = "${DockerUsername}/${ImageName}:latest"
Write-Host "Creating tag: $TagLatest" -ForegroundColor $InfoColor
docker tag "${ImageName}:${CommitHash}" "$TagLatest"

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Failed to create latest tag" -ForegroundColor $ErrorColor
    exit 1
}

Write-Host "`nTags created successfully" -ForegroundColor $SuccessColor

# Check Docker Hub authentication
Write-Host "`n=== Step 3: Checking Docker Hub authentication ===" -ForegroundColor $InfoColor
Write-Host "If not authenticated, run: docker login" -ForegroundColor $WarningColor

# Push images to Docker Hub
Write-Host "`n=== Step 4: Pushing images to Docker Hub ===" -ForegroundColor $InfoColor

Write-Host "`nPushing image with commit hash..." -ForegroundColor $InfoColor
docker push "$TagWithHash"

if ($LASTEXITCODE -ne 0) {
    Write-Host "`nError: Failed to push image with hash" -ForegroundColor $ErrorColor
    Write-Host "You may not be authenticated to Docker Hub" -ForegroundColor $ErrorColor
    Write-Host "Run: docker login" -ForegroundColor $WarningColor
    exit 1
}

Write-Host "`nPushing latest image..." -ForegroundColor $InfoColor
docker push "$TagLatest"

if ($LASTEXITCODE -ne 0) {
    Write-Host "`nError: Failed to push latest image" -ForegroundColor $ErrorColor
    exit 1
}

# Summary
Write-Host "`n=== Success! ===" -ForegroundColor $SuccessColor
Write-Host "`nImages pushed to Docker Hub:" -ForegroundColor $SuccessColor
Write-Host "  - $TagWithHash" -ForegroundColor $SuccessColor
Write-Host "  - $TagLatest" -ForegroundColor $SuccessColor
Write-Host "`nCheck on Docker Hub: https://hub.docker.com/r/${DockerUsername}/${ImageName}" -ForegroundColor $InfoColor

# Show local images
Write-Host "`nLocal images:" -ForegroundColor $InfoColor
docker images | Select-String -Pattern $ImageName

Write-Host "`n=== Done! ===" -ForegroundColor $SuccessColor
