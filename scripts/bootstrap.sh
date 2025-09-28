#!/usr/bin/env bash
set -euo pipefail

# Bootstraps the Microservice Canary Playground on Unix shells.
# Mirrors bootstrap.ps1 but sticks to portable bash utilities so it can be run
# inside WSL, Git Bash, or a macOS/Linux terminal.

CLUSTER_NAME="canary-playground"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ensure_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Expected '$1' on PATH" >&2
    exit 1
  fi
}

ensure_cmd k3d
ensure_cmd kubectl
ensure_cmd docker

RECREATE=${RECREATE:-false}
PHASE=${PHASE:-all}

if [ "$RECREATE" = "true" ]; then
  echo "Deleting existing cluster $CLUSTER_NAME (if present)..."
  k3d cluster delete "$CLUSTER_NAME" || true
fi

if ! k3d cluster list --no-headers | grep -q "^$CLUSTER_NAME\s"; then
  echo "Creating k3d cluster $CLUSTER_NAME from clusters/k3d/cluster.yaml..."
  k3d cluster create --config "$REPO_ROOT/clusters/k3d/cluster.yaml"
else
  echo "Cluster $CLUSTER_NAME already exists. Set RECREATE=true to rebuild."
fi

mapfile -t IMAGES <<'EOF'
services/service-a/v1 canary-playground/service-a:v1
services/service-a/v2 canary-playground/service-a:v2
services/service-b/app canary-playground/service-b:latest
loadtest canary-playground/locust:latest
EOF

for entry in "${IMAGES[@]}"; do
  path="${entry%% *}"
  tag="${entry##* }"
  dockerfile="$REPO_ROOT/$path/Dockerfile"
  if [ ! -f "$dockerfile" ]; then
    echo "Skipping $tag (Dockerfile not found at $dockerfile)"
    continue
  fi
  echo "Building $tag from $path..."
  docker build --pull --tag "$tag" "$REPO_ROOT/$path"
  echo "Importing $tag into k3d..."
  k3d image import "$tag" -c "$CLUSTER_NAME"
done

apply_phase() {
  local phase_name="$1"; shift
  echo "Applying manifests for ${phase_name}..."
  for manifest_dir in "$@"; do
    if [ ! -d "$manifest_dir" ]; then
      echo "Skipping $manifest_dir (missing)"
      continue
    fi
    kubectl apply -f "$manifest_dir"
  done
}

chaos_mesh_installed() {
  if kubectl api-resources --no-headers | grep -q "podchaos" && \
     kubectl api-resources --no-headers | grep -q "networkchaos"; then
    return 0
  else
    return 1
  fi
}

CHAOS_READY="unset"

case "$PHASE" in
  phase1)
    apply_phase "Phase 1" \
      "$REPO_ROOT/observability/prometheus/prometheus-config.yaml" \
      "$REPO_ROOT/observability/grafana/datasource-config.yaml" \
      "$REPO_ROOT/observability/grafana/dashboard-providers.yaml" \
      "$REPO_ROOT/deployments/service-a/phase1" \
      "$REPO_ROOT/deployments/observability/phase1"
    ;;
  phase2)
    apply_phase "Phase 1" \
      "$REPO_ROOT/observability/prometheus/prometheus-config.yaml" \
      "$REPO_ROOT/observability/grafana/datasource-config.yaml" \
      "$REPO_ROOT/observability/grafana/dashboard-providers.yaml" \
      "$REPO_ROOT/deployments/service-a/phase1" \
      "$REPO_ROOT/deployments/observability/phase1"
    apply_phase "Phase 2" \
      "$REPO_ROOT/deployments/service-a/phase2" \
      "$REPO_ROOT/deployments/service-b/phase2" \
      "$REPO_ROOT/deployments/gateway" \
      "$REPO_ROOT/deployments/loadtest"
    ;;
  phase3)
    apply_phase "Phase 1" \
      "$REPO_ROOT/observability/prometheus/prometheus-config.yaml" \
      "$REPO_ROOT/observability/grafana/datasource-config.yaml" \
      "$REPO_ROOT/observability/grafana/dashboard-providers.yaml" \
      "$REPO_ROOT/deployments/service-a/phase1" \
      "$REPO_ROOT/deployments/observability/phase1"
    apply_phase "Phase 2" \
      "$REPO_ROOT/deployments/service-a/phase2" \
      "$REPO_ROOT/deployments/service-b/phase2" \
      "$REPO_ROOT/deployments/gateway" \
      "$REPO_ROOT/deployments/loadtest"
    if [ "$CHAOS_READY" = "unset" ]; then
      if chaos_mesh_installed; then
        CHAOS_READY="true"
      else
        CHAOS_READY="false"
      fi
    fi
    if [ "$CHAOS_READY" = "true" ]; then
      apply_phase "Phase 3" \
        "$REPO_ROOT/deployments/chaos"
    else
      echo "Chaos Mesh not detected. Install it before running Phase 3." >&2
    fi
    ;;
  all|*)
    apply_phase "Phase 1" \
      "$REPO_ROOT/observability/prometheus/prometheus-config.yaml" \
      "$REPO_ROOT/observability/grafana/datasource-config.yaml" \
      "$REPO_ROOT/observability/grafana/dashboard-providers.yaml" \
      "$REPO_ROOT/deployments/service-a/phase1" \
      "$REPO_ROOT/deployments/observability/phase1"
    apply_phase "Phase 2" \
      "$REPO_ROOT/deployments/service-a/phase2" \
      "$REPO_ROOT/deployments/service-b/phase2" \
      "$REPO_ROOT/deployments/gateway" \
      "$REPO_ROOT/deployments/loadtest"
    if [ "$CHAOS_READY" = "unset" ]; then
      if chaos_mesh_installed; then
        CHAOS_READY="true"
      else
        CHAOS_READY="false"
      fi
    fi
    if [ "$CHAOS_READY" = "true" ]; then
      apply_phase "Phase 3" \
        "$REPO_ROOT/deployments/chaos"
    else
      echo "Chaos Mesh not detected. Install it before applying Phase 3 resources." >&2
    fi
    ;;
 esac

if [ -d "$REPO_ROOT/observability/grafana/dashboards" ]; then
  echo "Synchronizing Grafana dashboards..."
  kubectl create configmap grafana-dashboards \
    --from-file="$REPO_ROOT/observability/grafana/dashboards" \
    --dry-run=client -o yaml | kubectl apply -f -
fi

echo "Bootstrap complete!"
