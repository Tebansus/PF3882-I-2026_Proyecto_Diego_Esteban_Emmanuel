#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-bookinfo}"
NAMESPACE="${NAMESPACE:-bookinfo}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBE_DIR="${SCRIPT_DIR}/../platform/kube"
CONTEXT="kind-${CLUSTER_NAME}"

if ! kubectl config get-contexts -o name | grep -qx "${CONTEXT}"; then
  echo "ERROR: context '${CONTEXT}' not found. Run 01-create-cluster.sh first." >&2
  exit 1
fi
kubectl config use-context "${CONTEXT}" >/dev/null

kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1 || \
  kubectl create namespace "${NAMESPACE}"

echo "Enabling Istio sidecar injection for namespace '${NAMESPACE}'..."
kubectl label namespace "${NAMESPACE}" istio-injection=enabled --overwrite

echo "Applying Bookinfo manifests to namespace '${NAMESPACE}'..."
kubectl -n "${NAMESPACE}" apply -f "${KUBE_DIR}/bookinfo.yaml"

echo "Applying Istio Gateway + VirtualService for Bookinfo..."
kubectl -n "${NAMESPACE}" apply -f "${SCRIPT_DIR}/../networking/bookinfo-gateway.yaml"

echo "Applying DestinationRule for reviews subsets..."
kubectl -n "${NAMESPACE}" apply -f "${SCRIPT_DIR}/../networking/destination-rules.yaml"
