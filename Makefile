SHELL := /bin/bash

# Convenience targets for bringing the playground up on Unix shells.
# Windows users can run the equivalent PowerShell commands documented in README.

cluster := canary-playground

.PHONY: bootstrap phase1 phase2 phase3 cleanup loadtest chaos dashboards

bootstrap:
	./scripts/bootstrap.sh

phase1:
	PHASE=phase1 ./scripts/bootstrap.sh

phase2:
	PHASE=phase2 ./scripts/bootstrap.sh

phase3:
	PHASE=phase3 ./scripts/bootstrap.sh

cleanup:
	k3d cluster delete $(cluster)

loadtest:
	kubectl apply -f deployments/loadtest

chaos:
	kubectl apply -f deployments/chaos

# Utility target to (re)apply dashboards if you tweak JSON files.
dashboards:
	kubectl create configmap grafana-dashboards --from-file=observability/grafana/dashboards --dry-run=client -o yaml | kubectl apply -f -
