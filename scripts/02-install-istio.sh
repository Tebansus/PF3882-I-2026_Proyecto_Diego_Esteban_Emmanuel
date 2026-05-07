#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-bookinfo}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ISTIO_PROFILE="${SCRIPT_DIR}/../demo-profile-no-gateways.yaml"
CONTEXT="kind-${CLUSTER_NAME}"

# Check if required commands are available
for cmd in kubectl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: '$cmd' not found in PATH" >&2
    exit 1
  fi
done

# Check if context exists
if ! kubectl config get-contexts -o name | grep -qx "${CONTEXT}"; then
  echo "ERROR: context '${CONTEXT}' not found. Run 01-create-cluster.sh first." >&2
  exit 1
fi
kubectl config use-context "${CONTEXT}" >/dev/null

# Check if istioctl is available (assumed installed locally)
if ! command -v istioctl >/dev/null 2>&1; then
  echo "ERROR: istioctl not found. Please install Istio CLI first." >&2
  echo "Download from: https://istio.io/latest/docs/setup/getting-started/" >&2
  exit 1
fi

# Check if Istio is already installed
if kubectl get namespace istio-system >/dev/null 2>&1; then
  echo "Istio is already installed. Skipping installation."
else
  echo "Installing Istio control plane using profile: ${ISTIO_PROFILE}"
  istioctl install -f "${ISTIO_PROFILE}" --skip-confirmation
fi

# Wait for istiod to be ready
echo "Waiting for Istio control plane (istiod) to be ready..."
kubectl wait --for=condition=Available --timeout=300s deployment/istiod -n istio-system

echo "Istio control plane installed successfully."
echo
kubectl get pods -n istio-system