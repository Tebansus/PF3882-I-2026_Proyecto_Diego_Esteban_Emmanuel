#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-bookinfo}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../kind-config.yaml"

for cmd in docker kind kubectl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: '$cmd' not found in PATH" >&2
    exit 1
  fi
done

if ! docker info >/dev/null 2>&1; then
  echo "ERROR: docker daemon is not reachable. Start Docker Desktop and retry." >&2
  exit 1
fi

if kind get clusters | grep -qx "${CLUSTER_NAME}"; then
  echo "Cluster '${CLUSTER_NAME}' already exists. Skipping creation."
else
  echo "Creating kind cluster '${CLUSTER_NAME}' from ${CONFIG_FILE}..."
  kind create cluster --name "${CLUSTER_NAME}" --config "${CONFIG_FILE}"
fi

kubectl cluster-info --context "kind-${CLUSTER_NAME}"
kubectl get nodes -o wide
