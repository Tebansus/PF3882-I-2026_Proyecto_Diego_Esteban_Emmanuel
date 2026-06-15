#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-bookinfo}"

echo "Scaling down in-cluster load generator..."
kubectl -n "${NAMESPACE}" scale deployment load-generator --replicas=0

echo "Stopped in-cluster load generator."
