# Microservice Canary Playground

A self-contained sandbox for mastering canary deployments, traffic shaping, chaos engineering, and observability on a local Kubernetes (k3d) cluster. The playground deploys FastAPI demo services, an Envoy gateway with canary routing, Prometheus + Grafana dashboards, Locust load generation, and optional Chaos Mesh experiments.

## Prerequisites

Install the following locally (macOS/Linux/Windows + WSL supported):

- Docker 24+
- [k3d](https://k3d.io/) 5+
- kubectl 1.27+
- Python 3.11+ (for quick syntax checks)
- Optional (Phase 3): [Chaos Mesh](https://chaos-mesh.org/) `v2.7+` installed in the cluster

On Windows, run the PowerShell commands in an elevated PowerShell window. For macOS/Linux/WSL, use the provided shell scripts or `Makefile` targets.

## Quick start

Clone the repo and bootstrap everything:

```powershell
# Windows PowerShell
cd .\microservice_playground\scripts
./bootstrap.ps1
```

```bash
# macOS/Linux/WSL
cd microservice_playground
./scripts/bootstrap.sh
```

The bootstrap script:

1. Creates the `canary-playground` k3d cluster (with optional registry) if it does not exist.
2. Builds Docker images for all services + Locust and imports them into the cluster.
3. Applies Kubernetes manifests in phased order (see below).
4. Synchronizes Grafana dashboards from `observability/grafana/dashboards`.

### Phased rollouts

You can provision pieces of the stack incrementally:

```powershell
# Windows PowerShell examples
./bootstrap.ps1 -Phase phase1        # Baseline service + observability
./bootstrap.ps1 -Phase phase2        # Adds canary v2, Envoy gateway, Locust
./bootstrap.ps1 -Phase phase3        # Also applies chaos experiments
./bootstrap.ps1 -Recreate            # Tear down and rebuild the cluster
```

```bash
# Makefile shortcuts for macOS/Linux/WSL
make phase1
make phase2
make phase3
```

Phase summary:

- **Phase 1** – Namespace, `service-a:v1`, Prometheus, Grafana, baseline dashboards
- **Phase 2** – Adds `service-a:v2`, aggregated `service-b`, Envoy gateway with 90/10 routing, Locust deployment
- **Phase 3** – Applies Chaos Mesh experiments (skipped automatically if CRDs are missing)

## What gets deployed

| Component | Notes |
|-----------|-------|
| `service-a:v1` | FastAPI baseline version with predictable latency |
| `service-a:v2` | FastAPI canary with variable latency + synthetic failures |
| `service-b` | Aggregator calling `service-a` for fortunes |
| Envoy Gateway | Routes `/` traffic 90/10 between v1/v2, `/service-b` to service-b |
| Prometheus | Scrapes all services, Envoy admin, Locust |
| Grafana | Includes ready-to-use *Service-A Canary Overview* dashboard |
| Locust | Web UI (NodePort `30089`) to drive configurable traffic |
| Chaos Mesh CRs | Pod kill + latency + packet loss experiments for service-a (Phase 3) |

External ports are mapped via k3d load balancer:

| Service | URL |
|---------|-----|
| Envoy gateway | <http://localhost:8080> |
| Prometheus | <http://localhost:9090> |
| Grafana | <http://localhost:3000> (user/pass: `admin`/`admin`) |
| Locust UI | <http://localhost:30089> |

## Observability & dashboards

Grafana automatically provisions the Prometheus datasource and imports `observability/grafana/dashboards/service-a-canary.json`. Update the JSON and rerun the bootstrap script (or `make dashboards`) to sync changes.

Dashboard highlights:

- Request throughput per service-a instance (`req/s`)
- P95 latency by instance (observe canary slowdown under load)
- Error-rate percentage with synthetic 500s introduced by v2

## Driving load with Locust

Launch the Locust web UI:

```bash
kubectl -n canary-playground get svc locust
```

Open the NodePort (`localhost:30089`) and start a swarm. Default targets:

- `/` hits the canary-weighted Envoy route
- `/fortunes` exercises the second FastAPI endpoint
- `/service-b/aggregate` drills the aggregator calling service-a
- `/beta-insights` (tagged scenario) simulates gated beta traffic

You can override endpoints via environment variables on the Locust deployment or by running Locust locally with `TARGET_HOST`, `CANARY_ENDPOINT`, etc.

## Chaos experiments (Phase 3)

### Prerequisite: install Chaos Mesh

```bash
kubectl create ns chaos-mesh
helm repo add chaos-mesh https://charts.chaos-mesh.org
helm install chaos-mesh chaos-mesh/chaos-mesh \
  --namespace chaos-mesh \
  --set chaosDaemon.runtime=containerd \
  --set chaosDaemon.socketPath=/run/k3s/containerd/containerd.sock
```

Re-run `./scripts/bootstrap.sh PHASE=phase3` (or `./bootstrap.ps1 -Phase phase3`). The script detects the `podchaos`/`networkchaos` CRDs before applying `deployments/chaos/chaos-experiments.yaml`:

- `PodChaos` randomly kills one `service-a` pod every 5 minutes for 30 seconds.
- `NetworkChaos` injects 250 ms delay (±50 ms jitter) to all `service-a:v2` pods every 10 minutes.
- `NetworkChaos` drops 20 % of packets to `service-a:v2` on a separate schedule.

Manual disruption helpers live in `chaos/`:

```bash
./chaos/kill-service-a-pod.sh              # Bash
powershell -File .\chaos\kill-service-a-pod.ps1  # PowerShell
```

## Tear down

```bash
# macOS/Linux/WSL
make cleanup
```

```powershell
# Windows PowerShell
k3d cluster delete canary-playground
```

## Optional enhancements

- Add automated rollback logic reacting to Prometheus alerts.
- Wire in Jaeger or OpenTelemetry Collector for distributed traces.
- Extend Grafana dashboards with service-b and Locust metrics.
- Parameterize Envoy canary weights via ConfigMap updates or Argo Rollouts.

## Verification

Syntax checks run with `python -m compileall` on all FastAPI services and Locust scripts. No additional automated tests are bundled; run `kubectl get pods -n canary-playground` after bootstrap to confirm everything is `Running`.
