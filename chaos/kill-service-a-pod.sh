#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=${NAMESPACE:-canary-playground}
LABEL=${LABEL:-app=service-a}

pod=$(kubectl -n "$NAMESPACE" get pods -l "$LABEL" -o jsonpath='{.items[0].metadata.name}')
if [ -z "$pod" ]; then
  echo "No pods matching label $LABEL in namespace $NAMESPACE" >&2
  exit 1
fi

echo "Deleting pod $pod to simulate disruption..."
kubectl -n "$NAMESPACE" delete pod "$pod" --grace-period=0 --force
