#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-bookinfo}"

echo "Scaling up in-cluster load generator..."
kubectl -n "${NAMESPACE}" scale deployment load-generator --replicas=1

echo "Load generator started in cluster."
echo "View logs with: kubectl -n ${NAMESPACE} logs -l app=load-generator -f"
