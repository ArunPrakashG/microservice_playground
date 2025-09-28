param(
    [switch]$Recreate,
    [ValidateSet("phase1", "phase2", "phase3", "all")]
    [string]$Phase = "all"
)

# Bootstraps the Microservice Canary Playground on Windows PowerShell.
# - Creates (or recreates) the k3d cluster defined in clusters/k3d/cluster.yaml
# - Builds and imports the demo microservice images into the cluster registry
# - Applies Kubernetes manifests for the requested phase(s)

$ErrorActionPreference = "Stop"
$clusterName = "canary-playground"
$registryName = "k3d-$clusterName"
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")

function Assert-Dependency($command) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "Required command '$command' was not found in PATH."
    }
}

Assert-Dependency -command "k3d"
Assert-Dependency -command "kubectl"
Assert-Dependency -command "docker"

if ($Recreate) {
    Write-Host "Deleting existing cluster $clusterName (if present)..."
    k3d cluster delete $clusterName | Out-Null
}

$clusterExists = (k3d cluster list --no-headers | Where-Object { $_ -match "^$clusterName\s" })
if (-not $clusterExists) {
    Write-Host "Creating k3d cluster $clusterName from clusters/k3d/cluster.yaml..."
    $clusterConfig = Resolve-Path (Join-Path $repoRoot "clusters/k3d/cluster.yaml")
    k3d cluster create --config $clusterConfig
}
else {
    Write-Host "Cluster $clusterName already exists. Use -Recreate to rebuild it."
}

$images = @(
    @{ Path = Join-Path $repoRoot "services/service-a/v1"; Tag = "canary-playground/service-a:v1" },
    @{ Path = Join-Path $repoRoot "services/service-a/v2"; Tag = "canary-playground/service-a:v2" },
    @{ Path = Join-Path $repoRoot "services/service-b/app"; Tag = "canary-playground/service-b:latest" },
    @{ Path = Join-Path $repoRoot "loadtest"; Tag = "canary-playground/locust:latest" }
)

foreach ($image in $images) {
    $dockerfile = Join-Path (Resolve-Path $image.Path) "Dockerfile"
    if (-not (Test-Path $dockerfile)) {
        Write-Warning "Skip build: Dockerfile not found at $dockerfile."
        continue
    }

    Write-Host "Building image $($image.Tag) from $($image.Path)..."
    docker build --pull --tag $image.Tag $image.Path
    Write-Host "Importing $($image.Tag) into k3d cluster..."
    k3d image import $image.Tag -c $clusterName
}

function Apply-Phase($phaseName, $paths) {
    Write-Host "Applying Kubernetes manifests for $phaseName..." -ForegroundColor Cyan
    foreach ($path in $paths) {
        $resolved = Resolve-Path $path -ErrorAction SilentlyContinue
        if (-not $resolved) {
            Write-Warning "Skipping $path (not found)."
            continue
        }

        kubectl apply -f $resolved
    }
}

function Test-ChaosMeshInstalled {
    try {
        $apiResources = kubectl api-resources --no-headers | Out-String
        return ($apiResources -match "podchaos") -and ($apiResources -match "networkchaos")
    }
    catch {
        Write-Warning "Failed to query api-resources: $_"
        return $false
    }
}

$chaosMeshAvailable = $null

switch ($Phase.ToLower()) {
    "phase1" {
        Apply-Phase "Phase 1" @(
            Join-Path $repoRoot "observability/prometheus/prometheus-config.yaml",
            Join-Path $repoRoot "observability/grafana/datasource-config.yaml",
            Join-Path $repoRoot "observability/grafana/dashboard-providers.yaml",
            Join-Path $repoRoot "deployments/service-a/phase1",
            Join-Path $repoRoot "deployments/observability/phase1"
        )
    }
    "phase2" {
        Apply-Phase "Phase 1" @(
            Join-Path $repoRoot "observability/prometheus/prometheus-config.yaml",
            Join-Path $repoRoot "observability/grafana/datasource-config.yaml",
            Join-Path $repoRoot "observability/grafana/dashboard-providers.yaml",
            Join-Path $repoRoot "deployments/service-a/phase1",
            Join-Path $repoRoot "deployments/observability/phase1"
        )
        Apply-Phase "Phase 2" @(
            Join-Path $repoRoot "deployments/service-a/phase2",
            Join-Path $repoRoot "deployments/service-b/phase2",
            Join-Path $repoRoot "deployments/gateway",
            Join-Path $repoRoot "deployments/loadtest"
        )
    }
    "phase3" {
        Apply-Phase "Phase 1" @(
            Join-Path $repoRoot "observability/prometheus/prometheus-config.yaml",
            Join-Path $repoRoot "observability/grafana/datasource-config.yaml",
            Join-Path $repoRoot "observability/grafana/dashboard-providers.yaml",
            Join-Path $repoRoot "deployments/service-a/phase1",
            Join-Path $repoRoot "deployments/observability/phase1"
        )
        Apply-Phase "Phase 2" @(
            Join-Path $repoRoot "deployments/service-a/phase2",
            Join-Path $repoRoot "deployments/service-b/phase2",
            Join-Path $repoRoot "deployments/gateway",
            Join-Path $repoRoot "deployments/loadtest"
        )
        if ($chaosMeshAvailable -eq $null) {
            $chaosMeshAvailable = Test-ChaosMeshInstalled
        }
        if ($chaosMeshAvailable) {
            Apply-Phase "Phase 3" @(
                Join-Path $repoRoot "deployments/chaos"
            )
        }
        else {
            Write-Warning "Chaos Mesh CRDs not detected. Install Chaos Mesh before running phase3."
        }
    }
    default {
        Apply-Phase "Phase 1" @(
            Join-Path $repoRoot "observability/prometheus/prometheus-config.yaml",
            Join-Path $repoRoot "observability/grafana/datasource-config.yaml",
            Join-Path $repoRoot "observability/grafana/dashboard-providers.yaml",
            Join-Path $repoRoot "deployments/service-a/phase1",
            Join-Path $repoRoot "deployments/observability/phase1"
        )
        Apply-Phase "Phase 2" @(
            Join-Path $repoRoot "deployments/service-a/phase2",
            Join-Path $repoRoot "deployments/service-b/phase2",
            Join-Path $repoRoot "deployments/gateway",
            Join-Path $repoRoot "deployments/loadtest"
        )
        if ($chaosMeshAvailable -eq $null) {
            $chaosMeshAvailable = Test-ChaosMeshInstalled
        }
        if ($chaosMeshAvailable) {
            Apply-Phase "Phase 3" @(
                Join-Path $repoRoot "deployments/chaos"
            )
        }
        else {
            Write-Warning "Chaos Mesh CRDs not detected. Install Chaos Mesh before applying phase 3 resources."
        }
    }
}

$dashboardsPath = Join-Path $repoRoot "observability/grafana/dashboards"
if (Test-Path $dashboardsPath) {
    Write-Host "Synchronizing Grafana dashboards from $dashboardsPath..."
    kubectl create configmap grafana-dashboards --from-file=$dashboardsPath --dry-run=client -o yaml | kubectl apply -f -
}

Write-Host "Bootstrap complete!" -ForegroundColor Green
