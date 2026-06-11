#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-bookinfo}"
CONTEXT="kind-${CLUSTER_NAME}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if ! kubectl config get-contexts -o name | grep -qx "${CONTEXT}"; then
  echo "ERROR: context '${CONTEXT}' not found. Run scripts/01-create-cluster.sh first." >&2
  exit 1
fi
kubectl config use-context "${CONTEXT}" >/dev/null

kubectl apply -f "${PROJECT_ROOT}/tracing/namespaces.yaml"

echo "Installing Jaeger..."
kubectl apply -f "${PROJECT_ROOT}/tracing/jaeger.yaml"

echo "Applying Kiali CRDs and custom resource..."
kubectl apply -f "${PROJECT_ROOT}/tracing/kiali-crd.yaml"
kubectl wait --for condition=established --timeout=60s crd/kialis.kiali.io
kubectl apply -f "${PROJECT_ROOT}/tracing/kiali-cr.yaml"

echo "Installing Kiali (addon deployment)..."
kubectl apply -f "${PROJECT_ROOT}/tracing/kiali.yaml"

echo "Applying Telemetry config (100% sampling) for bookinfo..."
kubectl apply -f "${PROJECT_ROOT}/tracing/telemetry-bookinfo.yaml"

echo "Waiting for tracing deployments to be available..."
kubectl -n jaeger wait deployment/jaeger --for=condition=Available --timeout=180s
kubectl -n kiali wait deployment/kiali --for=condition=Available --timeout=180s

echo "Tracing stack installed successfully."
echo "Access Kiali with:  kubectl -n kiali port-forward svc/kiali 20001:20001"
echo "Access Jaeger with: kubectl -n jaeger port-forward svc/tracing 16686:80"
