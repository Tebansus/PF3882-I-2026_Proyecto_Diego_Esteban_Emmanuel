#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="${NAMESPACE:-bookinfo}"
CLUSTER_NAME="${CLUSTER_NAME:-bookinfo}"
ROUTING_MODE="${ROUTING_MODE:-canary}"

if [[ "${ROUTING_MODE}" != "canary" && "${ROUTING_MODE}" != "header" ]]; then
  echo "ERROR: ROUTING_MODE must be 'canary' or 'header'" >&2
  exit 1
fi

echo "Running 01-create-cluster.sh: create the kind cluster"
bash "${SCRIPT_DIR}/01-create-cluster.sh"
echo
echo "Running 02-install-istio.sh: install Istio control plane"
bash "${SCRIPT_DIR}/02-install-istio.sh"
echo
echo "Running 03-deploy-bookinfo.sh: deploy Bookinfo application and gateway"
bash "${SCRIPT_DIR}/03-deploy-bookinfo.sh"
echo

echo "Selected routing mode: ${ROUTING_MODE}"
echo

if [[ "${ROUTING_MODE}" == "canary" ]]; then
  echo "Switching to canary reviews routing"
  kubectl -n "${NAMESPACE}" delete virtualservice reviews-combined --ignore-not-found=true
  kubectl -n "${NAMESPACE}" apply -f "${SCRIPT_DIR}/../networking/virtual-service-canary.yaml"
fi

if [[ "${ROUTING_MODE}" == "header" ]]; then
  echo "Switching to header-based reviews routing"
  kubectl -n "${NAMESPACE}" delete virtualservice reviews-canary --ignore-not-found=true
  kubectl -n "${NAMESPACE}" apply -f "${SCRIPT_DIR}/../networking/combined-virtual-service.yaml"
  echo "Waiting for Istio to reconcile header routing..."
  sleep 5
fi

echo "Waiting for all deployments to become Available (timeout: 5m)..."
kubectl -n "${NAMESPACE}" wait --for=condition=Available --timeout=300s deployment --all

echo
kubectl -n "${NAMESPACE}" get pods -o wide
echo
kubectl -n "${NAMESPACE}" get svc

echo "Running 05-validate.sh: verify Bookinfo is reachable through the ingress"
bash "${SCRIPT_DIR}/05-validate.sh"
echo
echo "Running 06-install-metrics.sh: install Prometheus and Grafana"
bash "${SCRIPT_DIR}/06-install-metrics.sh"
echo
echo "Running 07-install-tracing.sh: install Jaeger, Kiali, and tracing"
bash "${SCRIPT_DIR}/07-install-tracing.sh"
echo

if [[ "${ROUTING_MODE}" == "canary" ]]; then
  echo "Running 10-verify-canary.sh: validate the reviews canary deployment"
  bash "${SCRIPT_DIR}/10-verify-canary.sh"
fi

if [[ "${ROUTING_MODE}" == "header" ]]; then
  echo "Running 11-test-header-routing.sh: exercise header-based reviews routing"
  bash "${SCRIPT_DIR}/11-test-header-routing.sh"
fi

echo
echo "Running 08-start-load-generator.sh: start the load generator"
bash "${SCRIPT_DIR}/08-start-load-generator.sh"
echo

echo
echo "Done. Bookinfo is live at: http://localhost:31080/productpage"
echo "Grafana: http://localhost:3000"
echo "Kiali:   http://localhost:20001/kiali"
echo "Jaeger:  http://localhost:16686/jaeger"
