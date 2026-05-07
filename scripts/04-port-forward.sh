#!/usr/bin/env bash
set -euo pipefail

# Alternative to the NodePort exposure: forwards productpage:9080 to localhost:9080.
# Runs in the foreground; Ctrl+C to stop.

CLUSTER_NAME="${CLUSTER_NAME:-bookinfo}"
NAMESPACE="${NAMESPACE:-bookinfo}"
LOCAL_PORT="${LOCAL_PORT:-9080}"
CONTEXT="kind-${CLUSTER_NAME}"

kubectl --context "${CONTEXT}" -n "${NAMESPACE}" \
  wait --for=condition=Available --timeout=120s deployment/productpage-v1

echo "Forwarding http://localhost:${LOCAL_PORT}/productpage  ->  svc/productpage:9080"
echo "Press Ctrl+C to stop."
kubectl --context "${CONTEXT}" -n "${NAMESPACE}" \
  port-forward svc/productpage "${LOCAL_PORT}:9080"
